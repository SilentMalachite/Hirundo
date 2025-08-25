import Foundation
@preconcurrency import Swifter

// Weak wrapper for WebSocket sessions to prevent memory leaks
private class WeakWebSocketSession {
    weak var session: WebSocketSession?
    
    init(_ session: WebSocketSession) {
        self.session = session
    }
}

public final class DevelopmentServer: @unchecked Sendable {
    private let projectPath: String
    private let port: Int
    private let host: String
    private let liveReload: Bool
    private let corsConfig: CorsConfig?
    private let websocketAuth: WebSocketAuthConfig?
    private let server: HttpServer
    private let fileManager: FileManager
    private var hotReloadManager: HotReloadManager?
    private var websocketSessions: [WeakWebSocketSession] = []
    private let sessionsQueue = DispatchQueue(label: "websocket.sessions", attributes: .concurrent)
    private var cleanupTimer: Timer?
    
    // Authentication properties
    private var tokenStore: [String: Date] = [:] // token -> expiry
    private var authenticatedSessions: Set<ObjectIdentifier> = []
    private let authQueue = DispatchQueue(label: "auth.tokens", attributes: .concurrent)
    
    public init(projectPath: String, port: Int, host: String, liveReload: Bool, corsConfig: CorsConfig? = nil, fileManager: FileManager = .default, websocketAuth: WebSocketAuthConfig? = nil) {
        self.fileManager = fileManager
        self.projectPath = projectPath
        self.port = port
        self.host = host
        self.liveReload = liveReload
        self.corsConfig = corsConfig ?? CorsConfig()
        self.websocketAuth = websocketAuth
        self.server = HttpServer()
        
        setupRoutes()
    }
    
    public func start() async throws {
        try server.start(UInt16(port), forceIPv4: false, priority: .default)
        
        startCleanupTimer()
        
        if liveReload {
            try await startFileWatcher()
        }
        
        print("Development server started at http://\(host):\(port)")
    }
    
    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.performPeriodicCleanup()
        }
    }
    
    private func setupRoutes() {
        let outputPath = URL(fileURLWithPath: projectPath).appendingPathComponent("_site").path
        
        // Auth token endpoint
        server["/auth-token"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            
            guard request.method == "GET" else {
                return .badRequest(.text("Method not allowed"))
            }
            
            let token = self.generateAuthToken()
            let expiresIn = (self.websocketAuth?.tokenExpirationMinutes ?? 60)
            let json = """
            {"token":"\(token)","expiresIn":\(expiresIn),"endpoint":"/livereload"}
            """
            var headers = self.getCorsHeaders(for: request)
            headers["Content-Type"] = "application/json; charset=utf-8"
            let data = Data(json.utf8)
            return .raw(200, "OK", headers) { writer in
                try writer.write(data)
            }
        }
        
        // Main route handler for static files
        server["/(.*)"] = { [weak self] request in
            return self?.handleStaticFileRequest(request, outputPath: outputPath) ?? .notFound
        }
        
        if liveReload {
            // WebSocket endpoint for live reload with auth
            server["/livereload"] = websocket(
                text: { [weak self] session, text in
                    guard let self = self else { return }
                    // Handle JSON messages for auth / control
                    if let data = text.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = obj["type"] as? String {
                        if type == "auth" {
                            let token = obj["token"] as? String
                            if self.authenticateWebSocketConnection(session, token: token) {
                                let id = ObjectIdentifier(session)
                                self.authenticatedSessions.insert(id)
                                self.addWebSocketSession(session)
                                session.writeText("{\"type\":\"auth_success\",\"message\":\"Authentication successful\"}")
                            } else {
                                session.writeText("{\"type\":\"auth_error\",\"message\":\"Invalid or expired token\"}")
                                // Swifter's WebSocketSession may not expose a close API in this version.
                                // We simply don't register the session; it won't receive reload events.
                            }
                            return
                        }
                    }
                    // Simple ping/pong for keepalive (only after auth)
                    let id = ObjectIdentifier(session)
                    if text == "ping" && self.authenticatedSessions.contains(id) {
                        session.writeText("pong")
                    }
                },
                connected: { [weak self] session in
                    // Send authentication challenge on connect
                    self?.sendAuthChallenge(session)
                }
            )
        }
    }
    
    // MARK: - Authentication Methods
    
    public func generateAuthToken() -> String {
        // Generate secure alphanumeric token (length 40)
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var token = String()
        token.reserveCapacity(40)
        for _ in 0..<40 {
            let idx = Int(arc4random_uniform(UInt32(chars.count)))
            token.append(chars[idx])
        }
        
        let minutes = websocketAuth?.tokenExpirationMinutes ?? 60
        let expiry = Date().addingTimeInterval(TimeInterval(minutes * 60))
        
        authQueue.async(flags: .barrier) { [weak self, token, expiry] in
            guard let self = self else { return }
            // Enforce max active tokens
            let maxTokens = self.websocketAuth?.maxActiveTokens ?? 100
            if self.tokenStore.count >= maxTokens {
                // Remove the earliest-expiring tokens
                let sorted = self.tokenStore.sorted { $0.value < $1.value }
                for (k, _) in sorted.prefix(self.tokenStore.count - maxTokens + 1) {
                    self.tokenStore.removeValue(forKey: k)
                }
            }
            self.tokenStore[token] = expiry
        }
        
        return token
    }
    
    public func getAuthTokenEndpoint() -> String {
        return "/auth-token"
    }
    
    public func validateAuthToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        
        return authQueue.sync {
            if let expiry = tokenStore[token] {
                if expiry > Date() {
                    return true
                } else {
                    // Expired
                    tokenStore.removeValue(forKey: token)
                    return false
                }
            }
            return false
        }
    }
    
    public func authenticateWebSocketConnection(_ session: Any, token: String?) -> Bool {
        guard websocketAuth?.enabled ?? true else { return true }
        guard let token = token else { return false }
        return validateAuthToken(token)
    }
    
    public func expireAuthToken(_ token: String) {
        authQueue.async(flags: .barrier) { [weak self] in
            self?.tokenStore.removeValue(forKey: token)
        }
    }
    
    private func handleStaticFileRequest(_ request: HttpRequest, outputPath: String) -> HttpResponse {
        let requestPath = request.path == "/" ? "/index.html" : request.path
        let filePath = outputPath + requestPath
        
        // Secure path traversal protection
        let canonicalBasePath = URL(fileURLWithPath: outputPath).standardized.path
        let canonicalRequestPath = URL(fileURLWithPath: filePath).standardized.path
        
        guard canonicalRequestPath.hasPrefix(canonicalBasePath) else {
            return .forbidden
        }
        
        // CORS handling
        if request.method == "OPTIONS" {
            return .raw(204, "No Content", getCorsHeaders(for: request)) { _ in }
        }
        
        guard fileManager.fileExists(atPath: filePath) else {
            return .notFound
        }
        
        return serveFile(at: filePath, request: request)
    }
    
    private func handleWebSocketConnection(_ session: WebSocketSession) {
        // Authentication is required before adding to broadcast list
        sendAuthChallenge(session)
    }

    
    private func sendAuthChallenge(_ session: WebSocketSession) {
        let message = "{\"type\":\"auth_required\",\"message\":\"Please provide authentication token\"}"
        session.writeText(message)
    }
    
    private func getCorsHeaders(for request: HttpRequest) -> [String: String] {
        guard let corsConfig = corsConfig, corsConfig.enabled else {
            return [:]
        }
        
        var headers: [String: String] = [:]
        
        // Check origin
        let origin = request.headers["origin"] ?? request.headers["Origin"] ?? ""
        
        // Check if origin is allowed
        var isOriginAllowed = false
        for allowedOrigin in corsConfig.allowedOrigins {
            if allowedOrigin == "*" {
                isOriginAllowed = true
                break
            }
            if allowedOrigin.contains("*") {
                // Secure wildcard matching with proper escaping
                let escapedPattern = NSRegularExpression.escapedPattern(for: allowedOrigin)
                let pattern = escapedPattern.replacingOccurrences(of: "\\*", with: ".*")
                if let regex = try? NSRegularExpression(pattern: "^" + pattern + "$", options: []),
                   regex.firstMatch(in: origin, options: [], range: NSRange(location: 0, length: origin.count)) != nil {
                    isOriginAllowed = true
                    break
                }
            } else if origin == allowedOrigin {
                isOriginAllowed = true
                break
            }
        }
        
        if isOriginAllowed {
            headers["Access-Control-Allow-Origin"] = origin.isEmpty ? "*" : origin
        }
        
        headers["Access-Control-Allow-Methods"] = corsConfig.allowedMethods.joined(separator: ", ")
        headers["Access-Control-Allow-Headers"] = corsConfig.allowedHeaders.joined(separator: ", ")
        
        if let exposedHeaders = corsConfig.exposedHeaders {
            headers["Access-Control-Expose-Headers"] = exposedHeaders.joined(separator: ", ")
        }
        
        if let maxAge = corsConfig.maxAge {
            headers["Access-Control-Max-Age"] = String(maxAge)
        }
        
        if corsConfig.allowCredentials {
            headers["Access-Control-Allow-Credentials"] = "true"
        }
        
        return headers
    }
    
    private func serveFile(at path: String, request: HttpRequest) -> HttpResponse {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let fileExtension = URL(fileURLWithPath: path).pathExtension
            let contentType = mimeType(for: fileExtension)
            
            var headers = [
                "Content-Type": contentType,
                "Cache-Control": "no-cache, no-store, must-revalidate"
            ]
            
            // Add CORS headers if configured
            let corsHeaders = getCorsHeaders(for: request)
            for (key, value) in corsHeaders {
                headers[key] = value
            }
            
            // Add live reload script injection for HTML files
            if liveReload && contentType.contains("text/html") {
                if var htmlString = String(data: data, encoding: .utf8) {
                    let liveReloadScript = """
                    <script>
                    (function() {
                        async function initLiveReload() {
                            try {
                                const resp = await fetch('/auth-token', { method: 'GET', credentials: 'include' });
                                const info = await resp.json();
                                const token = info.token;
                                const ws = new WebSocket('ws://\(host):\(port)/livereload');
                                ws.onopen = function() {
                                    ws.send(JSON.stringify({ type: 'auth', token }));
                                };
                                ws.onmessage = function(event) {
                                    try {
                                        const data = JSON.parse(event.data);
                                        if (data.type === 'auth_success') {
                                            // authenticated
                                        } else if (data.type === 'reload') {
                                            window.location.reload();
                                        } else if (data.type === 'error') {
                                            console.error('Build error:', data.message);
                                        } else if (data.type === 'auth_error') {
                                            console.error('LiveReload auth failed.');
                                        }
                                    } catch (_) { /* ignore */ }
                                };
                                ws.onclose = function() {
                                    setTimeout(() => window.location.reload(), 2000);
                                };
                                // Ping every 30 seconds to keep connection alive
                                setInterval(() => {
                                    if (ws.readyState === WebSocket.OPEN) {
                                        ws.send('ping');
                                    }
                                }, 30000);
                            } catch (e) {
                                console.error('LiveReload init failed:', e);
                            }
                        }
                        initLiveReload();
                    })();
                    </script>
                    """
                    
                    // Inject before closing body tag or at the end
                    if let bodyEndRange = htmlString.range(of: "</body>", options: .caseInsensitive) {
                        htmlString.insert(contentsOf: liveReloadScript, at: bodyEndRange.lowerBound)
                    } else {
                        htmlString.append(liveReloadScript)
                    }
                    
                    let modifiedData = htmlString.data(using: .utf8) ?? data
                    return .raw(200, "OK", headers) { writer in
                        try writer.write(modifiedData)
                    }
                }
            }
            
            return .raw(200, "OK", headers) { writer in
                try writer.write(data)
            }
        } catch {
            return .internalServerError
        }
    }
    
    private func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "txt": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
    
    private func startFileWatcher() async throws {
        let contentPaths = [
            URL(fileURLWithPath: projectPath).appendingPathComponent("content").path,
            URL(fileURLWithPath: projectPath).appendingPathComponent("templates").path,
            URL(fileURLWithPath: projectPath).appendingPathComponent("static").path,
            URL(fileURLWithPath: projectPath).appendingPathComponent("config.yaml").path
        ]
        
        // Filter out non-existent paths
        let watchPaths = contentPaths.filter { fileManager.fileExists(atPath: $0) }
        
        guard !watchPaths.isEmpty else {
            print("No paths to watch for changes")
            return
        }
        
        hotReloadManager = HotReloadManager(
            watchPaths: watchPaths
        ) { [weak self] changes in
            guard let self = self else { return }
            Task {
                do {
                    // Rebuild the site
                    let generator = try SiteGenerator(projectPath: self.projectPath)
                    try await generator.build()
                    
                    // Notify clients to reload
                    await MainActor.run {
                        self.notifyClientsToReload()
                    }
                } catch {
                    // Notify clients of the error
                    await MainActor.run {
                        self.recordBuildError(error, changes: changes)
                    }
                }
            }
        }
        
        try await hotReloadManager?.start()
    }
    
    private func addWebSocketSession(_ session: WebSocketSession) {
        sessionsQueue.async(flags: .barrier) { [weak self] in
            self?.websocketSessions.append(WeakWebSocketSession(session))
            // Clean up nil sessions
            self?.websocketSessions = self?.websocketSessions.filter { $0.session != nil } ?? []
        }
    }
    
    private func removeWebSocketSession(_ session: WebSocketSession) {
        sessionsQueue.async(flags: .barrier) { [weak self] in
            self?.websocketSessions = self?.websocketSessions.filter { weakSession in
                guard let strongSession = weakSession.session else { return false }
                return strongSession !== session
            } ?? []
        }
    }
    
    // Periodic cleanup of disconnected sessions
    private func performPeriodicCleanup() {
        // Cleanup sessions
        sessionsQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let initialCount = self.websocketSessions.count
            self.websocketSessions = self.websocketSessions.filter { $0.session != nil }
            let cleanedCount = initialCount - self.websocketSessions.count
            
            if cleanedCount > 0 {
                print("🧹 Cleaned up \(cleanedCount) disconnected WebSocket sessions")
            }
        }
        // Cleanup expired tokens
        authQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let now = Date()
            self.tokenStore = self.tokenStore.filter { _, expiry in expiry > now }
        }
    }
    
    private func notifyClientsToReload() {
        sessionsQueue.sync {
            let message = """
            {
                "type": "reload",
                "timestamp": \(Date().timeIntervalSince1970)
            }
            """
            
            for weakSession in websocketSessions {
                weakSession.session?.writeText(message)
            }
        }
    }
    
    private func notifyClientsOfError(_ error: String) {
        sessionsQueue.sync {
            let escapedError = error
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            
            let message = """
            {
                "type": "error",
                "message": "\(escapedError)",
                "timestamp": \(Date().timeIntervalSince1970)
            }
            """
            
            for weakSession in websocketSessions {
                weakSession.session?.writeText(message)
            }
        }
    }
    
    private func recordBuildError(_ error: Error, changes: [FileChange]) {
        // Extract relevant error information
        var errorMessage = "Build failed: "
        
        if let hirundoError = error as? HirundoError {
            errorMessage += hirundoError.userMessage
        } else {
            errorMessage += error.localizedDescription
        }
        
        // Add file change context
        if !changes.isEmpty {
            errorMessage += "\n\nTriggered by changes to:"
            for change in changes.prefix(5) {
                let fileName = URL(fileURLWithPath: change.path).lastPathComponent
                errorMessage += "\n  - \(fileName) (\(change.type))"
            }
            if changes.count > 5 {
                errorMessage += "\n  ... and \(changes.count - 5) more files"
            }
        }
        
        // Notify connected clients
        notifyClientsOfError(errorMessage)
        
        // Also log to console
        print("❌ Build Error:")
        print(errorMessage)
    }
    
    deinit {
        cleanupTimer?.invalidate()
        server.stop()
        Task { [hotReloadManager] in
            await hotReloadManager?.stop()
        }
    }
}

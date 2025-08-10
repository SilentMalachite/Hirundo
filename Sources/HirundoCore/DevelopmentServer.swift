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
    private let websocketAuthConfig: WebSocketAuthConfig?
    private let server: HttpServer
    private let fileManager: FileManager
    private var hotReloadManager: HotReloadManager?
    private var websocketSessions: [WeakWebSocketSession] = []
    private let sessionsQueue = DispatchQueue(label: "websocket.sessions", attributes: .concurrent)
    private var cleanupTimer: Timer?
    
    // Authentication token storage
    private var activeTokens: Set<String> = []
    private var tokenExpirationDates: [String: Date] = [:]
    private let authQueue = DispatchQueue(label: "websocket.auth", attributes: .concurrent)
    
    // CSRF token storage for WebSocket connections
    private var csrfTokens: [String: (token: String, expires: Date)] = [:]
    private let csrfQueue = DispatchQueue(label: "csrf.tokens", attributes: .concurrent)
    
    // Rate limiting for auth endpoint
    private var authRequestCounts: [String: (count: Int, resetTime: Date)] = [:]
    private let rateLimitQueue = DispatchQueue(label: "rate.limit", attributes: .concurrent)
    private let maxAuthRequestsPerMinute = 10
    
    public init(projectPath: String, port: Int, host: String, liveReload: Bool, corsConfig: CorsConfig? = nil, websocketAuthConfig: WebSocketAuthConfig? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.projectPath = projectPath
        self.port = port
        self.host = host
        self.liveReload = liveReload
        self.corsConfig = corsConfig ?? CorsConfig() // Use default CORS config if not provided
        self.websocketAuthConfig = websocketAuthConfig ?? WebSocketAuthConfig() // Use default auth config if not provided
        self.server = HttpServer()
        
        setupRoutes()
    }
    
    public func start() throws {
        try server.start(UInt16(port), forceIPv4: false, priority: .default)
        
        if liveReload {
            startFileWatcher()
            startCleanupTimer()
        }
        
        // Keep the server running
        RunLoop.current.run()
    }
    
    private func startCleanupTimer() {
        // Schedule periodic cleanup every 30 seconds
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.performPeriodicCleanup()
        }
    }
    
    private func setupRoutes() {
        let outputPath = URL(fileURLWithPath: projectPath).appendingPathComponent("_site").path
        
        // Handle all requests
        server["/(.*)"] = { [weak self] request in
            guard let self = self else { return .internalServerError }
            
            // Handle CORS preflight requests
            if request.method == "OPTIONS" {
                if let corsConfig = self.corsConfig, corsConfig.enabled {
                    var headers = self.getCorsHeaders(for: request)
                    headers["Content-Length"] = "0"
                    return .raw(204, "No Content", headers) { _ in }
                }
                return .raw(204, "No Content", [:]) { _ in }
            }
            
            // Handle auth token endpoint  
            if request.path == "/auth-token" {
                return self.handleAuthTokenRequest(request)
            }
            
            // Handle static file requests
            return self.handleStaticFileRequest(request, outputPath: outputPath)
        }
        
        // Live reload endpoint
        if liveReload {
            server["/livereload"] = websocket(text: { [weak self] session, text in
                self?.handleWebSocketMessage(session, text: text)
            }, binary: { session, binary in
                // Not used
            }, pong: { session, _ in
                // Keep alive
            }, connected: { [weak self] session in
                self?.handleWebSocketConnection(session)
            }, disconnected: { [weak self] session in
                self?.removeWebSocketSession(session)
            })
        }
    }
    
    private func handleStaticFileRequest(_ request: HttpRequest, outputPath: String) -> HttpResponse {
        let filePath = request.path == "/" ? "/index.html" : request.path
        let fullPath = outputPath + filePath
        
        // Try exact path first
        if fileManager.fileExists(atPath: fullPath) {
            return serveFile(at: fullPath, request: request)
        }
        
        // Try as directory with index.html
        let indexPath = fullPath + "/index.html"
        if fileManager.fileExists(atPath: indexPath) {
            return serveFile(at: indexPath, request: request)
        }
        
        // 404 with CORS headers if enabled
        if let corsConfig = corsConfig, corsConfig.enabled {
            let headers = getCorsHeaders(for: request)
            return .raw(404, "Not Found", headers) { writer in
                try writer.write("404 Not Found".data(using: .utf8)!)
            }
        }
        
        return .notFound
    }
    
    private func handleAuthTokenRequest(_ request: HttpRequest) -> HttpResponse {
        // Get client IP for rate limiting
        let clientIP = request.headers["x-forwarded-for"] ?? request.address ?? "unknown"
        
        // Check rate limit
        if !checkRateLimit(for: clientIP) {
            return .raw(429, "Too Many Requests", ["Retry-After": "60"]) { writer in
                try writer.write("Rate limit exceeded. Please try again later.".data(using: .utf8)!)
            }
        }
        
        // Generate CSRF token for this session
        let csrfToken = generateSecureToken(length: 32)
        let authToken = generateSecureToken(length: 64)
        
        // Store CSRF token with expiration
        let expirationMinutes = websocketAuthConfig?.tokenExpirationMinutes ?? 60
        let expirationDate = Date().addingTimeInterval(TimeInterval(expirationMinutes * 60))
        
        csrfQueue.async(flags: .barrier) {
            self.csrfTokens[authToken] = (token: csrfToken, expires: expirationDate)
        }
        
        // Store auth token
        authQueue.async(flags: .barrier) {
            self.activeTokens.insert(authToken)
            self.tokenExpirationDates[authToken] = expirationDate
        }
        
        let tokenResponse: [String: Any] = [
            "token": authToken,
            "csrfToken": csrfToken,
            "expiresIn": expirationMinutes,
            "endpoint": "/livereload"
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: tokenResponse)
            var headers = ["Content-Type": "application/json"]
            
            // Add CORS headers if enabled
            if let corsConfig = corsConfig, corsConfig.enabled {
                let corsHeaders = getCorsHeaders(for: request)
                headers.merge(corsHeaders) { _, new in new }
            }
            
            return .raw(200, "OK", headers) { writer in
                try writer.write(jsonData)
            }
        } catch {
            return .internalServerError
        }
    }
    
    private func handleWebSocketConnection(_ session: WebSocketSession) {
        // Note: With the current Swifter API, we can't directly access query parameters
        // in the WebSocket connection handler. In a real implementation, we would need
        // to parse the WebSocket handshake request or use a different approach.
        // For now, we'll implement a simplified version where authentication is handled
        // at the application level through message exchange.
        
        guard let websocketAuthConfig = websocketAuthConfig, websocketAuthConfig.enabled else {
            // If authentication is disabled, allow all connections
            addWebSocketSession(session)
            return
        }
        
        // For demonstration purposes, we'll accept the connection but expect
        // the first message to be an authentication token
        addWebSocketSession(session)
        
        // Send authentication challenge
        let authChallenge = [
            "type": "auth_required",
            "message": "Please provide authentication token"
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: authChallenge),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            session.writeText(jsonString)
        }
    }
    
    private func handleWebSocketMessage(_ session: WebSocketSession, text: String) {
        // Parse incoming message
        guard let messageData = text.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
              let messageType = message["type"] as? String else {
            // If not a JSON message, ignore (for backward compatibility)
            return
        }
        
        switch messageType {
        case "auth":
            handleAuthMessage(session, message: message)
        default:
            // Unknown message type, ignore
            break
        }
    }
    
    private func handleAuthMessage(_ session: WebSocketSession, message: [String: Any]) {
        guard let token = message["token"] as? String else {
            sendAuthError(session, message: "Invalid auth message format")
            return
        }
        
        if validateAuthToken(token) {
            // Mark session as authenticated (we'd need to track this in practice)
            sendAuthSuccess(session)
        } else {
            sendAuthError(session, message: "Invalid or expired token")
        }
    }
    
    private func sendAuthSuccess(_ session: WebSocketSession) {
        let response = [
            "type": "auth_success",
            "message": "Authentication successful"
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: response),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            session.writeText(jsonString)
        }
    }
    
    private func sendAuthError(_ session: WebSocketSession, message: String) {
        let response = [
            "type": "auth_error",
            "message": message
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: response),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            session.writeText(jsonString)
        }
        
        // Close the connection after authentication failure
        // Note: In Swifter, we can't directly close WebSocket connections
        // This should be handled at the application level
    }
    
    // Helper method to get CORS headers based on request origin
    private func getCorsHeaders(for request: HttpRequest) -> [String: String] {
        var headers: [String: String] = [:]
        
        guard let corsConfig = corsConfig, corsConfig.enabled else {
            return headers
        }
        
        // Get request origin
        let origin = request.headers["origin"] ?? ""
        
        // Check if origin is allowed
        let isAllowedOrigin = corsConfig.allowedOrigins.contains { allowedOrigin in
            if allowedOrigin == "*" {
                return true
            }
            // Support wildcard ports (e.g., http://localhost:*)
            if allowedOrigin.contains("*") {
                let pattern = allowedOrigin.replacingOccurrences(of: "*", with: "[0-9]+")
                return origin.range(of: pattern, options: .regularExpression) != nil
            }
            return origin == allowedOrigin
        }
        
        if isAllowedOrigin {
            headers["Access-Control-Allow-Origin"] = origin
        } else if corsConfig.allowedOrigins.contains("*") {
            headers["Access-Control-Allow-Origin"] = "*"
        }
        
        // Add other CORS headers
        if !corsConfig.allowedMethods.isEmpty {
            headers["Access-Control-Allow-Methods"] = corsConfig.allowedMethods.joined(separator: ", ")
        }
        
        if !corsConfig.allowedHeaders.isEmpty {
            headers["Access-Control-Allow-Headers"] = corsConfig.allowedHeaders.joined(separator: ", ")
        }
        
        if let exposedHeaders = corsConfig.exposedHeaders, !exposedHeaders.isEmpty {
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
        guard let data = fileManager.contents(atPath: path) else {
            return .notFound
        }
        
        let mimeType = mimeType(for: path)
        var headers = ["Content-Type": mimeType]
        
        // Add CORS headers if enabled
        if let corsConfig = corsConfig, corsConfig.enabled {
            let corsHeaders = getCorsHeaders(for: request)
            headers.merge(corsHeaders) { _, new in new }
        }
        
        // Inject live reload script for HTML files
        if liveReload && mimeType == "text/html",
           var content = String(data: data, encoding: .utf8) {
            let authEnabled = websocketAuthConfig?.enabled ?? true
            let script = """
                <script>
                (function() {
                    let lastReload = Date.now();
                    let authenticated = false;
                    let authToken = null;
                    
                    function connectWebSocket() {
                        let ws = new WebSocket('ws://\(host):\(port)/livereload');
                        
                        ws.onopen = function() {
                            console.log('WebSocket connected');
                            if (\(authEnabled)) {
                                // Fetch auth token and authenticate
                                fetchAuthToken().then(token => {
                                    authToken = token;
                                    // Send auth token as first message
                                    ws.send(JSON.stringify({type: 'auth', token: token}));
                                }).catch(err => {
                                    console.error('Failed to get auth token:', err);
                                    ws.close();
                                });
                            } else {
                                authenticated = true;
                            }
                        };
                        
                        ws.onmessage = function(event) {
                            try {
                                const data = JSON.parse(event.data);
                                if (data.type === 'auth_required') {
                                    // Server requesting authentication
                                    if (authToken) {
                                        ws.send(JSON.stringify({type: 'auth', token: authToken}));
                                    }
                                } else if (data.type === 'auth_success') {
                                    authenticated = true;
                                    console.log('WebSocket authenticated');
                                } else if (data.type === 'auth_error') {
                                    console.error('WebSocket authentication failed:', data.message);
                                    ws.close();
                                }
                            } catch (e) {
                                // Handle plain text messages for backward compatibility
                                if (event.data === 'reload' && authenticated && Date.now() - lastReload > 1000) {
                                    lastReload = Date.now();
                                    location.reload();
                                }
                            }
                        };
                        
                        ws.onclose = function() {
                            console.log('WebSocket disconnected');
                            setTimeout(function() {
                                location.reload();
                            }, 2000);
                        };
                        
                        ws.onerror = function(error) {
                            console.error('WebSocket error:', error);
                        };
                    }
                    
                    async function fetchAuthToken() {
                        const response = await fetch('/auth-token');
                        if (!response.ok) {
                            throw new Error('Failed to get auth token');
                        }
                        const data = await response.json();
                        return data.token;
                    }
                    
                    // Start connection
                    connectWebSocket();
                })();
                </script>
                </body>
                """
            content = content.replacingOccurrences(of: "</body>", with: script)
            return .ok(.html(content))
        }
        
        return .raw(200, "OK", headers) { writer in
            try writer.write(data)
        }
    }
    
    private func mimeType(for path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "eot": return "application/vnd.ms-fontobject"
        default: return "application/octet-stream"
        }
    }
    
    private func startFileWatcher() {
        let watchPaths = [
            URL(fileURLWithPath: projectPath).appendingPathComponent("content").path,
            URL(fileURLWithPath: projectPath).appendingPathComponent("templates").path,
            URL(fileURLWithPath: projectPath).appendingPathComponent("static").path,
            URL(fileURLWithPath: projectPath).appendingPathComponent("config.yaml").path
        ]
        
        hotReloadManager = HotReloadManager(
            watchPaths: watchPaths,
            debounceInterval: 0.5,
            ignorePatterns: ["_site", ".git", ".hirundo-cache"]
        ) { [weak self] changes in
            guard let self = self else { return }
            
            // Log changes
            for change in changes {
                let changeType: String
                switch change.type {
                case .created: changeType = "➕"
                case .modified: changeType = "📝"
                case .deleted: changeType = "🗑"
                case .renamed: changeType = "🔄"
                }
                print("\(changeType) \(URL(fileURLWithPath: change.path).lastPathComponent)")
            }
            
            // Rebuild site
            do {
                print("🔨 Rebuilding...")
                let generator = try SiteGenerator(projectPath: self.projectPath)
                try generator.build()
                print("✅ Rebuild complete")
                
                // Notify connected clients to reload
                self.notifyClientsToReload()
            } catch {
                let errorMessage = "❌ Rebuild failed: \(error.localizedDescription)"
                print(errorMessage)
                
                // Notify clients about the error
                self.notifyClientsOfError(errorMessage)
                
                // Try to record the error for debugging
                self.recordBuildError(error, changes: changes)
            }
        }
        
        Task {
            do {
                try await hotReloadManager?.start()
            } catch {
                print("⚠️ Failed to start file watcher: \(error.localizedDescription)")
            }
        }
    }
    
    private func addWebSocketSession(_ session: WebSocketSession) {
        sessionsQueue.async(flags: .barrier) {
            // Clean up any nil sessions before adding new one
            self.websocketSessions.removeAll { $0.session == nil }
            
            self.websocketSessions.append(WeakWebSocketSession(session))
            
            // Log session count for debugging
            print("WebSocket connected. Active sessions: \(self.websocketSessions.count)")
        }
    }
    
    private func removeWebSocketSession(_ session: WebSocketSession) {
        sessionsQueue.async(flags: .barrier) {
            let initialCount = self.websocketSessions.count
            
            self.websocketSessions.removeAll { weakSession in
                guard let existingSession = weakSession.session else {
                    return true // Remove nil sessions
                }
                return existingSession === session
            }
            
            let finalCount = self.websocketSessions.count
            if finalCount != initialCount {
                print("WebSocket disconnected. Active sessions: \(finalCount)")
            }
        }
    }
    
    // Periodic cleanup method to prevent memory leaks
    private func performPeriodicCleanup() {
        sessionsQueue.async(flags: .barrier) {
            let initialCount = self.websocketSessions.count
            self.websocketSessions.removeAll { $0.session == nil }
            let finalCount = self.websocketSessions.count
            
            if finalCount != initialCount {
                print("Cleaned up \(initialCount - finalCount) dead WebSocket sessions")
            }
        }
    }
    
    private func notifyClientsToReload() {
        sessionsQueue.async(flags: .barrier) {
            // Clean up nil sessions first
            self.websocketSessions.removeAll { $0.session == nil }
            
            // Notify active sessions
            for weakSession in self.websocketSessions {
                if let session = weakSession.session {
                    session.writeText("reload")
                }
            }
        }
    }
    
    private func notifyClientsOfError(_ errorMessage: String) {
        sessionsQueue.async(flags: .barrier) {
            // Clean up nil sessions first
            self.websocketSessions.removeAll { $0.session == nil }
            
            // Notify active sessions about the error
            let errorData = [
                "type": "error",
                "message": errorMessage,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: errorData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                for weakSession in self.websocketSessions {
                    if let session = weakSession.session {
                        session.writeText(jsonString)
                    }
                }
            }
        }
    }
    
    private func recordBuildError(_ error: Error, changes: [FileChange]) {
        // Create a detailed error record for debugging
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let changedFiles = changes.map { "\($0.type): \($0.path)" }.joined(separator: ", ")
        
        let errorRecord = """
        
        =================== BUILD ERROR ===================
        Time: \(timestamp)
        Changed Files: \(changedFiles)
        Error: \(error.localizedDescription)
        
        """
        
        // Log to stderr for better visibility in development
        fputs(errorRecord, stderr)
        
        // Optionally write to a log file for persistence
        let logPath = URL(fileURLWithPath: projectPath).appendingPathComponent(".hirundo-build.log").path
        if let logData = errorRecord.data(using: .utf8) {
            // Append to log file with proper resource management
            if let logFile = FileHandle(forWritingAtPath: logPath) {
                defer {
                    // Ensure file handle is always closed
                    logFile.closeFile()
                }
                logFile.seekToEndOfFile()
                logFile.write(logData)
            } else {
                // Create new log file with security validation
                do {
                    try FileSecurityUtilities.createFile(
                        atPath: logPath,
                        contents: logData,
                        attributes: nil,
                        basePath: projectPath
                    )
                } catch {
                    // If unable to create log file, just log to stderr
                    fputs("Warning: Unable to create log file: \(error)\n", stderr)
                }
            }
        }
    }
    
    // MARK: - WebSocket Authentication Methods
    
    /// Generates a secure authentication token for WebSocket connections
    public func generateAuthToken() -> String {
        let token = generateSecureToken(length: 64)
        
        // Add token to active tokens with expiration
        authQueue.sync(flags: .barrier) {
            activeTokens.insert(token)
            tokenExpirationDates[token] = Date().addingTimeInterval(3600) // 1 hour expiration
        }
        
        return token
    }
    
    /// Generates a cryptographically secure token using SecRandomCopyBytes
    private func generateSecureToken(length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var randomBytes = [UInt8](repeating: 0, count: length)
        
        // Use SecRandomCopyBytes for cryptographically secure random generation
        let result = SecRandomCopyBytes(kSecRandomDefault, length, &randomBytes)
        guard result == errSecSuccess else {
            // Fallback to less secure method if SecRandomCopyBytes fails (should never happen)
            print("Warning: SecRandomCopyBytes failed, falling back to arc4random")
            return (0..<length).map { _ in
                characters[Int(arc4random_uniform(UInt32(characters.count)))]
            }.map(String.init).joined()
        }
        
        // Convert random bytes to characters
        let token = randomBytes.map { byte in
            characters[Int(byte) % characters.count]
        }.map(String.init).joined()
        
        return token
    }
    
    /// Check rate limit for a given client IP
    private func checkRateLimit(for clientIP: String) -> Bool {
        let now = Date()
        var allowed = false
        
        rateLimitQueue.sync(flags: .barrier) {
            // Clean up old entries
            authRequestCounts = authRequestCounts.filter { _, value in
                value.resetTime > now
            }
            
            if let entry = authRequestCounts[clientIP] {
                if entry.resetTime > now {
                    // Within rate limit window
                    if entry.count < maxAuthRequestsPerMinute {
                        authRequestCounts[clientIP] = (count: entry.count + 1, resetTime: entry.resetTime)
                        allowed = true
                    }
                } else {
                    // Reset window expired
                    authRequestCounts[clientIP] = (count: 1, resetTime: now.addingTimeInterval(60))
                    allowed = true
                }
            } else {
                // First request from this IP
                authRequestCounts[clientIP] = (count: 1, resetTime: now.addingTimeInterval(60))
                allowed = true
            }
        }
        
        return allowed
    }
    
    /// Validates an authentication token
    public func validateAuthToken(_ token: String) -> Bool {
        return authQueue.sync {
            // Clean up expired tokens first
            cleanupExpiredTokens()
            
            // Check if token exists and is not expired
            guard activeTokens.contains(token),
                  let expirationDate = tokenExpirationDates[token] else {
                return false
            }
            
            return Date() < expirationDate
        }
    }
    
    /// Expires a specific token (for testing purposes)
    public func expireAuthToken(_ token: String) {
        authQueue.sync(flags: .barrier) {
            activeTokens.remove(token)
            tokenExpirationDates.removeValue(forKey: token)
        }
    }
    
    /// Authenticates a WebSocket connection
    public func authenticateWebSocketConnection(_ session: Any, token: String?) -> Bool {
        guard let websocketAuthConfig = websocketAuthConfig, websocketAuthConfig.enabled else {
            // If authentication is disabled, allow all connections
            return true
        }
        
        guard let token = token else {
            return false
        }
        
        return validateAuthToken(token)
    }
    
    /// Returns the auth token endpoint path
    public func getAuthTokenEndpoint() -> String {
        return "/auth-token"
    }
    
    /// Cleans up expired tokens
    private func cleanupExpiredTokens() {
        let now = Date()
        let expiredTokens = tokenExpirationDates.compactMap { (token, expiration) in
            now >= expiration ? token : nil
        }
        
        for expiredToken in expiredTokens {
            activeTokens.remove(expiredToken)
            tokenExpirationDates.removeValue(forKey: expiredToken)
        }
    }
    
    deinit {
        // Note: We can't use async operations in deinit
        // The HotReloadManager will clean up its resources in its own deinit
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
}
import Foundation
import Swifter

// Weak wrapper for WebSocket sessions to prevent memory leaks
private class WeakWebSocketSession {
    weak var session: WebSocketSession?
    
    init(_ session: WebSocketSession) {
        self.session = session
    }
}

public class DevelopmentServer {
    private let projectPath: String
    private let port: Int
    private let host: String
    private let liveReload: Bool
    private let server: HttpServer
    private let fileManager = FileManager.default
    private var hotReloadManager: HotReloadManager?
    private var websocketSessions: [WeakWebSocketSession] = []
    private let sessionsQueue = DispatchQueue(label: "websocket.sessions", attributes: .concurrent)
    private var cleanupTimer: Timer?
    
    public init(projectPath: String, port: Int, host: String, liveReload: Bool) {
        self.projectPath = projectPath
        self.port = port
        self.host = host
        self.liveReload = liveReload
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
        
        // Serve static files
        server["/(.*)"] = { request in
            let filePath = request.path == "/" ? "/index.html" : request.path
            let fullPath = outputPath + filePath
            
            // Try exact path first
            if self.fileManager.fileExists(atPath: fullPath) {
                return self.serveFile(at: fullPath)
            }
            
            // Try as directory with index.html
            let indexPath = fullPath + "/index.html"
            if self.fileManager.fileExists(atPath: indexPath) {
                return self.serveFile(at: indexPath)
            }
            
            // 404
            return .notFound
        }
        
        // Live reload endpoint
        if liveReload {
            server["/livereload"] = websocket(text: { session, text in
                // WebSocket for live reload - no action needed for text messages
            }, binary: { session, binary in
                // Not used
            }, pong: { session, _ in
                // Keep alive
            }, connected: { [weak self] session in
                self?.addWebSocketSession(session)
            }, disconnected: { [weak self] session in
                self?.removeWebSocketSession(session)
            })
        }
    }
    
    private func serveFile(at path: String) -> HttpResponse {
        guard let data = fileManager.contents(atPath: path) else {
            return .notFound
        }
        
        let mimeType = mimeType(for: path)
        
        // Inject live reload script for HTML files
        if liveReload && mimeType == "text/html",
           var content = String(data: data, encoding: .utf8) {
            let script = """
                <script>
                (function() {
                    let lastReload = Date.now();
                    let ws = new WebSocket('ws://\(host):\(port)/livereload');
                    ws.onmessage = function(event) {
                        if (event.data === 'reload' && Date.now() - lastReload > 1000) {
                            lastReload = Date.now();
                            location.reload();
                        }
                    };
                    ws.onclose = function() {
                        setTimeout(function() {
                            location.reload();
                        }, 2000);
                    };
                })();
                </script>
                </body>
                """
            content = content.replacingOccurrences(of: "</body>", with: script)
            return .ok(.html(content))
        }
        
        return .raw(200, "OK", ["Content-Type": mimeType]) { writer in
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
        
        do {
            try hotReloadManager?.start()
        } catch {
            print("⚠️ Failed to start file watcher: \(error.localizedDescription)")
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
            // Append to log file
            if let logFile = FileHandle(forWritingAtPath: logPath) {
                logFile.seekToEndOfFile()
                logFile.write(logData)
                logFile.closeFile()
            } else {
                // Create new log file
                FileManager.default.createFile(atPath: logPath, contents: logData, attributes: nil)
            }
        }
    }
    
    deinit {
        hotReloadManager?.stop()
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
}
import Foundation
@preconcurrency import Swifter

public final class DevelopmentServer: @unchecked Sendable {
    private let projectPath: String
    private let port: Int
    private let host: String
    private let liveReload: Bool
    private let server: HttpServer
    private let fileManager: FileManager
    private var hotReloadManager: HotReloadManager?
    private let outputPath: String

    // Concurrency: lifecycle guard to make stop() idempotent and thread-safe
    private actor LifecycleState {
        private(set) var stopped = false
        func markStoppingIfNeeded() -> Bool {
            if stopped { return false }
            stopped = true
            return true
        }
    }
    private let lifecycle = LifecycleState()
    
    public init(
        projectPath: String,
        port: Int,
        host: String,
        liveReload: Bool,
        fileManager: FileManager = .default,
        outputDirectory: String = "_site"
    ) {
        self.fileManager = fileManager
        self.projectPath = projectPath
        self.port = port
        self.host = host
        self.liveReload = liveReload
        self.server = HttpServer()
        self.outputPath = URL(fileURLWithPath: projectPath).appendingPathComponent(outputDirectory).path
        
        setupRoutes()
    }
    
    public func start() async throws {
        try server.start(UInt16(port), forceIPv4: false, priority: .default)
        
        print("Development server started at http://\(host):\(port)")
    }
    
    /// Gracefully stop the server and related resources (idempotent)
    public func stop() async {
        let shouldStop = await lifecycle.markStoppingIfNeeded()
        guard shouldStop else { return }
        server.stop()
        if let hotReloadManager {
            await hotReloadManager.stop()
        }
    }
    
    private func setupRoutes() {
        // Main route handler for static files
        server["/(.*)"] = { [weak self] request in
            return self?.handleStaticFileRequest(request) ?? .notFound
        }
        
        if liveReload {
            // WebSocket endpoint for live reload
            server["/livereload"] = websocket(
                text: { [weak self] session, text in
                    self?.handleWebSocketMessage(session, text: text)
                }
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func handleStaticFileRequest(_ request: HttpRequest) -> HttpResponse {
        let requestPath = request.path == "/" ? "/index.html" : request.path
        let filePath = outputPath + requestPath
        
        guard fileManager.fileExists(atPath: filePath) else {
            return .notFound
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let fileExtension = URL(fileURLWithPath: filePath).pathExtension
            let contentType = mimeType(for: fileExtension)
            
            let headers = [
                "Content-Type": contentType,
                "Cache-Control": "no-cache, no-store, must-revalidate"
            ]
            
            return .raw(200, "OK", headers) { writer in
                try writer.write(data)
            }
        } catch {
            return .internalServerError
        }
    }
    
    private func handleWebSocketMessage(_ session: WebSocketSession, text: String) {
        // Simple ping/pong for keepalive
        if text == "ping" {
            session.writeText("pong")
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
    
    
    
    deinit {
        // Ensure resources are released, idempotently
        server.stop()
        Task { [lifecycle, hotReloadManager] in
            _ = await lifecycle.markStoppingIfNeeded()
            await hotReloadManager?.stop()
        }
    }
}

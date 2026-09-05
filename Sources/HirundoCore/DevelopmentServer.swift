import Foundation
@preconcurrency import Swifter

public final class DevelopmentServer: @unchecked Sendable {
    private let projectPath: String
    private let port: Int
    private let host: String
    private let liveReload: Bool
    private let server: HttpServer
    private let fileManager: FileManager
    private let outputPath: String
    private let injector = LiveReloadScriptInjector()

    /// The hub the `/livereload` endpoint registers its clients with.
    public let liveReloadHub: LiveReloadHub

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
        outputDirectory: String = "_site",
        hub: LiveReloadHub? = nil
    ) {
        self.fileManager = fileManager
        self.projectPath = projectPath
        self.port = port
        self.host = host
        self.liveReload = liveReload
        self.server = HttpServer()
        self.outputPath = URL(fileURLWithPath: projectPath).appendingPathComponent(outputDirectory).path
        self.liveReloadHub = hub ?? LiveReloadHub()

        setupRoutes()
    }

    public func start() async throws {
        let listen = try resolveListenAddress(host: host)
        if listen.forceIPv4 {
            server.listenAddressIPv4 = listen.address
        } else {
            server.listenAddressIPv6 = listen.address
        }
        try server.start(UInt16(port), forceIPv4: listen.forceIPv4, priority: .default)
        print("Development server started at http://\(listen.displayHost):\(port)")
    }

    /// Gracefully stop the server and related resources (idempotent)
    public func stop() async {
        let shouldStop = await lifecycle.markStoppingIfNeeded()
        guard shouldStop else { return }
        server.stop()
    }

    private func setupRoutes() {
        if liveReload {
            // WebSocket endpoint for live reload. `connected`/`disconnected` register and
            // unregister the client with the hub so `broadcast` can reach every open tab.
            server["/livereload"] = websocket(
                text: { session, text in
                    if text == "ping" { session.writeText("pong") }
                },
                connected: { [hub = liveReloadHub] session in
                    let client = WebSocketLiveReloadClient(session)
                    Task { await hub.add(client) }
                },
                disconnected: { [hub = liveReloadHub] session in
                    let id = ObjectIdentifier(session)
                    Task { await hub.remove(id: id) }
                }
            )
        }

        // Static files are served from the not-found handler, which runs after the
        // routes above have had their chance. Swifter's router matches literal path
        // segments and `:name` variables — it does not interpret regular expressions,
        // so a `/(.*)` route would only ever match the literal path `/(.*)`.
        server.notFoundHandler = { [weak self] request in
            self?.handleStaticFileRequest(request) ?? .notFound
        }
    }
    
    // MARK: - Private Methods
    
    /// Maps a request path to the file to serve from the output directory.
    ///
    /// Directory requests (`/about`, `/about/`, `/`) resolve to the directory's
    /// `index.html`, which is the layout `SiteGenerator` produces for every page.
    /// - Parameter requestPath: Path component of the incoming request.
    /// - Returns: Absolute path of the file to serve, or `nil` when nothing matches
    ///   or the path escapes the output directory.
    func resolveFilePath(forRequestPath requestPath: String) -> String? {
        let root = URL(fileURLWithPath: outputPath, isDirectory: true).standardizedFileURL
        // `HttpRequest.path` is already percent-decoded and query-stripped by Swifter's parser.
        var candidate = root
        for component in requestPath.split(separator: "/") {
            candidate.appendPathComponent(String(component))
        }
        candidate.standardize()

        // Reject anything that climbs out of the output directory, e.g. `/../../etc/passwd`.
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
            return nil
        }
        guard isDirectory.boolValue else {
            return candidate.path
        }

        let index = candidate.appendingPathComponent("index.html")
        guard fileManager.fileExists(atPath: index.path) else {
            return nil
        }
        return index.path
    }

    private func handleStaticFileRequest(_ request: HttpRequest) -> HttpResponse {
        guard let filePath = resolveFilePath(forRequestPath: request.path) else {
            return .notFound
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let fileExtension = URL(fileURLWithPath: filePath).pathExtension
            let contentType = mimeType(for: fileExtension)

            // Inject the live-reload client script into HTML responses only. Injection failure
            // (e.g. the file isn't valid UTF-8, which shouldn't happen for an .html file but
            // isn't guaranteed) must never turn into a serving failure, so fall back to the
            // original bytes unchanged.
            var body = data
            if liveReload, contentType.hasPrefix("text/html"), let html = String(data: data, encoding: .utf8),
               let injected = injector.inject(into: html).data(using: .utf8) {
                body = injected
            }

            let headers = [
                "Content-Type": contentType,
                "Cache-Control": "no-cache, no-store, must-revalidate"
            ]

            return .raw(200, "OK", headers) { writer in
                try writer.write(body)
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

    deinit {
        // Ensure resources are released, idempotently
        server.stop()
    }
}

/// Adapts Swifter's session to the hub's client protocol.
///
/// `id` is the *session's* identity, not the wrapper's: `connected` and `disconnected`
/// hand back the same session but this wrapper is built twice, so keying on the wrapper
/// would leave every disconnected client registered forever.
final class WebSocketLiveReloadClient: LiveReloadClient, @unchecked Sendable {
    private let session: WebSocketSession
    init(_ session: WebSocketSession) { self.session = session }
    var id: ObjectIdentifier { ObjectIdentifier(session) }
    func send(_ text: String) { session.writeText(text) }
}

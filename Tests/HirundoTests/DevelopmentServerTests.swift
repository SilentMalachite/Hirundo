import XCTest
import Swifter
import Yams
@testable import HirundoCore

final class DevelopmentServerTests: XCTestCase {
    var tempDir: URL!
    let fileManager = FileManager.default
    
    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try! fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create _site directory
        let siteDir = tempDir.appendingPathComponent("_site")
        try! fileManager.createDirectory(at: siteDir, withIntermediateDirectories: true)
        
        // Create test HTML file
        let testHTML = """
        <!DOCTYPE html>
        <html>
        <head><title>Test</title></head>
        <body>Test Content</body>
        </html>
        """
        try! testHTML.write(to: siteDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
    
    override func tearDown() {
        try? fileManager.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Server Configuration Tests
    
    func testDefaultServerConfiguration() {
        let server = Server()
        
        XCTAssertEqual(server.port, 8080)
        XCTAssertTrue(server.liveReload)
    }
    
    func testCustomServerConfiguration() {
        let server = Server(port: 3000, liveReload: false)
        
        XCTAssertEqual(server.port, 3000)
        XCTAssertFalse(server.liveReload)
    }
    
    // MARK: - Development Server Tests
    
    func testDevelopmentServerCreation() {
        let server = DevelopmentServer(
            projectPath: "/tmp/test",
            port: 8080,
            host: "localhost",
            liveReload: false
        )
        
        XCTAssertNotNil(server)
    }
    
    func testDevelopmentServerWithCustomPort() {
        let server = DevelopmentServer(
            projectPath: "/tmp/test",
            port: 3000,
            host: "localhost",
            liveReload: true
        )
        
        XCTAssertNotNil(server)
    }
    
    func testDevelopmentServerWithLiveReload() {
        let server = DevelopmentServer(
            projectPath: "/tmp/test",
            port: 8080,
            host: "localhost",
            liveReload: true
        )
        
        XCTAssertNotNil(server)
    }
    
    func testDevelopmentServerWithoutLiveReload() {
        let server = DevelopmentServer(
            projectPath: "/tmp/test",
            port: 8080,
            host: "localhost",
            liveReload: false
        )

        XCTAssertNotNil(server)
    }

    // MARK: - Request Path Resolution Tests

    private func makeServer() -> DevelopmentServer {
        DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: false
        )
    }

    func testResolveFilePath_whenRootRequested_servesIndexHTML() {
        let expected = tempDir.appendingPathComponent("_site/index.html").path
        XCTAssertEqual(makeServer().resolveFilePath(forRequestPath: "/"), expected)
    }

    func testResolveFilePath_whenDirectoryRequested_servesNestedIndexHTML() throws {
        let about = tempDir.appendingPathComponent("_site/about")
        try fileManager.createDirectory(at: about, withIntermediateDirectories: true)
        try "<p>About</p>".write(
            to: about.appendingPathComponent("index.html"),
            atomically: true,
            encoding: .utf8
        )

        let server = makeServer()
        let expected = about.appendingPathComponent("index.html").path
        XCTAssertEqual(server.resolveFilePath(forRequestPath: "/about"), expected)
        XCTAssertEqual(server.resolveFilePath(forRequestPath: "/about/"), expected)
    }

    func testResolveFilePath_whenDirectoryHasNoIndex_returnsNil() throws {
        let assets = tempDir.appendingPathComponent("_site/assets")
        try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)

        XCTAssertNil(makeServer().resolveFilePath(forRequestPath: "/assets"))
    }

    func testResolveFilePath_whenFileRequested_servesThatFile() throws {
        let css = tempDir.appendingPathComponent("_site/css")
        try fileManager.createDirectory(at: css, withIntermediateDirectories: true)
        let file = css.appendingPathComponent("style.css")
        try "body {}".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(makeServer().resolveFilePath(forRequestPath: "/css/style.css"), file.path)
    }

    func testResolveFilePath_whenPathMissing_returnsNil() {
        XCTAssertNil(makeServer().resolveFilePath(forRequestPath: "/nope.html"))
    }

    func testResolveFilePath_whenPathEscapesOutputDirectory_returnsNil() throws {
        let secret = tempDir.appendingPathComponent("secret.txt")
        try "top secret".write(to: secret, atomically: true, encoding: .utf8)

        XCTAssertNil(makeServer().resolveFilePath(forRequestPath: "/../secret.txt"))
        XCTAssertNil(makeServer().resolveFilePath(forRequestPath: "/a/../../secret.txt"))
    }

    func testServer_whenDirectoryRequested_respondsWithNestedIndexHTML() async throws {
        let about = tempDir.appendingPathComponent("_site/about")
        try fileManager.createDirectory(at: about, withIntermediateDirectories: true)
        try "<p>About page</p>".write(
            to: about.appendingPathComponent("index.html"),
            atomically: true,
            encoding: .utf8
        )

        let port = Int.random(in: 20000...30000)
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: port,
            host: "localhost",
            liveReload: false
        )
        try await server.start()
        defer { Task { await server.stop() } }

        for path in ["/about", "/about/"] {
            let url = URL(string: "http://127.0.0.1:\(port)\(path)")!
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode
            XCTAssertEqual(status, 200, "GET \(path)")
            XCTAssertEqual(String(data: data, encoding: .utf8), "<p>About page</p>", "GET \(path)")
        }

        let root = URL(string: "http://127.0.0.1:\(port)/")!
        let (rootData, rootResponse) = try await URLSession.shared.data(from: root)
        XCTAssertEqual((rootResponse as? HTTPURLResponse)?.statusCode, 200, "GET /")
        XCTAssertTrue(String(data: rootData, encoding: .utf8)?.contains("Test Content") == true)

        let missing = URL(string: "http://127.0.0.1:\(port)/nope.html")!
        let (_, missingResponse) = try await URLSession.shared.data(from: missing)
        XCTAssertEqual((missingResponse as? HTTPURLResponse)?.statusCode, 404, "GET /nope.html")
    }

    // MARK: - Live Reload Injection Tests

    func testStaticFileRequest_whenLiveReloadEnabled_injectsScriptBeforeBodyClose() async throws {
        let html = "<!DOCTYPE html><html><body><p>Hello</p></body></html>"
        try html.write(
            to: tempDir.appendingPathComponent("_site/inject.html"),
            atomically: true,
            encoding: .utf8
        )

        let port = Int.random(in: 20000...30000)
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: port,
            host: "localhost",
            liveReload: true
        )
        try await server.start()

        let url = URL(string: "http://127.0.0.1:\(port)/inject.html")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let body = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(body.contains("/livereload"))
        XCTAssertTrue(body.contains("location.reload()"))
        let scriptRange = try XCTUnwrap(body.range(of: "/livereload"))
        let bodyCloseRange = try XCTUnwrap(body.range(of: "</body>"))
        XCTAssertLessThan(scriptRange.lowerBound, bodyCloseRange.lowerBound)

        await server.stop()
    }

    func testStaticFileRequest_whenLiveReloadDisabled_doesNotInjectScript() async throws {
        let html = "<!DOCTYPE html><html><body><p>Hello</p></body></html>"
        try html.write(
            to: tempDir.appendingPathComponent("_site/noinject.html"),
            atomically: true,
            encoding: .utf8
        )

        let port = Int.random(in: 20000...30000)
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: port,
            host: "localhost",
            liveReload: false
        )
        try await server.start()

        let url = URL(string: "http://127.0.0.1:\(port)/noinject.html")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), html)

        await server.stop()
    }

    func testStaticFileRequest_whenLiveReloadEnabledAndCSSRequested_doesNotInjectScript() async throws {
        let css = "body {}"
        try css.write(
            to: tempDir.appendingPathComponent("_site/style.css"),
            atomically: true,
            encoding: .utf8
        )

        let port = Int.random(in: 20000...30000)
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: port,
            host: "localhost",
            liveReload: true
        )
        try await server.start()

        let url = URL(string: "http://127.0.0.1:\(port)/style.css")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), css)

        await server.stop()
    }

    func testStaticFileRequest_whenLiveReloadEnabledAndBinaryFileRequested_servesBytesUnchanged() async throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0xFF, 0xFE])
        try bytes.write(to: tempDir.appendingPathComponent("_site/image.png"))

        let port = Int.random(in: 20000...30000)
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: port,
            host: "localhost",
            liveReload: true
        )
        try await server.start()

        let url = URL(string: "http://127.0.0.1:\(port)/image.png")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(data, bytes)

        await server.stop()
    }

    // MARK: - Bind Address Tests

    func testStart_whenHostIsIPv4Literal_servesOverThatAddress() async throws {
        let port = Int.random(in: 20000...30000)
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: port,
            host: "127.0.0.1",
            liveReload: false
        )
        try await server.start()

        let url = URL(string: "http://127.0.0.1:\(port)/")!
        let (_, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        await server.stop()
    }

    func testStart_whenHostIsIPv6Loopback_servesOverThatAddress() async throws {
        let port = Int.random(in: 20000...30000)
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: port,
            host: "::1",
            liveReload: false
        )

        do {
            try await server.start()
        } catch {
            throw XCTSkip("IPv6 loopback is not available on this machine: \(error)")
        }

        let url = URL(string: "http://[::1]:\(port)/")!
        let (_, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        await server.stop()
    }

    func testStart_whenHostIsNotNumeric_throwsListenAddressError() async throws {
        let port = Int.random(in: 20000...30000)
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: port,
            host: "example.com",
            liveReload: false
        )

        do {
            try await server.start()
            XCTFail("Expected start() to throw for a non-numeric host")
        } catch let error as ListenAddressError {
            XCTAssertEqual(error, .notNumeric("example.com"))
        }
    }

    // MARK: - Hub Wiring Tests

    func testInit_whenHubProvided_usesProvidedHubInstance() {
        let hub = LiveReloadHub()
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: true,
            hub: hub
        )

        XCTAssertTrue(server.liveReloadHub === hub)
    }
}
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
}
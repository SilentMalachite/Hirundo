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
}
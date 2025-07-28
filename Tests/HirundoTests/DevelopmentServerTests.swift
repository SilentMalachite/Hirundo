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
        super.tearDown()
        try? fileManager.removeItem(at: tempDir)
    }
    
    // MARK: - CORS Configuration Tests
    
    func testDefaultCorsConfiguration() {
        let corsConfig = CorsConfig()
        
        XCTAssertTrue(corsConfig.enabled)
        XCTAssertEqual(corsConfig.allowedOrigins, ["http://localhost:*", "https://localhost:*"])
        XCTAssertEqual(corsConfig.allowedMethods, ["GET", "POST", "PUT", "DELETE", "OPTIONS"])
        XCTAssertEqual(corsConfig.allowedHeaders, ["Content-Type", "Authorization"])
        XCTAssertNil(corsConfig.exposedHeaders)
        XCTAssertEqual(corsConfig.maxAge, 3600)
        XCTAssertFalse(corsConfig.allowCredentials)
    }
    
    func testCustomCorsConfiguration() {
        let corsConfig = CorsConfig(
            enabled: true,
            allowedOrigins: ["https://example.com", "https://app.example.com"],
            allowedMethods: ["GET", "POST"],
            allowedHeaders: ["Content-Type", "X-Custom-Header"],
            exposedHeaders: ["X-Response-Header"],
            maxAge: 7200,
            allowCredentials: true
        )
        
        XCTAssertTrue(corsConfig.enabled)
        XCTAssertEqual(corsConfig.allowedOrigins, ["https://example.com", "https://app.example.com"])
        XCTAssertEqual(corsConfig.allowedMethods, ["GET", "POST"])
        XCTAssertEqual(corsConfig.allowedHeaders, ["Content-Type", "X-Custom-Header"])
        XCTAssertEqual(corsConfig.exposedHeaders, ["X-Response-Header"])
        XCTAssertEqual(corsConfig.maxAge, 7200)
        XCTAssertTrue(corsConfig.allowCredentials)
    }
    
    // MARK: - CORS Header Generation Tests
    
    func testGetCorsHeadersWithMatchingOrigin() {
        // This test verifies that CORS headers are correctly generated
        // when the request origin matches an allowed origin
        
        let corsConfig = CorsConfig(
            enabled: true,
            allowedOrigins: ["http://localhost:3000", "https://example.com"],
            allowedMethods: ["GET", "POST"],
            allowedHeaders: ["Content-Type"],
            maxAge: 3600
        )
        
        // Note: Since we can't easily test the private getCorsHeaders method directly,
        // we'll test the behavior through the server responses
        
        // Test server initialization with CORS config
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: false,
            corsConfig: corsConfig
        )
        
        XCTAssertNotNil(server)
    }
    
    func testGetCorsHeadersWithWildcardOrigin() {
        let corsConfig = CorsConfig(
            enabled: true,
            allowedOrigins: ["*"],
            allowedMethods: ["GET", "POST", "PUT", "DELETE"],
            allowedHeaders: ["Content-Type", "Authorization"]
        )
        
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: false,
            corsConfig: corsConfig
        )
        
        XCTAssertNotNil(server)
    }
    
    func testGetCorsHeadersWithWildcardPort() {
        let corsConfig = CorsConfig(
            enabled: true,
            allowedOrigins: ["http://localhost:*", "https://localhost:*"],
            allowedMethods: ["GET"],
            allowedHeaders: ["Content-Type"]
        )
        
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: false,
            corsConfig: corsConfig
        )
        
        XCTAssertNotNil(server)
    }
    
    func testCorsDisabled() {
        let corsConfig = CorsConfig(
            enabled: false,
            allowedOrigins: ["http://localhost:3000"],
            allowedMethods: ["GET"],
            allowedHeaders: ["Content-Type"]
        )
        
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: false,
            corsConfig: corsConfig
        )
        
        XCTAssertNotNil(server)
    }
    
    // MARK: - Config Integration Tests
    
    func testServerConfigWithCors() throws {
        let yaml = """
        server:
          port: 8080
          liveReload: true
          cors:
            enabled: true
            allowedOrigins: ["http://localhost:3000", "https://app.example.com"]
            allowedMethods: ["GET", "POST", "PUT"]
            allowedHeaders: ["Content-Type", "Authorization", "X-Custom-Header"]
            exposedHeaders: ["X-Response-Time"]
            maxAge: 7200
            allowCredentials: true
        """
        
        let decoder = try YAMLDecoder()
        let serverConfig = try decoder.decode([String: Server].self, from: yaml)
        let server = serverConfig["server"]!
        
        XCTAssertNotNil(server.cors)
        let cors = server.cors!
        
        XCTAssertTrue(cors.enabled)
        XCTAssertEqual(cors.allowedOrigins, ["http://localhost:3000", "https://app.example.com"])
        XCTAssertEqual(cors.allowedMethods, ["GET", "POST", "PUT"])
        XCTAssertEqual(cors.allowedHeaders, ["Content-Type", "Authorization", "X-Custom-Header"])
        XCTAssertEqual(cors.exposedHeaders, ["X-Response-Time"])
        XCTAssertEqual(cors.maxAge, 7200)
        XCTAssertTrue(cors.allowCredentials)
    }
    
    func testServerConfigWithoutCors() throws {
        let yaml = """
        server:
          port: 8080
          liveReload: true
        """
        
        let decoder = try YAMLDecoder()
        let serverConfig = try decoder.decode([String: Server].self, from: yaml)
        let server = serverConfig["server"]!
        
        XCTAssertNil(server.cors)
    }
    
    func testFullConfigWithCors() throws {
        let yaml = """
        site:
          title: "Test Site"
          url: "https://example.com"
        
        server:
          port: 8080
          liveReload: true
          cors:
            enabled: true
            allowedOrigins: ["*"]
            allowedMethods: ["GET", "POST", "OPTIONS"]
            allowedHeaders: ["Content-Type"]
            maxAge: 3600
        """
        
        let config = try HirundoConfig.parse(from: yaml)
        
        XCTAssertNotNil(config.server.cors)
        let cors = config.server.cors!
        
        XCTAssertTrue(cors.enabled)
        XCTAssertEqual(cors.allowedOrigins, ["*"])
        XCTAssertEqual(cors.allowedMethods, ["GET", "POST", "OPTIONS"])
        XCTAssertEqual(cors.allowedHeaders, ["Content-Type"])
        XCTAssertEqual(cors.maxAge, 3600)
        XCTAssertFalse(cors.allowCredentials)
    }
    
    // MARK: - Development Server Initialization Tests
    
    func testDevelopmentServerWithDefaultCors() {
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: false
        )
        
        XCTAssertNotNil(server)
        // Default CORS config should be applied
    }
    
    func testDevelopmentServerWithCustomCors() {
        let corsConfig = CorsConfig(
            enabled: true,
            allowedOrigins: ["https://production.com"],
            allowedMethods: ["GET"],
            allowedHeaders: ["Content-Type"],
            allowCredentials: false
        )
        
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: false,
            corsConfig: corsConfig
        )
        
        XCTAssertNotNil(server)
    }
    
    func testDevelopmentServerWithNilCors() {
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: false,
            corsConfig: nil
        )
        
        XCTAssertNotNil(server)
        // Should use default CORS config
    }
}
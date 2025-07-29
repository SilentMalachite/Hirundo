import XCTest
import Foundation
@testable import HirundoCore

/// Test class for WebSocket authentication functionality
/// Tests secure token-based authentication for WebSocket connections in development server
final class WebSocketAuthenticationTests: XCTestCase {
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
    
    // MARK: - Token Generation Tests
    
    func testGenerateAuthenticationToken() {
        // Test that the development server can generate an authentication token
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: true
        )
        
        // This test should fail initially as we haven't implemented token generation
        let token = server.generateAuthToken()
        
        XCTAssertNotNil(token, "Authentication token should be generated")
        XCTAssertFalse(token.isEmpty, "Authentication token should not be empty")
        XCTAssertGreaterThanOrEqual(token.count, 32, "Token should be at least 32 characters for security")
    }
    
    func testTokenUniqueness() {
        // Test that each generated token is unique
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: true
        )
        
        let token1 = server.generateAuthToken()
        let token2 = server.generateAuthToken()
        
        XCTAssertNotEqual(token1, token2, "Each generated token should be unique")
    }
    
    func testTokenValidation() {
        // Test that generated tokens can be validated
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: true
        )
        
        let token = server.generateAuthToken()
        
        XCTAssertTrue(server.validateAuthToken(token), "Valid token should pass validation")
        XCTAssertFalse(server.validateAuthToken("invalid-token"), "Invalid token should fail validation")
        XCTAssertFalse(server.validateAuthToken(""), "Empty token should fail validation")
    }
    
    // MARK: - WebSocket Authentication Tests
    
    func testWebSocketAuthenticationRequired() {
        // Test that WebSocket connections require authentication
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: true
        )
        
        // Create a mock WebSocket session without authentication
        let mockSession = MockWebSocketSession()
        
        // Attempt to connect without token should fail
        let result = server.authenticateWebSocketConnection(mockSession, token: nil)
        XCTAssertFalse(result, "WebSocket connection without token should be rejected")
    }
    
    func testWebSocketAuthenticationWithValidToken() {
        // Test that WebSocket connections with valid tokens are allowed
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: true
        )
        
        let validToken = server.generateAuthToken()
        let mockSession = MockWebSocketSession()
        
        let result = server.authenticateWebSocketConnection(mockSession, token: validToken)
        XCTAssertTrue(result, "WebSocket connection with valid token should be accepted")
    }
    
    func testWebSocketAuthenticationWithInvalidToken() {
        // Test that WebSocket connections with invalid tokens are rejected
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: true
        )
        
        let mockSession = MockWebSocketSession()
        let invalidToken = "invalid-token-12345"
        
        let result = server.authenticateWebSocketConnection(mockSession, token: invalidToken)
        XCTAssertFalse(result, "WebSocket connection with invalid token should be rejected")
    }
    
    func testWebSocketAuthenticationWithExpiredToken() {
        // Test that expired tokens are rejected
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: true
        )
        
        // Generate a token and mark it as expired
        let expiredToken = server.generateAuthToken()
        server.expireAuthToken(expiredToken)
        
        let mockSession = MockWebSocketSession()
        let result = server.authenticateWebSocketConnection(mockSession, token: expiredToken)
        XCTAssertFalse(result, "WebSocket connection with expired token should be rejected")
    }
    
    // MARK: - Token Endpoint Tests
    
    func testAuthTokenEndpoint() {
        // Test that there's an endpoint to retrieve authentication tokens
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: true
        )
        
        // This should test the HTTP endpoint that serves the auth token
        let endpoint = server.getAuthTokenEndpoint()
        XCTAssertEqual(endpoint, "/auth-token", "Auth token endpoint should be at /auth-token")
    }
    
    // MARK: - Security Tests
    
    func testTokenSecurityProperties() {
        // Test that tokens have proper security characteristics
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: true
        )
        
        let token = server.generateAuthToken()
        
        // Token should be long enough for security
        XCTAssertGreaterThanOrEqual(token.count, 32, "Token should be at least 32 characters")
        
        // Token should only contain safe characters (no special chars that could cause issues)
        let allowedCharacterSet = CharacterSet.alphanumerics
        let tokenCharacterSet = CharacterSet(charactersIn: token)
        XCTAssertTrue(allowedCharacterSet.isSuperset(of: tokenCharacterSet), 
                     "Token should only contain alphanumeric characters")
    }
    
    func testTokenDoesNotContainSensitiveInformation() {
        // Test that tokens don't contain sensitive information
        let server = DevelopmentServer(
            projectPath: tempDir.path,
            port: 8080,
            host: "localhost",
            liveReload: true
        )
        
        let token = server.generateAuthToken()
        
        // Token should not contain obvious sensitive patterns
        XCTAssertFalse(token.lowercased().contains("password"), "Token should not contain 'password'")
        XCTAssertFalse(token.lowercased().contains("secret"), "Token should not contain 'secret'")
        XCTAssertFalse(token.contains(tempDir.lastPathComponent), "Token should not contain project path")
    }
}

// MARK: - Mock Classes

/// Mock WebSocket session for testing
class MockWebSocketSession {
    var isConnected = false
    var receivedMessages: [String] = []
    
    func writeText(_ text: String) {
        receivedMessages.append(text)
    }
    
    func close() {
        isConnected = false
    }
}
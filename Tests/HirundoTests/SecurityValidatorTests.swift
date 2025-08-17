import XCTest
@testable import HirundoCore

final class SecurityValidatorTests: XCTestCase {
    
    var tempDir: URL!
    var validator: SecurityValidator!
    var config: HirundoConfig!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create a minimal config for testing
        let site = try Site(title: "Test", url: "https://example.com")
        config = HirundoConfig(site: site)
        validator = SecurityValidator(projectPath: tempDir.path, config: config)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Path Validation Tests
    
    func testValidatePathSuccess() throws {
        let validPath = tempDir.appendingPathComponent("test.md").path
        XCTAssertNoThrow(try validator.validatePath(validPath, withinBaseDirectory: tempDir.path))
    }
    
    func testValidatePathRejectsPathTraversal() throws {
        let traversalPath = tempDir.appendingPathComponent("../../../etc/passwd").path
        XCTAssertThrowsError(try validator.validatePath(traversalPath, withinBaseDirectory: tempDir.path)) { error in
            XCTAssertTrue(error is SecurityError)
            if case SecurityError.pathTraversal = error {
                // Expected
            } else {
                XCTFail("Expected path traversal error")
            }
        }
    }
    
    func testValidatePathRejectsNullBytes() throws {
        let nullPath = tempDir.appendingPathComponent("test\0.md").path
        XCTAssertThrowsError(try validator.validatePath(nullPath, withinBaseDirectory: tempDir.path)) { error in
            XCTAssertTrue(error is SecurityError)
        }
    }
    
    func testValidatePathRejectsAbsolutePathsOutsideProject() throws {
        let outsidePath = "/etc/passwd"
        XCTAssertThrowsError(try validator.validatePath(outsidePath, withinBaseDirectory: tempDir.path)) { error in
            XCTAssertTrue(error is SecurityError)
        }
    }
    
    // MARK: - Path Safety Tests
    
    func testIsPathSafeSuccess() {
        let safePath = tempDir.appendingPathComponent("test.md").path
        XCTAssertTrue(validator.isPathSafe(safePath, withinBaseDirectory: tempDir.path))
    }
    
    func testIsPathSafeRejectsPathTraversal() {
        let unsafePath = tempDir.appendingPathComponent("../../../etc/passwd").path
        XCTAssertFalse(validator.isPathSafe(unsafePath, withinBaseDirectory: tempDir.path))
    }
    
    func testIsPathSafeRejectsOutsidePaths() {
        let outsidePath = "/etc/passwd"
        XCTAssertFalse(validator.isPathSafe(outsidePath, withinBaseDirectory: tempDir.path))
    }
    
    // MARK: - File Size Validation Tests
    
    func testValidateFileSizeSuccess() async throws {
        let testFile = tempDir.appendingPathComponent("test.md")
        try "# Test Content".write(to: testFile, atomically: true, encoding: .utf8)
        
        XCTAssertNoThrow(try validator.validateFileSize(at: testFile.path))
    }
    
    func testValidateFileSizeTooLarge() async throws {
        let testFile = tempDir.appendingPathComponent("large.md")
        // Create a file larger than the max markdown file size
        let largeContent = String(repeating: "a", count: 11_000_000) // 11MB
        try largeContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        XCTAssertThrowsError(try validator.validateFileSize(at: testFile.path)) { error in
            XCTAssertTrue(error is SecurityError)
            if case SecurityError.fileTooLarge = error {
                // Expected
            } else {
                XCTFail("Expected file too large error")
            }
        }
    }
    
    func testValidateFileSizeNonexistent() async throws {
        let nonexistentFile = tempDir.appendingPathComponent("nonexistent.md")
        
        XCTAssertThrowsError(try validator.validateFileSize(at: nonexistentFile.path)) { error in
            XCTAssertTrue(error is SecurityError)
        }
    }
    
    // MARK: - Metadata Validation Tests
    
    func testValidateMetadataSuccess() throws {
        let metadata: [String: Any] = [
            "title": "Test Post",
            "author": "Test Author",
            "date": "2024-01-01",
            "tags": ["swift", "testing"]
        ]
        
        XCTAssertNoThrow(try validator.validateMetadata(metadata))
    }
    
    func testValidateMetadataRejectsTooLongTitle() throws {
        let metadata: [String: Any] = [
            "title": String(repeating: "a", count: 201), // Exceeds max title length
            "author": "Test Author"
        ]
        
        XCTAssertThrowsError(try validator.validateMetadata(metadata)) { error in
            XCTAssertTrue(error is SecurityError)
            if case SecurityError.metadataTooLong = error {
                // Expected
            } else {
                XCTFail("Expected invalid metadata error")
            }
        }
    }
    
    func testValidateMetadataRejectsTooLongDescription() throws {
        let metadata: [String: Any] = [
            "title": "Test",
            "description": String(repeating: "a", count: 501) // Exceeds max description length
        ]
        
        XCTAssertThrowsError(try validator.validateMetadata(metadata)) { error in
            XCTAssertTrue(error is SecurityError)
            if case SecurityError.metadataTooLong = error {
                // Expected
            } else {
                XCTFail("Expected invalid metadata error")
            }
        }
    }
    
    // MARK: - Template Sanitization Tests
    
    func testSanitizeForTemplateBasicHTML() {
        let input = "<script>alert('xss')</script>"
        let sanitized = validator.sanitizeForTemplate(input)
        XCTAssertEqual(sanitized, "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;")
    }
    
    func testSanitizeForTemplateQuotes() {
        let input = "She said \"Hello\" and 'Goodbye'"
        let sanitized = validator.sanitizeForTemplate(input)
        XCTAssertEqual(sanitized, "She said &quot;Hello&quot; and &#39;Goodbye&#39;")
    }
    
    func testSanitizeForTemplateAmpersand() {
        let input = "AT&T & Johnson & Johnson"
        let sanitized = validator.sanitizeForTemplate(input)
        XCTAssertEqual(sanitized, "AT&amp;T &amp; Johnson &amp; Johnson")
    }
    
    func testSanitizeForTemplateUnicode() {
        let input = "日本語のテキスト 🚀"
        let sanitized = validator.sanitizeForTemplate(input)
        XCTAssertEqual(sanitized, "日本語のテキスト 🚀")
    }
    
    func testSanitizeForTemplateEmpty() {
        XCTAssertEqual(validator.sanitizeForTemplate(""), "")
    }
    
    // MARK: - Path Sanitization Tests
    
    func testSanitizePath() {
        // Test basic path sanitization
        let input = "test/../file.md"
        let sanitized = validator.sanitizePath(input)
        XCTAssertFalse(sanitized.contains(".."))
    }
    
    func testSanitizePathRemovesNullBytes() {
        let input = "test\0file.md"
        let sanitized = validator.sanitizePath(input)
        XCTAssertFalse(sanitized.contains("\0"))
    }
    
    func testSanitizePathNormalizesSlashes() {
        let input = "test//file.md"
        let sanitized = validator.sanitizePath(input)
        XCTAssertFalse(sanitized.contains("//"))
    }
    
    // MARK: - Cache Management Tests
    
    func testClearCache() {
        // Just test that clearCache doesn't crash
        validator.clearCache()
        XCTAssertTrue(true) // If we get here, it worked
    }
    
    // MARK: - Integration Tests
    
    func testSecurityValidatorWithRealFile() async throws {
        let content = """
        ---
        title: "Test Post"
        author: "Test Author"
        ---
        
        # Test Content
        
        This is a test post with <script>alert('xss')</script> attempt.
        """
        
        let file = tempDir.appendingPathComponent("test.md")
        try content.write(to: file, atomically: true, encoding: .utf8)
        
        // Validate the file path
        XCTAssertNoThrow(try validator.validatePath(file.path, withinBaseDirectory: tempDir.path))
        
        // Validate the file size
        XCTAssertNoThrow(try validator.validateFileSize(at: file.path))
        
        // Sanitize for template
        let sanitized = validator.sanitizeForTemplate(content)
        XCTAssertFalse(sanitized.contains("<script>"))
        XCTAssertTrue(sanitized.contains("&lt;script&gt;"))
    }
    
    func testValidatePathWithSymlinks() throws {
        let originalFile = tempDir.appendingPathComponent("original.md")
        let symlinkFile = tempDir.appendingPathComponent("symlink.md")
        
        try "test".write(to: originalFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: symlinkFile, withDestinationURL: originalFile)
        
        // Symlinks within project should be allowed
        XCTAssertNoThrow(try validator.validatePath(symlinkFile.path, withinBaseDirectory: tempDir.path))
    }
    
    func testValidatePathWithHiddenFiles() throws {
        let hiddenFile = tempDir.appendingPathComponent(".hidden.md")
        try "test".write(to: hiddenFile, atomically: true, encoding: .utf8)
        
        // Hidden files should be allowed
        XCTAssertNoThrow(try validator.validatePath(hiddenFile.path, withinBaseDirectory: tempDir.path))
    }
}

// Helper for async assertions
extension XCTestCase {
    func XCTAssertThrowsAsyncError<T>(_ expression: @autoclosure () async throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line, _ errorHandler: (_ error: Error) -> Void = { _ in }) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
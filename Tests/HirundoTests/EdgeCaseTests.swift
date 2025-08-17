import XCTest
@testable import HirundoCore

final class EdgeCaseTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("hirundo-edge-test-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
    
    func testEmptyMarkdownFile() async throws {
        let emptyFile = tempDir.appendingPathComponent("empty.md")
        try "".write(to: emptyFile, atomically: true, encoding: .utf8)
        
        let config = HirundoConfig.createDefault()
        let securityValidator = SecurityValidator(projectPath: tempDir.path, config: config)
        let contentProcessor = ContentProcessor(config: config, securityValidator: securityValidator)
        
        do {
            let content = try await contentProcessor.processMarkdownFile(at: emptyFile, projectPath: tempDir.path, includeDrafts: false)
            XCTAssertNotNil(content)
            if let content = content {
                XCTAssertEqual(content.markdown.renderHTML(), "")
                XCTAssertTrue(content.markdown.frontMatter?.isEmpty ?? true)
            }
        } catch {
            XCTFail("Empty file should be processed successfully: \(error)")
        }
    }
    
    func testMarkdownWithOnlyFrontMatter() async throws {
        let frontMatterOnly = """
        ---
        title: "Test"
        date: "2023-01-01"
        ---
        """
        
        let file = tempDir.appendingPathComponent("frontmatter-only.md")
        try frontMatterOnly.write(to: file, atomically: true, encoding: .utf8)
        
        let config = HirundoConfig.createDefault()
        let securityValidator = SecurityValidator(projectPath: tempDir.path, config: config)
        let contentProcessor = ContentProcessor(config: config, securityValidator: securityValidator)
        
        do {
            let content = try await contentProcessor.processMarkdownFile(at: file, projectPath: tempDir.path, includeDrafts: false)
            XCTAssertNotNil(content)
            if let content = content {
                XCTAssertEqual(content.markdown.renderHTML(), "")
                XCTAssertEqual(content.markdown.frontMatter?["title"] as? String, "Test")
                XCTAssertEqual(content.markdown.frontMatter?["date"] as? String, "2023-01-01")
            }
        } catch {
            XCTFail("Front matter only file should be processed: \(error)")
        }
    }
    
    func testMarkdownWithMalformedFrontMatter() async throws {
        let malformedFrontMatter = """
        ---
        title: "Test
        date: 2023-01-01
        invalid: [unclosed
        ---
        # Content
        """
        
        let file = tempDir.appendingPathComponent("malformed.md")
        try malformedFrontMatter.write(to: file, atomically: true, encoding: .utf8)
        
        let config = HirundoConfig.createDefault()
        let securityValidator = SecurityValidator(projectPath: tempDir.path, config: config)
        let contentProcessor = ContentProcessor(config: config, securityValidator: securityValidator)
        
        await XCTAssertThrowsAsyncError(try await contentProcessor.processMarkdownFile(at: file, projectPath: tempDir.path, includeDrafts: false)) { error in
            XCTAssertTrue(error is MarkdownError)
            if case MarkdownError.invalidFrontMatter = error {
                // Expected behavior
            } else {
                XCTFail("Expected invalidFrontMatter error")
            }
        }
    }
    
    func testVeryLargeMarkdownFile() async throws {
        // Create a file that exceeds typical size limits
        let largeContent = String(repeating: "# Large Content\n\nThis is a very large markdown file.\n\n", count: 10000)
        let file = tempDir.appendingPathComponent("large.md")
        try largeContent.write(to: file, atomically: true, encoding: .utf8)
        
        let config = HirundoConfig.createDefault()
        let securityValidator = SecurityValidator(projectPath: tempDir.path, config: config)
        let contentProcessor = ContentProcessor(config: config, securityValidator: securityValidator)
        
        // This should either succeed or fail with a specific large content error
        do {
            let content = try await contentProcessor.processMarkdownFile(at: file, projectPath: tempDir.path, includeDrafts: false)
            XCTAssertNotNil(content)
        } catch MarkdownError.contentTooLarge {
            // This is acceptable behavior for very large files
        } catch {
            XCTFail("Unexpected error for large file: \(error)")
        }
    }
    
    func testUnicodeMarkdownContent() async throws {
        let unicodeContent = """
        ---
        title: "テスト記事"
        author: "山田太郎"
        tags: ["日本語", "テスト", "🚀"]
        ---
        
        # 日本語のテスト記事
        
        これは**日本語**のMarkdownファイルです。
        
        ## 絵文字のテスト
        
        🎉 お祝い！ 🎊
        
        ## コードブロック
        
        ```swift
        let greeting = "こんにちは、世界！"
        print(greeting)
        ```
        
        ## リスト
        
        - 項目1
        - 項目2
        - 項目3
        """
        
        let file = tempDir.appendingPathComponent("unicode.md")
        try unicodeContent.write(to: file, atomically: true, encoding: .utf8)
        
        let config = HirundoConfig.createDefault()
        let securityValidator = SecurityValidator(projectPath: tempDir.path, config: config)
        let contentProcessor = ContentProcessor(config: config, securityValidator: securityValidator)
        
        do {
            let content = try await contentProcessor.processMarkdownFile(at: file, projectPath: tempDir.path, includeDrafts: false)
            XCTAssertNotNil(content)
            if let content = content {
                XCTAssertTrue(content.markdown.renderHTML().contains("日本語"))
                XCTAssertTrue(content.markdown.renderHTML().contains("🎉"))
                XCTAssertEqual(content.markdown.frontMatter?["title"] as? String, "テスト記事")
                XCTAssertEqual(content.markdown.frontMatter?["author"] as? String, "山田太郎")
            }
        } catch {
            XCTFail("Unicode content should be processed: \(error)")
        }
    }
    
    func testMarkdownWithSpecialCharacters() async throws {
        let specialContent = """
        ---
        title: "Special Characters"
        description: "Testing <>&\\"'`"
        ---
        
        # Testing Special Characters
        
        This content has special characters and HTML: &lt;div&gt;content&lt;/div&gt;
        
        And some quotes: "double" and 'single'
        
        Backslashes: \\ and \\n
        
        Ampersands: AT&T & Johnson & Johnson
        """
        
        let file = tempDir.appendingPathComponent("special.md")
        try specialContent.write(to: file, atomically: true, encoding: .utf8)
        
        let config = HirundoConfig.createDefault()
        let securityValidator = SecurityValidator(projectPath: tempDir.path, config: config)
        let contentProcessor = ContentProcessor(config: config, securityValidator: securityValidator)
        
        do {
            let processedContent = try await contentProcessor.processMarkdownFile(at: file, projectPath: tempDir.path, includeDrafts: false)
            XCTAssertNotNil(processedContent)
            if let content = processedContent {
                XCTAssertFalse(content.markdown.renderHTML().isEmpty)
                XCTAssertEqual(content.markdown.frontMatter?["title"] as? String, "Special Characters")
                
                // Content should be safely processed without dangerous scripts
                let html = content.markdown.renderHTML()
                XCTAssertTrue(html.contains("&lt;div&gt;") || html.contains("&amp;lt;div&amp;gt;"))
                XCTAssertTrue(html.contains("AT&amp;T") || html.contains("AT&T"))
            }
        } catch {
            XCTFail("Special characters should be handled: \(error)")
        }
    }
    
    func testZeroByteFile() async throws {
        let zeroByteFile = tempDir.appendingPathComponent("zero.md")
        FileManager.default.createFile(atPath: zeroByteFile.path, contents: Data(), attributes: nil)
        
        let config = HirundoConfig.createDefault()
        let securityValidator = SecurityValidator(projectPath: tempDir.path, config: config)
        let contentProcessor = ContentProcessor(config: config, securityValidator: securityValidator)
        
        do {
            let processedContent = try await contentProcessor.processMarkdownFile(at: zeroByteFile, projectPath: tempDir.path, includeDrafts: false)
            XCTAssertNotNil(processedContent)
            if let content = processedContent {
                XCTAssertEqual(content.markdown.renderHTML(), "")
                XCTAssertTrue(content.markdown.frontMatter?.isEmpty ?? true)
            }
        } catch {
            XCTFail("Zero byte file should be handled: \(error)")
        }
    }
    
    func testFileWithOnlyWhitespace() async throws {
        let whitespaceContent = "   \n\n\t\t\n   \n"
        let file = tempDir.appendingPathComponent("whitespace.md")
        try whitespaceContent.write(to: file, atomically: true, encoding: .utf8)
        
        let config = HirundoConfig.createDefault()
        let securityValidator = SecurityValidator(projectPath: tempDir.path, config: config)
        let contentProcessor = ContentProcessor(config: config, securityValidator: securityValidator)
        
        do {
            let processedContent = try await contentProcessor.processMarkdownFile(at: file, projectPath: tempDir.path, includeDrafts: false)
            XCTAssertNotNil(processedContent)
            if let content = processedContent {
                XCTAssertTrue(content.markdown.renderHTML().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertTrue(content.markdown.frontMatter?.isEmpty ?? true)
            }
        } catch {
            XCTFail("Whitespace-only file should be handled: \(error)")
        }
    }
    
    func testDeepDirectoryStructure() async throws {
        // Create a deeply nested directory structure
        var deepPath = tempDir!
        for i in 1...10 {
            deepPath = deepPath.appendingPathComponent("level\(i)")
            try FileManager.default.createDirectory(at: deepPath, withIntermediateDirectories: true)
        }
        
        let deepFile = deepPath.appendingPathComponent("deep.md")
        try "# Deep File\n\nThis is deep in the directory structure.".write(to: deepFile, atomically: true, encoding: .utf8)
        
        let config = HirundoConfig.createDefault()
        let securityValidator = SecurityValidator(projectPath: tempDir.path, config: config)
        let contentProcessor = ContentProcessor(config: config, securityValidator: securityValidator)
        
        do {
            let processedContent = try await contentProcessor.processMarkdownFile(at: deepFile, projectPath: tempDir.path, includeDrafts: false)
            XCTAssertNotNil(processedContent)
            if let content = processedContent {
                XCTAssertTrue(content.markdown.renderHTML().contains("Deep File"))
            }
        } catch {
            XCTFail("Deep directory structure should be handled: \(error)")
        }
    }
    
    func testFileWithInvalidUTF8() async throws {
        let file = tempDir.appendingPathComponent("invalid-utf8.md")
        
        // Create a file with invalid UTF-8 bytes
        var invalidData = Data("# Test\n".utf8)
        invalidData.append(contentsOf: [0xFF, 0xFE, 0xFD]) // Invalid UTF-8 sequence
        invalidData.append(contentsOf: "\nMore content".utf8)
        
        try invalidData.write(to: file)
        
        let config = HirundoConfig.createDefault()
        let securityValidator = SecurityValidator(projectPath: tempDir.path, config: config)
        let contentProcessor = ContentProcessor(config: config, securityValidator: securityValidator)
        
        await XCTAssertThrowsAsyncError(try await contentProcessor.processMarkdownFile(at: file, projectPath: tempDir.path, includeDrafts: false)) { error in
            if case MarkdownError.invalidEncoding = error {
                // Expected behavior
            } else {
                XCTFail("Expected invalidEncoding error, got: \(error)")
            }
        }
    }
    
    func testConcurrentFileProcessing() async throws {
        // Create multiple files for concurrent processing
        let fileCount = 10
        var files: [URL] = []
        
        for i in 1...fileCount {
            let file = tempDir.appendingPathComponent("concurrent\(i).md")
            let content = """
            ---
            title: "Concurrent File \(i)"
            number: \(i)
            ---
            
            # File \(i)
            
            This is concurrent file number \(i).
            """
            try content.write(to: file, atomically: true, encoding: .utf8)
            files.append(file)
        }
        
        let config = HirundoConfig.createDefault()
        let securityValidator = SecurityValidator(projectPath: tempDir.path, config: config)
        let contentProcessor = ContentProcessor(config: config, securityValidator: securityValidator)
        
        // Process files concurrently
        await withTaskGroup(of: Void.self) { group in
            for file in files {
                group.addTask { [tempDir] in
                    do {
                        let processedContent = try await contentProcessor.processMarkdownFile(at: file, projectPath: tempDir!.path, includeDrafts: false)
                        XCTAssertNotNil(processedContent)
                        if let content = processedContent {
                            XCTAssertFalse(content.markdown.renderHTML().isEmpty)
                            XCTAssertNotNil(content.markdown.frontMatter?["title"])
                        }
                    } catch {
                        XCTFail("Concurrent processing failed for \(file.lastPathComponent): \(error)")
                    }
                }
            }
        }
    }
    
    func testTemplateWithCircularInheritance() async throws {
        let templatesDir = tempDir.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        // Create templates with circular inheritance
        let template1 = """
        {% extends "template2.html" %}
        {% block content %}Template 1{% endblock %}
        """
        
        let template2 = """
        {% extends "template1.html" %}
        {% block content %}Template 2{% endblock %}
        """
        
        try template1.write(to: templatesDir.appendingPathComponent("template1.html"), atomically: true, encoding: .utf8)
        try template2.write(to: templatesDir.appendingPathComponent("template2.html"), atomically: true, encoding: .utf8)
        
        let templateEngine = TemplateEngine(templatesDirectory: templatesDir.path)
        
        XCTAssertThrowsError(try templateEngine.render(template: "template1.html", context: [:])) { error in
            // Should detect circular inheritance
            XCTAssertTrue(error is TemplateError)
        }
    }
    
    func testConfigWithExtremeValues() async throws {
        let extremeConfig = """
        site:
          title: "\(String(repeating: "A", count: 1000))"
          url: "https://example.com"
        
        limits:
          maxMarkdownFileSize: 1
          maxConfigFileSize: 1000000000
          maxFrontMatterSize: 0
          maxFilenameLength: 1
          maxTitleLength: 1
          maxDescriptionLength: 1
        
        timeouts:
          fileReadTimeout: 0.001
          fileWriteTimeout: 600.0
          directoryOperationTimeout: 1000.0
          httpRequestTimeout: -1.0
        """
        
        let configFile = tempDir.appendingPathComponent("extreme-config.yaml")
        try extremeConfig.write(to: configFile, atomically: true, encoding: .utf8)
        
        XCTAssertThrowsError(try HirundoConfig.load(from: configFile)) { error in
            // Should validate extreme values
            XCTAssertTrue(error is ConfigError)
        }
    }
}
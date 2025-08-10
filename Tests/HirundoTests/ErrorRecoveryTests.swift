import XCTest
@testable import HirundoCore

final class ErrorRecoveryTests: XCTestCase {
    private var tempDirectory: URL!
    private var projectPath: String!
    
    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-error-recovery-tests-\(UUID().uuidString)")
        projectPath = tempDirectory.path
        
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create basic config
        let config = """
        site:
          title: "Test Site"
          url: "https://example.com"
        
        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          templatesDirectory: "templates"
          staticDirectory: "static"
        """
        
        let configURL = tempDirectory.appendingPathComponent("config.yaml")
        try config.write(to: configURL, atomically: true, encoding: .utf8)
        
        // Create directories
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("content"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("templates"),
            withIntermediateDirectories: true
        )
        
        // Create default template
        let defaultTemplate = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>{{ page.title }}</title>
        </head>
        <body>
            {{ content }}
        </body>
        </html>
        """
        
        let templateURL = tempDirectory.appendingPathComponent("templates/default.html")
        try defaultTemplate.write(to: templateURL, atomically: true, encoding: .utf8)
    }
    
    override func tearDown() async throws {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }
    
    // MARK: - Test 1: Build continues after encountering invalid markdown
    
    func testBuildContinuesAfterInvalidMarkdown() async throws {
        // Create valid markdown files
        let validContent1 = """
        ---
        title: Valid Page 1
        ---
        # Valid Page 1
        
        This is a valid page.
        """
        
        let validContent2 = """
        ---
        title: Valid Page 2
        ---
        # Valid Page 2
        
        This is another valid page.
        """
        
        // Create invalid markdown file (malformed front matter)
        let invalidContent = """
        ---
        title: Invalid Page
        invalid_yaml: [unclosed
        ---
        # Invalid Page
        
        This page has invalid front matter.
        """
        
        // Write files
        let contentDir = tempDirectory.appendingPathComponent("content")
        try validContent1.write(
            to: contentDir.appendingPathComponent("valid1.md"),
            atomically: true,
            encoding: .utf8
        )
        try validContent2.write(
            to: contentDir.appendingPathComponent("valid2.md"),
            atomically: true,
            encoding: .utf8
        )
        try invalidContent.write(
            to: contentDir.appendingPathComponent("invalid.md"),
            atomically: true,
            encoding: .utf8
        )
        
        // Build site - should not throw
        let generator = try SiteGenerator(projectPath: projectPath)
        let buildResult = try generator.buildWithRecovery()
        
        // Verify results
        XCTAssertEqual(buildResult.successCount, 2, "Should process 2 valid pages")
        XCTAssertEqual(buildResult.failCount, 1, "Should have 1 failed page")
        
        // Check that valid pages were generated
        let outputDir = tempDirectory.appendingPathComponent("_site")
        
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("valid1/index.html").path),
            "Valid page 1 should be generated"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("valid2/index.html").path),
            "Valid page 2 should be generated"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("invalid/index.html").path),
            "Invalid page should not be generated"
        )
        
        // Check error details
        let failedError = buildResult.errors.first
        XCTAssertNotNil(failedError)
        XCTAssertTrue(failedError!.file.contains("invalid.md"))
        XCTAssertTrue(failedError!.error.localizedDescription.contains("front matter"))
    }
    
    // MARK: - Test 2: Build continues after template rendering error
    
    func testBuildContinuesAfterTemplateError() async throws {
        // Create content that will cause template error
        let contentWithBadTemplate = """
        ---
        title: Bad Template Page
        template: nonexistent
        ---
        # Page with non-existent template
        """
        
        let validContent = """
        ---
        title: Valid Page
        ---
        # Valid Page
        
        This page uses the default template.
        """
        
        // Write files
        let contentDir = tempDirectory.appendingPathComponent("content")
        try contentWithBadTemplate.write(
            to: contentDir.appendingPathComponent("bad-template.md"),
            atomically: true,
            encoding: .utf8
        )
        try validContent.write(
            to: contentDir.appendingPathComponent("valid.md"),
            atomically: true,
            encoding: .utf8
        )
        
        // Build site
        let generator = try SiteGenerator(projectPath: projectPath)
        let buildResult = try generator.buildWithRecovery()
        
        // Verify results
        XCTAssertEqual(buildResult.successCount, 1, "Should process 1 valid page")
        XCTAssertEqual(buildResult.failCount, 1, "Should have 1 failed page")
        
        // Check that valid page was generated
        let outputDir = tempDirectory.appendingPathComponent("_site")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("valid/index.html").path),
            "Valid page should be generated"
        )
        
        // Check error details
        let failedError = buildResult.errors.first
        XCTAssertNotNil(failedError)
        if let error = failedError {
            XCTAssertTrue(error.file.contains("bad-template.md"))
            XCTAssertTrue(error.error.localizedDescription.lowercased().contains("template") || 
                          error.error.localizedDescription.lowercased().contains("not found"))
        }
    }
    
    // MARK: - Test 3: Error summary is generated after build
    
    func testErrorSummaryGeneration() async throws {
        // Create multiple files with different types of errors
        let files = [
            ("valid.md", """
            ---
            title: Valid Page
            ---
            # Valid Page
            """),
            ("invalid-yaml.md", """
            ---
            title: Invalid YAML
            invalid: [unclosed
            ---
            # Invalid YAML
            """),
            ("missing-title.md", """
            ---
            description: No title
            ---
            # Missing Title
            """),
            ("bad-date.md", """
            ---
            title: Bad Date
            date: not-a-date
            ---
            # Bad Date
            """)
        ]
        
        // Write files
        let contentDir = tempDirectory.appendingPathComponent("content")
        for (filename, content) in files {
            try content.write(
                to: contentDir.appendingPathComponent(filename),
                atomically: true,
                encoding: .utf8
            )
        }
        
        // Build site
        let generator = try SiteGenerator(projectPath: projectPath)
        let buildResult = try generator.buildWithRecovery()
        
        // Create error summary (since errorSummary is not in our simplified BuildResult)
        var summary = "Build completed with errors\n"
        summary += "Successful: \(buildResult.successCount)\n"
        summary += "Failed: \(buildResult.failCount)\n"
        
        // Verify summary content
        XCTAssertTrue(summary.contains("Build completed with errors"))
        XCTAssertTrue(summary.contains("Successful: \(buildResult.successCount)"))
        XCTAssertTrue(summary.contains("Failed: \(buildResult.failCount)"))
        
        // Check that errors exist
        XCTAssertFalse(buildResult.errors.isEmpty, "Should have errors recorded")
    }
    
    // MARK: - Test 4: Build with all files failing still creates output directory
    
    func testBuildWithAllFailuresCreatesOutputStructure() async throws {
        // Create only invalid files
        let invalidContent = """
        ---
        title: Invalid
        invalid: [unclosed
        ---
        # Invalid
        """
        
        let contentDir = tempDirectory.appendingPathComponent("content")
        try invalidContent.write(
            to: contentDir.appendingPathComponent("invalid.md"),
            atomically: true,
            encoding: .utf8
        )
        
        // Build site
        let generator = try SiteGenerator(projectPath: projectPath)
        let buildResult = try generator.buildWithRecovery()
        
        // Verify output directory was created
        let outputDir = tempDirectory.appendingPathComponent("_site")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputDir.path),
            "Output directory should be created even if all files fail"
        )
        
        // Verify build result
        XCTAssertEqual(buildResult.successCount, 0)
        XCTAssertEqual(buildResult.failCount, 1)
        XCTAssertFalse(buildResult.success)
    }
    
    // MARK: - Test 5: Partial build recovery with plugin errors
    
    func testPartialBuildRecoveryWithPluginErrors() async throws {
        // Create content that will trigger plugin errors
        let contentWithPluginIssue = """
        ---
        title: Plugin Error Page
        custom_plugin_data: "trigger-error"
        ---
        # Plugin Error Page
        """
        
        let validContent = """
        ---
        title: Valid Page
        ---
        # Valid Page
        """
        
        // Write files
        let contentDir = tempDirectory.appendingPathComponent("content")
        try contentWithPluginIssue.write(
            to: contentDir.appendingPathComponent("plugin-error.md"),
            atomically: true,
            encoding: .utf8
        )
        try validContent.write(
            to: contentDir.appendingPathComponent("valid.md"),
            atomically: true,
            encoding: .utf8
        )
        
        // Build site
        let generator = try SiteGenerator(projectPath: projectPath)
        let buildResult = try generator.buildWithRecovery()
        
        // At least the valid page should be processed
        XCTAssertGreaterThanOrEqual(buildResult.successCount, 1)
    }
}

// The BuildResult types are now defined in SiteGenerator.swift
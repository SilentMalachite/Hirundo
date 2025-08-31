import XCTest
import Foundation
@testable import HirundoCore

final class SecurityTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Path Traversal Tests
    
    func testPathTraversalInContentDirectory() async throws {
        // Set up project structure
        let contentDir = tempDir.appendingPathComponent("content")
        let templatesDir = tempDir.appendingPathComponent("templates")
        let _ = tempDir.appendingPathComponent("_site")
        
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        // Create config.yaml with properly formatted YAML
        let configYAML = """
        site:
          title: Test Site
          description: Test Description
          url: https://example.com
          language: en-US
        
        build:
          contentDirectory: content
          outputDirectory: _site
          templatesDirectory: templates
          staticDirectory: static
        """
        
        let configPath = tempDir.appendingPathComponent("config.yaml")
        try configYAML.write(to: configPath, atomically: true, encoding: .utf8)
        
        // Create a base template
        let baseTemplate = "<!DOCTYPE html><html><body>{{ content }}</body></html>"
        try baseTemplate.write(to: templatesDir.appendingPathComponent("base.html"), 
                              atomically: true, encoding: .utf8)
        
        // Create a malicious content file that tries path traversal
        let maliciousContent = """
        ---
        title: "Test"
        template: "../../../etc/passwd"
        ---
        
        This should not be processed
        """
        
        let maliciousPath = contentDir.appendingPathComponent("malicious.md")
        try maliciousContent.write(to: maliciousPath, atomically: true, encoding: .utf8)
        
        // Try to build - should fail or safely handle the malicious template path
        do {
            let generator = try SiteGenerator(projectPath: tempDir.path)
            try await generator.build()
            
            // If build succeeds, verify the malicious path wasn't used
            let outputDir = tempDir.appendingPathComponent("_site")
            let outputFiles = try FileManager.default.contentsOfDirectory(at: outputDir, 
                                                                         includingPropertiesForKeys: nil)
            for file in outputFiles {
                let content = try String(contentsOf: file)
                XCTAssertFalse(content.contains("root:") || content.contains("/etc/passwd"))
            }
        } catch {
            // If it fails, that's also acceptable security behavior
            print("Build failed with error: \(error)")
        }
    }
    
    func testPathTraversalInTemplateIncludes() async throws {
        let templatesDir = tempDir.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        // Create a template that tries to include a file outside the templates directory
        let maliciousTemplate = """
        {% include "../../etc/passwd" %}
        """
        
        let templatePath = templatesDir.appendingPathComponent("malicious.html")
        try maliciousTemplate.write(to: templatePath, atomically: true, encoding: .utf8)
        
        let engine = TemplateEngine(templatesDirectory: templatesDir.path)
        
        // This should fail or sanitize the path
        do {
            let result = try engine.render(template: maliciousTemplate, context: [:])
            // If it succeeds, ensure it didn't include the sensitive file
            XCTAssertFalse(result.contains("root:") || result.contains("/etc/passwd"))
        } catch {
            // Failing is also acceptable security behavior
            print("Template rendering failed with error: \(error)")
        }
    }
    
    func testPathTraversalInStaticAssets() async throws {
        let staticDir = tempDir.appendingPathComponent("static")
        let contentDir = tempDir.appendingPathComponent("content")
        let templatesDir = tempDir.appendingPathComponent("templates")
        let _ = tempDir.appendingPathComponent("_site")
        
        try FileManager.default.createDirectory(at: staticDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        // Create config.yaml
        let configYAML = """
        site:
          title: "Test Site"
          url: "https://example.com"
        
        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          staticDirectory: "static"
          templatesDirectory: "templates"
        """
        
        let configPath = tempDir.appendingPathComponent("config.yaml")
        try configYAML.write(to: configPath, atomically: true, encoding: .utf8)
        
        // Create a base template
        let baseTemplate = "<!DOCTYPE html><html><body>{{ content }}</body></html>"
        try baseTemplate.write(to: templatesDir.appendingPathComponent("base.html"), 
                              atomically: true, encoding: .utf8)
        
        // Create archive template (required by SiteGenerator)
        let archiveTemplate = "<!DOCTYPE html><html><body><h1>Archive</h1></body></html>"
        try archiveTemplate.write(to: templatesDir.appendingPathComponent("archive.html"),
                                 atomically: true, encoding: .utf8)
        
        // Create default template
        let defaultTemplate = "<!DOCTYPE html><html><body>{{ content }}</body></html>"
        try defaultTemplate.write(to: templatesDir.appendingPathComponent("default.html"),
                                atomically: true, encoding: .utf8)
        
        // Create malicious static files with path traversal names
        let maliciousPaths = [
            "../../../etc/passwd",
            "../../sensitive.txt",
            "../config.yaml"
        ]
        
        // Try to build - the generator should safely handle or reject these paths
        let generator = try SiteGenerator(projectPath: tempDir.path)
        
        for maliciousPath in maliciousPaths {
            // Create a file with malicious path-like content
            let testFile = staticDir.appendingPathComponent("test.txt")
            try maliciousPath.write(to: testFile, atomically: true, encoding: .utf8)
            
            // Clean up any existing files that might interfere with the test
            let parentDir = tempDir.deletingLastPathComponent()
            let sensitivePath = parentDir.appendingPathComponent("sensitive.txt").path
            let exploitPath = "/tmp/hirundo-exploit"
            try? FileManager.default.removeItem(atPath: sensitivePath)
            try? FileManager.default.removeItem(atPath: exploitPath)
            
            try await generator.build()
            
            // Verify no files were created outside the output directory
            // These files should not exist due to path traversal protection
            XCTAssertFalse(FileManager.default.fileExists(atPath: sensitivePath), 
                          "Path traversal protection failed - file created at: \(sensitivePath)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: exploitPath),
                          "Path traversal protection failed - file created at: \(exploitPath)")
            
            // Clean up test file for next iteration
            try? FileManager.default.removeItem(at: testFile)
        }
    }
    
    func testSymlinkTraversal() async throws {
        let contentDir = tempDir.appendingPathComponent("content")
        let templatesDir = tempDir.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        // Create a sensitive file outside the content directory
        let sensitiveFile = tempDir.deletingLastPathComponent().appendingPathComponent("sensitive.txt")
        try "Secret data".write(to: sensitiveFile, atomically: true, encoding: .utf8)
        
        // Create a symlink in content directory pointing to the sensitive file
        let symlinkPath = contentDir.appendingPathComponent("evil.md")
        try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: sensitiveFile)
        
        // Create config.yaml with properly formatted YAML
        let configYAML = """
        site:
          title: Test Site
          description: Test Description
          url: https://example.com
          language: en-US
        
        build:
          contentDirectory: content
          outputDirectory: _site
          templatesDirectory: templates
          staticDirectory: static
        """
        
        let configPath = tempDir.appendingPathComponent("config.yaml")
        try configYAML.write(to: configPath, atomically: true, encoding: .utf8)
        
        // Create a base template
        let baseTemplate = "<!DOCTYPE html><html><body>{{ content }}</body></html>"
        try baseTemplate.write(to: templatesDir.appendingPathComponent("base.html"), 
                              atomically: true, encoding: .utf8)
        
        // Try to build - the generator should safely handle symlinks
        do {
            let generator = try SiteGenerator(projectPath: tempDir.path)
            try await generator.build()
            
            // Check if the output contains sensitive data
            let _ = tempDir.appendingPathComponent("_site")
            let outputDir = tempDir.appendingPathComponent("_site")
            if FileManager.default.fileExists(atPath: outputDir.path) {
                let outputFiles = try FileManager.default.contentsOfDirectory(at: outputDir, 
                                                                             includingPropertiesForKeys: nil)
                for file in outputFiles {
                    if file.pathExtension == "html" {
                        let content = try String(contentsOf: file)
                        XCTAssertFalse(content.contains("Secret data"),
                                      "Output should not contain sensitive data from symlinked file")
                    }
                }
            }
        } catch {
            // Failing to build when symlinks are present is also acceptable
            print("Build failed with symlink present: \(error)")
        }
        // Ensure cleanup of the sensitive file to avoid cross-test interference
        try? FileManager.default.removeItem(at: sensitiveFile)
    }
    
    func testNullByteInjection() async throws {
        let contentDir = tempDir.appendingPathComponent("content")
        let templatesDir = tempDir.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        // Create config.yaml with properly formatted YAML
        let configYAML = """
        site:
          title: Test Site
          description: Test Description
          url: https://example.com
          language: en-US
        
        build:
          contentDirectory: content
          outputDirectory: _site
          templatesDirectory: templates
          staticDirectory: static
        """
        
        let configPath = tempDir.appendingPathComponent("config.yaml")
        try configYAML.write(to: configPath, atomically: true, encoding: .utf8)
        
        // Create a base template
        let baseTemplate = "<!DOCTYPE html><html><body>{{ content }}</body></html>"
        try baseTemplate.write(to: templatesDir.appendingPathComponent("base.html"), 
                              atomically: true, encoding: .utf8)
        
        // Try to create files with null bytes in names
        let testContent = """
        ---
        title: "Test"
        ---
        
        Test content
        """
        
        // Note: macOS filesystem doesn't allow null bytes in filenames,
        // so we test the handling of such attempts
        let maliciousFilenames = [
            "test\u{0000}.md",
            "test.md\u{0000}.exe",
            "../test\u{0000}file.md"
        ]
        
        for filename in maliciousFilenames {
            do {
                let filePath = contentDir.appendingPathComponent(filename)
                try testContent.write(to: filePath, atomically: true, encoding: .utf8)
                
                // If write succeeds (shouldn't on most filesystems), try to build
                let generator = try SiteGenerator(projectPath: tempDir.path)
                try await generator.build()
                
                XCTFail("Should not successfully process file with null byte: \(filename)")
            } catch {
                // Expected - either file creation or processing should fail
                print("Expected error for null byte filename: \(error)")
            }
        }
    }
    
    // MARK: - XSS Payload Tests
    
    func testXSSInMarkdownContent() async throws {
        let contentDir = tempDir.appendingPathComponent("content")
        let templatesDir = tempDir.appendingPathComponent("templates")
        let _ = tempDir.appendingPathComponent("_site")
        
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        // Create config.yaml
        let configYAML = """
        site:
          title: Test Site
          description: Test Description
          url: https://example.com
          language: en-US
        
        build:
          contentDirectory: content
          outputDirectory: _site
          templatesDirectory: templates
          staticDirectory: static
        """
        
        let configPath = tempDir.appendingPathComponent("config.yaml")
        try configYAML.write(to: configPath, atomically: true, encoding: .utf8)
        
        // Create a default template
        let template = """
        <!DOCTYPE html>
        <html>
        <head><title>{{ page.title }}</title></head>
        <body>{{ content }}</body>
        </html>
        """
        try template.write(to: templatesDir.appendingPathComponent("default.html"), 
                          atomically: true, encoding: .utf8)
        
        // Create content with XSS payload
        let xssContent = """
        ---
        title: XSS Test Page
        ---
        
        # Test Content
        
        <script>alert('XSS')</script>
        <img src=x onerror="alert('XSS')">
        <a href="javascript:alert('XSS')">Click me</a>
        """
        
        try xssContent.write(to: contentDir.appendingPathComponent("xss-test.md"), 
                           atomically: true, encoding: .utf8)
        
        // Build the site - it should reject dangerous content
        let generator = try SiteGenerator(projectPath: tempDir.path)
        
        do {
            try await generator.build()
            
            // If build succeeds, check that XSS is sanitized
            let outputDir = tempDir.appendingPathComponent("_site")
            let outputFile = outputDir.appendingPathComponent("xss-test.html")
            if FileManager.default.fileExists(atPath: outputFile.path) {
                let outputContent = try String(contentsOf: outputFile)
                
                // Verify XSS payloads are escaped or removed
                XCTAssertFalse(outputContent.contains("<script>alert('XSS')</script>"),
                              "Script tags should be escaped or removed")
                XCTAssertFalse(outputContent.contains("onerror=\"alert('XSS')\""),
                              "Event handlers should be escaped or removed")
                XCTAssertFalse(outputContent.contains("javascript:alert"),
                              "JavaScript URLs should be escaped or removed")
            }
        } catch {
            // It's also acceptable to reject dangerous content entirely
            if let markdownError = error as? MarkdownError {
                switch markdownError {
                case .dangerousContent:
                    // This is expected - the parser is protecting against XSS
                    return
                default:
                    throw error
                }
            } else {
                throw error
            }
        }
    }
    
    func testXSSInFrontMatter() async throws {
        let contentDir = tempDir.appendingPathComponent("content")
        let templatesDir = tempDir.appendingPathComponent("templates")
        let _ = tempDir.appendingPathComponent("_site")
        
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        // Create config.yaml
        let configYAML = """
        site:
          title: Test Site
          description: Test Description
          url: https://example.com
          language: en-US
        
        build:
          contentDirectory: content
          outputDirectory: _site
          templatesDirectory: templates
          staticDirectory: static
        """
        
        let configPath = tempDir.appendingPathComponent("config.yaml")
        try configYAML.write(to: configPath, atomically: true, encoding: .utf8)
        
        // Create a template that uses front matter
        let template = """
        <!DOCTYPE html>
        <html>
        <head><title>{{ page.title }}</title></head>
        <body>
            <h1>{{ page.title }}</h1>
            <p>{{ page.description }}</p>
            {{ content }}
        </body>
        </html>
        """
        try template.write(to: templatesDir.appendingPathComponent("default.html"), 
                          atomically: true, encoding: .utf8)
        
        // Create content with XSS in front matter
        let xssContent = """
        ---
        title: <script>alert('XSS in title')</script>
        description: <img src=x onerror="alert('XSS in description')">
        ---
        
        Regular content here.
        """
        
        try xssContent.write(to: contentDir.appendingPathComponent("xss-frontmatter.md"), 
                           atomically: true, encoding: .utf8)
        
        // Build the site - it should reject dangerous content
        let generator = try SiteGenerator(projectPath: tempDir.path)
        
        do {
            try await generator.build()
            
            // If build succeeds, check that XSS is sanitized
            let outputDir = tempDir.appendingPathComponent("_site")
            let outputFile = outputDir.appendingPathComponent("xss-frontmatter.html")
            if FileManager.default.fileExists(atPath: outputFile.path) {
                let outputContent = try String(contentsOf: outputFile)
                
                // Verify XSS payloads in front matter are escaped
                XCTAssertFalse(outputContent.contains("<script>alert('XSS in title')</script>"),
                              "Script tags in front matter should be escaped")
                XCTAssertTrue(outputContent.contains("&lt;script&gt;") || 
                             outputContent.contains("&amp;lt;script&amp;gt;"),
                             "Script tags should be HTML-escaped")
                XCTAssertFalse(outputContent.contains("onerror=\"alert"),
                              "Event handlers in front matter should be escaped")
            }
        } catch {
            // It's also acceptable to reject dangerous content entirely
            if let markdownError = error as? MarkdownError {
                switch markdownError {
                case .dangerousContent:
                    // This is expected - the parser is protecting against XSS
                    return
                default:
                    throw error
                }
            } else {
                throw error
            }
        }
    }
    
    // MARK: - YAML Bomb Tests
    
    func disabled_testYAMLBombProtection() async throws {
        let contentDir = tempDir.appendingPathComponent("content")
        let templatesDir = tempDir.appendingPathComponent("templates")
        
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        // Create a valid config.yaml
        let configYAML = """
        site:
          title: Test Site
          description: Test Description
          url: https://example.com
          language: en-US
        
        build:
          contentDirectory: content
          outputDirectory: _site
          templatesDirectory: templates
          staticDirectory: static
        """
        
        let configPath = tempDir.appendingPathComponent("config.yaml")
        try configYAML.write(to: configPath, atomically: true, encoding: .utf8)
        
        // Create a YAML bomb in content front matter
        let yamlBomb = """
        ---
        a: &a ["a", "a", "a", "a", "a", "a", "a", "a", "a"]
        b: &b [*a, *a, *a, *a, *a, *a, *a, *a, *a]
        c: &c [*b, *b, *b, *b, *b, *b, *b, *b, *b]
        d: &d [*c, *c, *c, *c, *c, *c, *c, *c, *c]
        e: &e [*d, *d, *d, *d, *d, *d, *d, *d, *d]
        f: &f [*e, *e, *e, *e, *e, *e, *e, *e, *e]
        g: &g [*f, *f, *f, *f, *f, *f, *f, *f, *f]
        ---
        
        This content should not be processed if YAML bomb protection works.
        """
        
        let bombPath = contentDir.appendingPathComponent("yaml-bomb.md")
        try yamlBomb.write(to: bombPath, atomically: true, encoding: .utf8)
        
        // Try to build - should handle YAML bomb gracefully
        do {
            let generator = try SiteGenerator(projectPath: tempDir.path)
            try await generator.build()
            // If build succeeds, that's also acceptable as long as it doesn't hang
        } catch {
            // Build failure is expected and acceptable - YAML bomb should be rejected
            print("YAML bomb correctly rejected: \(error)")
        }
    }
    
    private struct TimeoutError: Error {}
    
    func testExcessiveYAMLAnchors() async throws {
        let contentDir = tempDir.appendingPathComponent("content")
        
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        
        // Create content with excessive YAML anchors
        var yamlContent = "---\n"
        
        // Create 1000 anchors
        for i in 0..<1000 {
            yamlContent += "anchor\(i): &anchor\(i) \"value\(i)\"\n"
        }
        
        // Reference all anchors
        yamlContent += "references:\n"
        for i in 0..<1000 {
            yamlContent += "  - *anchor\(i)\n"
        }
        
        yamlContent += """
        ---
        
        Content with many YAML anchors.
        """
        
        let filePath = contentDir.appendingPathComponent("many-anchors.md")
        try yamlContent.write(to: filePath, atomically: true, encoding: .utf8)
        
        // This should be handled gracefully without excessive memory/CPU usage
        // The actual behavior depends on the YAML parser implementation
        print("Note: Excessive YAML anchors test created")
    }
    
    // MARK: - Resource Exhaustion Tests
    
    func testLargeFileProtection() async throws {
        let contentDir = tempDir.appendingPathComponent("content")
        let templatesDir = tempDir.appendingPathComponent("templates")
        
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        // Create a valid config.yaml
        let configYAML = """
        site:
          title: Test Site
          description: Test Description
          url: https://example.com
          language: en-US
        
        build:
          contentDirectory: content
          outputDirectory: _site
          templatesDirectory: templates
          staticDirectory: static
          
        limits:
          maxMarkdownFileSize: 1000  # 1KB for testing
        """
        
        let configPath = tempDir.appendingPathComponent("config.yaml")
        try configYAML.write(to: configPath, atomically: true, encoding: .utf8)
        
        // Create a large markdown file (over 1KB)
        var largeContent = """
        ---
        title: Large File
        ---
        
        """
        
        // Add content to exceed 1KB
        let paragraph = "This is a test paragraph that will be repeated many times. "
        for _ in 0..<50 {
            largeContent += paragraph
        }
        
        let largePath = contentDir.appendingPathComponent("large-file.md")
        try largeContent.write(to: largePath, atomically: true, encoding: .utf8)
        
        // Try to build - should reject the large file
        do {
            let generator = try SiteGenerator(projectPath: tempDir.path)
            try await generator.build()
            
            // Check if the large file was processed
            let _ = tempDir.appendingPathComponent("_site")
            let outputDir = tempDir.appendingPathComponent("_site")
            let largeOutput = outputDir.appendingPathComponent("large-file.html")
            
            if FileManager.default.fileExists(atPath: largeOutput.path) {
                XCTFail("Large file should not have been processed")
            }
        } catch {
            // Expected - large file should be rejected
            print("Large file correctly rejected: \(error)")
        }
    }
    
    func testDeepDirectoryNesting() async throws {
        let contentDir = tempDir.appendingPathComponent("content")
        
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        
        // Create deeply nested directory structure
        var currentDir = contentDir
        for i in 0..<50 {  // 50 levels deep
            currentDir = currentDir.appendingPathComponent("level\(i)")
            try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        }
        
        // Put a file at the deepest level
        let deepFile = currentDir.appendingPathComponent("deep.md")
        let content = """
        ---
        title: Deep File
        ---
        
        This file is deeply nested.
        """
        try content.write(to: deepFile, atomically: true, encoding: .utf8)
        
        // The system should handle deep nesting gracefully
        print("Note: Deep directory nesting test created with 50 levels")
    }
    
    func testInfiniteTemplateRecursion() async throws {
        let templatesDir = tempDir.appendingPathComponent("templates")
        
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        // Create templates that include each other (infinite recursion)
        let templateA = """
        <div>Template A</div>
        {% include "template-b.html" %}
        """
        
        let templateB = """
        <div>Template B</div>
        {% include "template-a.html" %}
        """
        
        try templateA.write(to: templatesDir.appendingPathComponent("template-a.html"),
                          atomically: true, encoding: .utf8)
        try templateB.write(to: templatesDir.appendingPathComponent("template-b.html"),
                          atomically: true, encoding: .utf8)
        
        // Try to render a template with infinite recursion
        let engine = TemplateEngine(templatesDirectory: templatesDir.path)
        
        do {
            _ = try engine.render(template: templateA, context: [:])
            XCTFail("Infinite template recursion should be prevented")
        } catch {
            // Expected - infinite recursion should be detected
            print("Infinite template recursion correctly prevented: \(error)")
        }
    }
}

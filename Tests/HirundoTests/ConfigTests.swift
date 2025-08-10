import XCTest
import Yams
@testable import HirundoCore

final class ConfigTests: XCTestCase {
    
    func testSiteConfigParsing() throws {
        let yamlString = """
        site:
          title: "テストサイト"
          description: "Hirundoで作成されたテストサイト"
          url: "https://example.com"
          language: "ja-JP"
          author:
            name: "テスト太郎"
            email: "test@example.com"
        """
        
        let config = try SiteConfig.parse(from: yamlString)
        
        XCTAssertEqual(config.site.title, "テストサイト")
        XCTAssertEqual(config.site.description, "Hirundoで作成されたテストサイト")
        XCTAssertEqual(config.site.url, "https://example.com")
        XCTAssertEqual(config.site.language, "ja-JP")
        XCTAssertEqual(config.site.author?.name, "テスト太郎")
        XCTAssertEqual(config.site.author?.email, "test@example.com")
    }
    
    func testBuildConfigParsing() throws {
        let yamlString = """
        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          staticDirectory: "static"
          templatesDirectory: "templates"
        """
        
        let config = try BuildConfig.parse(from: yamlString)
        
        XCTAssertEqual(config.build.contentDirectory, "content")
        XCTAssertEqual(config.build.outputDirectory, "_site")
        XCTAssertEqual(config.build.staticDirectory, "static")
        XCTAssertEqual(config.build.templatesDirectory, "templates")
    }
    
    func testServerConfigParsing() throws {
        let yamlString = """
        server:
          port: 8080
          liveReload: true
        """
        
        let config = try ServerConfig.parse(from: yamlString)
        
        XCTAssertEqual(config.server.port, 8080)
        XCTAssertTrue(config.server.liveReload)
    }
    
    func testBlogConfigParsing() throws {
        let yamlString = """
        blog:
          postsPerPage: 10
          generateArchive: true
          generateCategories: true
          generateTags: true
        """
        
        let config = try BlogConfig.parse(from: yamlString)
        
        XCTAssertEqual(config.blog.postsPerPage, 10)
        XCTAssertTrue(config.blog.generateArchive)
        XCTAssertTrue(config.blog.generateCategories)
        XCTAssertTrue(config.blog.generateTags)
    }
    
    func testPluginConfigParsing() throws {
        let yamlString = """
        plugins:
          - name: sitemap
            enabled: true
          - name: minify
            enabled: true
            removeComments: true
            removeWhitespace: false
        """
        
        let config = try PluginsConfig.parse(from: yamlString)
        
        XCTAssertEqual(config.plugins.count, 2)
        
        let sitemapPlugin = config.plugins[0]
        XCTAssertEqual(sitemapPlugin.name, "sitemap")
        XCTAssertTrue(sitemapPlugin.enabled)
        
        let minifyPlugin = config.plugins[1]
        XCTAssertEqual(minifyPlugin.name, "minify")
        XCTAssertTrue(minifyPlugin.enabled)
        XCTAssertTrue(minifyPlugin.settings["removeComments"] as? Bool ?? false)
        XCTAssertFalse(minifyPlugin.settings["removeWhitespace"] as? Bool ?? true)
    }
    
    func testCompleteConfigParsing() throws {
        let yamlString = """
        site:
          title: "My Site"
          description: "A website built with Hirundo"
          url: "https://example.com"
          language: "en-US"
          author:
            name: "Your Name"
            email: "you@example.com"
        
        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          staticDirectory: "static"
          templatesDirectory: "templates"
        
        server:
          port: 8080
          liveReload: true
        
        blog:
          postsPerPage: 10
          generateArchive: true
          generateCategories: true
          generateTags: true
        
        plugins:
          - name: sitemap
            enabled: true
          - name: rss
            enabled: true
          - name: minify
            enabled: true
            removeComments: true
        """
        
        let config = try HirundoConfig.parse(from: yamlString)
        
        XCTAssertEqual(config.site.title, "My Site")
        XCTAssertEqual(config.build.contentDirectory, "content")
        XCTAssertEqual(config.server.port, 8080)
        XCTAssertEqual(config.blog.postsPerPage, 10)
        XCTAssertEqual(config.plugins.count, 3)
    }
    
    func testConfigFileLoading() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test-config.yaml")
        
        let yamlContent = """
        site:
          title: "Test Site"
          url: "https://test.com"
        """
        
        try yamlContent.write(to: configPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configPath) }
        
        let config = try HirundoConfig.load(from: configPath)
        
        XCTAssertEqual(config.site.title, "Test Site")
        XCTAssertEqual(config.site.url, "https://test.com")
    }
    
    func testInvalidConfigError() throws {
        let invalidYaml = """
        site:
          title: 123
          url: ["not", "a", "string"]
        """
        
        XCTAssertThrows(try HirundoConfig.parse(from: invalidYaml)) { (error: ConfigError) in
            switch error {
            case .invalidFormat:
                break
            default:
                XCTFail("Expected invalidFormat error")
            }
        }
    }
    
    func testMissingRequiredFieldError() throws {
        let incompleteYaml = """
        site:
          title: "Test Site"
        """
        
        XCTAssertThrows(try HirundoConfig.parse(from: incompleteYaml)) { (error: ConfigError) in
            switch error {
            case .missingRequiredField(let field):
                XCTAssertEqual(field, "url")
            default:
                XCTFail("Expected missingRequiredField error")
            }
        }
    }
    
    func testDefaultValues() throws {
        let minimalYaml = """
        site:
          title: "Minimal Site"
          url: "https://minimal.com"
        """
        
        let config = try HirundoConfig.parse(from: minimalYaml)
        
        XCTAssertEqual(config.build.contentDirectory, "content")
        XCTAssertEqual(config.build.outputDirectory, "_site")
        XCTAssertEqual(config.server.port, 8080)
        XCTAssertTrue(config.server.liveReload)
        XCTAssertEqual(config.blog.postsPerPage, 10)
    }
    
    // MARK: - Timeout Configuration Tests
    
    func testDefaultTimeoutValues() throws {
        let minimalYaml = """
        site:
          title: "Test Site"
          url: "https://test.com"
        """
        
        let config = try HirundoConfig.parse(from: minimalYaml)
        
        // Test default timeout values
        XCTAssertEqual(config.timeouts.fileReadTimeout, 30.0)
        XCTAssertEqual(config.timeouts.fileWriteTimeout, 30.0)
        XCTAssertEqual(config.timeouts.directoryOperationTimeout, 15.0)
        XCTAssertEqual(config.timeouts.httpRequestTimeout, 10.0)
        XCTAssertEqual(config.timeouts.fsEventsTimeout, 5.0)
        XCTAssertEqual(config.timeouts.serverStartTimeout, 30.0)
    }
    
    func testCustomTimeoutValues() throws {
        let yamlWithTimeouts = """
        site:
          title: "Test Site"
          url: "https://test.com"
        
        timeouts:
          fileReadTimeout: 60.0
          fileWriteTimeout: 45.0
          directoryOperationTimeout: 20.0
          httpRequestTimeout: 15.0
          fsEventsTimeout: 10.0
          serverStartTimeout: 60.0
        """
        
        let config = try HirundoConfig.parse(from: yamlWithTimeouts)
        
        XCTAssertEqual(config.timeouts.fileReadTimeout, 60.0)
        XCTAssertEqual(config.timeouts.fileWriteTimeout, 45.0)
        XCTAssertEqual(config.timeouts.directoryOperationTimeout, 20.0)
        XCTAssertEqual(config.timeouts.httpRequestTimeout, 15.0)
        XCTAssertEqual(config.timeouts.fsEventsTimeout, 10.0)
        XCTAssertEqual(config.timeouts.serverStartTimeout, 60.0)
    }
    
    func testInvalidTimeoutValues() throws {
        let yamlWithInvalidTimeouts = """
        site:
          title: "Test Site"
          url: "https://test.com"
        
        timeouts:
          fileReadTimeout: -5.0
          fileWriteTimeout: 0.0
        """
        
        do {
            let _ = try HirundoConfig.parse(from: yamlWithInvalidTimeouts)
            XCTFail("Expected error for invalid timeout values")
        } catch let error as ConfigError {
            switch error {
            case .invalidValue(let message):
                XCTAssertTrue(message.contains("timeout"))
            case .parseError:
                // This is acceptable - the validation error is wrapped in a parse error
                break
            case .invalidFormat:
                // This is also acceptable for invalid YAML format
                break
            default:
                XCTFail("Expected invalidValue, parseError, or invalidFormat, got \(error)")
            }
        } catch {
            // Direct validation error from TimeoutConfig
            XCTAssertTrue(error.localizedDescription.contains("timeout") || error.localizedDescription.contains("greater than 0"))
        }
    }
    
    func testTimeoutValidationRange() throws {
        let yamlWithExcessiveTimeout = """
        site:
          title: "Test Site"
          url: "https://test.com"
        
        timeouts:
          fileReadTimeout: 3600.0
        """
        
        do {
            let _ = try HirundoConfig.parse(from: yamlWithExcessiveTimeout)
            XCTFail("Expected error for excessive timeout value")
        } catch let error as ConfigError {
            switch error {
            case .invalidValue(let message):
                XCTAssertTrue(message.contains("600") || message.contains("maximum"))
            case .parseError:
                // The validation error is wrapped in a parse error
                break
            case .invalidFormat:
                // This is also acceptable for invalid YAML format
                break
            default:
                XCTFail("Expected invalidValue, parseError, or invalidFormat, got \(error)")
            }
        } catch {
            // Direct validation error from TimeoutConfig
            XCTAssertTrue(error.localizedDescription.contains("600") || error.localizedDescription.contains("maximum"))
        }
    }
}
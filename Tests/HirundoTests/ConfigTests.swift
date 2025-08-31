import XCTest
import Yams
@testable import HirundoCore

final class ConfigTests: XCTestCase {
    
    func testSiteConfigParsing() throws {
        let yamlString = """
        site:
          title: "My Site"
          description: "A test site"
          url: "https://example.com"
          language: "en"
          author:
            name: "John Doe"
            email: "john@example.com"
        """
        
        let config = try HirundoConfig.parse(from: yamlString)
        
        XCTAssertEqual(config.site.title, "My Site")
        XCTAssertEqual(config.site.description, "A test site")
        XCTAssertEqual(config.site.url, "https://example.com")
        XCTAssertEqual(config.site.language, "en")
        XCTAssertEqual(config.site.author?.name, "John Doe")
        XCTAssertEqual(config.site.author?.email, "john@example.com")
    }
    
    func testServerConfigParsing() throws {
        let yamlString = """
        site:
          title: "Test Site"
          url: "https://test.com"
        
        server:
          port: 8080
          liveReload: true
        """
        
        let config = try HirundoConfig.parse(from: yamlString)
        
        XCTAssertEqual(config.server.port, 8080)
        XCTAssertTrue(config.server.liveReload)
    }
    
    func testBlogConfigParsing() throws {
        let yamlString = """
        site:
          title: "Test Site"
          url: "https://test.com"
        
        blog:
          postsPerPage: 10
          generateArchive: true
          generateCategories: true
          generateTags: true
        """
        
        let config = try HirundoConfig.parse(from: yamlString)
        
        XCTAssertEqual(config.blog.postsPerPage, 10)
        XCTAssertTrue(config.blog.generateArchive)
        XCTAssertTrue(config.blog.generateCategories)
        XCTAssertTrue(config.blog.generateTags)
    }
    
    func testFeaturesConfigParsing() throws {
        let yamlString = """
        site:
          title: "Test Site"
          url: "https://test.com"
        
        features:
          sitemap: true
          rss: false
          searchIndex: true
          minify: true
        """
        
        let config = try HirundoConfig.parse(from: yamlString)
        
        XCTAssertTrue(config.features.sitemap)
        XCTAssertFalse(config.features.rss)
        XCTAssertTrue(config.features.searchIndex)
        XCTAssertTrue(config.features.minify)
    }
    
    func testBuildConfigParsing() throws {
        let yamlString = """
        site:
          title: "Test Site"
          url: "https://test.com"
        
        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          staticDirectory: "static"
          templatesDirectory: "templates"
        """
        
        let config = try HirundoConfig.parse(from: yamlString)
        
        XCTAssertEqual(config.build.contentDirectory, "content")
        XCTAssertEqual(config.build.outputDirectory, "_site")
        XCTAssertEqual(config.build.staticDirectory, "static")
        XCTAssertEqual(config.build.templatesDirectory, "templates")
    }
    
    func testCompleteConfigParsing() throws {
        let yamlString = """
        site:
          title: "Complete Site"
          description: "A complete test site"
          url: "https://complete.com"
          language: "en"
          author:
            name: "Jane Doe"
            email: "jane@complete.com"
        
        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          staticDirectory: "static"
          templatesDirectory: "templates"
        
        server:
          port: 3000
          liveReload: false
        
        blog:
          postsPerPage: 5
          generateArchive: true
          generateCategories: true
          generateTags: true
        
        features:
          sitemap: true
          rss: true
          searchIndex: true
          minify: false
        """
        
        let config = try HirundoConfig.parse(from: yamlString)
        
        // Test site config
        XCTAssertEqual(config.site.title, "Complete Site")
        XCTAssertEqual(config.site.description, "A complete test site")
        XCTAssertEqual(config.site.url, "https://complete.com")
        XCTAssertEqual(config.site.language, "en")
        XCTAssertEqual(config.site.author?.name, "Jane Doe")
        XCTAssertEqual(config.site.author?.email, "jane@complete.com")
        
        // Test build config
        XCTAssertEqual(config.build.contentDirectory, "content")
        XCTAssertEqual(config.build.outputDirectory, "_site")
        XCTAssertEqual(config.build.staticDirectory, "static")
        XCTAssertEqual(config.build.templatesDirectory, "templates")
        
        // Test server config
        XCTAssertEqual(config.server.port, 3000)
        XCTAssertFalse(config.server.liveReload)
        
        // Test blog config
        XCTAssertEqual(config.blog.postsPerPage, 5)
        XCTAssertTrue(config.blog.generateArchive)
        XCTAssertTrue(config.blog.generateCategories)
        XCTAssertTrue(config.blog.generateTags)
        
        // Test features config
        XCTAssertTrue(config.features.sitemap)
        XCTAssertTrue(config.features.rss)
        XCTAssertTrue(config.features.searchIndex)
        XCTAssertFalse(config.features.minify)
    }
    
    func testConfigFileLoading() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("test-config.yaml")
        
        let yamlContent = """
        site:
          title: "File Test Site"
          url: "https://filetest.com"
        """
        
        try yamlContent.write(to: configFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: configFile) }
        
        let config = try HirundoConfig.load(from: configFile)
        
        XCTAssertEqual(config.site.title, "File Test Site")
        XCTAssertEqual(config.site.url, "https://filetest.com")
    }
    
    func testDefaultValues() throws {
        let minimalYaml = """
        site:
          title: "Minimal Site"
          url: "https://test.com"
        """
        
        let config = try HirundoConfig.parse(from: minimalYaml)
        
        // Test default server values
        XCTAssertEqual(config.server.port, 8080)
        XCTAssertTrue(config.server.liveReload)
    }
    
    func testCustomServerValues() throws {
        let yamlWithServer = """
        site:
          title: "Test Site"
          url: "https://test.com"
        
        server:
          port: 3000
          liveReload: false
        """
        
        let config = try HirundoConfig.parse(from: yamlWithServer)
        
        // Test custom server values
        XCTAssertEqual(config.server.port, 3000)
        XCTAssertFalse(config.server.liveReload)
    }
    
    func testInvalidConfigError() throws {
        let invalidYaml = """
        site:
          title: "Test Site"
          # Missing required url field
        """
        
        do {
            let _ = try HirundoConfig.parse(from: invalidYaml)
            XCTFail("Expected error for missing required field")
        } catch {
            // Should fail for missing required field
            XCTAssertTrue(true)
        }
    }
    
    func testMissingRequiredFieldError() throws {
        let yamlWithoutSite = """
        server:
          port: 8080
        """
        
        do {
            let _ = try HirundoConfig.parse(from: yamlWithoutSite)
            XCTFail("Expected error for missing site field")
        } catch {
            // Should fail for missing site field
            XCTAssertTrue(true)
        }
    }
}

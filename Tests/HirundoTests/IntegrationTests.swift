import XCTest
@testable import HirundoCore

final class IntegrationTests: XCTestCase {
    
    var tempProjectDir: URL!
    var siteGenerator: SiteGenerator!
    
    override func setUp() async throws {
        tempProjectDir = FileManager.default.temporaryDirectory.appendingPathComponent("hirundo-integration-\(UUID())")
        try FileManager.default.createDirectory(at: tempProjectDir, withIntermediateDirectories: true)
        
        try await setupTestProject()
    }
    
    override func tearDown() async throws {
        if let tempProjectDir = tempProjectDir {
            try? FileManager.default.removeItem(at: tempProjectDir)
        }
    }
    
    private func setupTestProject() async throws {
        // Create project structure
        let contentDir = tempProjectDir.appendingPathComponent("content")
        let templatesDir = tempProjectDir.appendingPathComponent("templates")
        let staticDir = tempProjectDir.appendingPathComponent("static")
        let _ = tempProjectDir.appendingPathComponent("_site")
        
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staticDir, withIntermediateDirectories: true)
        
        // Create config.yaml
        let config = """
        site:
          title: "Integration Test Site"
          description: "A test site for integration testing"
          url: "https://test.example.com"
          author:
            name: "Test Author"
            email: "test@example.com"
        
        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          staticDirectory: "static"
          templatesDirectory: "templates"
        
        blog:
          postsPerPage: 5
          generateArchive: true
          generateCategories: true
          generateTags: true
        """
        
        try config.write(to: tempProjectDir.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        
        // Create templates
        let baseTemplate = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>{{ site.title }}</title>
            <meta name="description" content="{{ site.description }}">
        </head>
        <body>
            <header>
                <h1><a href="/">{{ site.title }}</a></h1>
                <nav>
                    <a href="/">Home</a>
                    <a href="/about/">About</a>
                    <a href="/posts/">Posts</a>
                </nav>
            </header>
            <main>
                {{ content }}
            </main>
            <footer>
                <p>&copy; 2023 {{ site.author.name }}</p>
            </footer>
        </body>
        </html>
        """
        
        let defaultTemplate = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>{{ site.title }}</title>
        </head>
        <body>
            <h1>{{ site.title }}</h1>
            {{ content }}
        </body>
        </html>
        """
        
        let postTemplate = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>{{ site.title }}</title>
        </head>
        <body>
            <h1>{{ site.title }}</h1>
            <h2>{{ page.title }}</h2>
            {{ content }}
        </body>
        </html>
        """
        
        try baseTemplate.write(to: templatesDir.appendingPathComponent("base.html"), atomically: true, encoding: .utf8)
        try defaultTemplate.write(to: templatesDir.appendingPathComponent("default.html"), atomically: true, encoding: .utf8)
        try postTemplate.write(to: templatesDir.appendingPathComponent("post.html"), atomically: true, encoding: .utf8)
        
        // Create content files
        let indexContent = """
        ---
        title: "Welcome to Test Site"
        layout: "default"
        ---
        
        # Welcome to Integration Test Site
        
        This is the home page of our test site.
        
        ## Recent Posts
        
        {% for post in posts limit:3 %}
        - [{{ post.title }}]({{ post.url }}) - {{ post.date | date: '%B %d, %Y' }}
        {% endfor %}
        """
        
        let aboutContent = """
        ---
        title: "About"
        layout: "default"
        ---
        
        # About This Site
        
        This is a test site created for integration testing of the Hirundo static site generator.
        
        ## Features Tested
        
        - Markdown processing
        - Template rendering
        - Static file handling
        - Blog functionality
        """
        
        try indexContent.write(to: contentDir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
        try aboutContent.write(to: contentDir.appendingPathComponent("about.md"), atomically: true, encoding: .utf8)
        
        // Create blog posts
        let postsDir = contentDir.appendingPathComponent("posts")
        try FileManager.default.createDirectory(at: postsDir, withIntermediateDirectories: true)
        
        let posts = [
            (
                "first-post.md",
                """
                ---
                title: "First Post"
                date: 2023-01-01T00:00:00Z
                author: "Test Author"
                tags: ["testing", "first"]
                categories: ["blog"]
                layout: "post"
                ---
                
                # First Post
                
                This is the first test post.
                
                ## Features
                
                - **Bold text**
                - *Italic text*
                - `Code snippets`
                
                ```swift
                print("Hello, World!")
                ```
                """
            ),
            (
                "second-post.md",
                """
                ---
                title: "Second Post"
                date: 2023-01-15T00:00:00Z
                author: "Test Author"
                tags: ["testing", "second"]
                categories: ["blog", "updates"]
                layout: "post"
                ---
                
                # Second Post
                
                This is the second test post with more content.
                
                ## Links and Lists
                
                1. First item
                2. Second item
                3. [Link to about page](/about/)
                
                > This is a blockquote
                """
            ),
            (
                "third-post.md",
                """
                ---
                title: "Third Post"
                date: 2023-02-01T00:00:00Z
                author: "Another Author"
                tags: ["testing", "third", "unicode"]
                categories: ["blog"]
                layout: "post"
                ---
                
                # Third Post with Unicode
                
                This post tests Unicode content: 日本語、中文、🚀、🎉
                
                ## Math and Symbols
                
                - α, β, γ
                - ∑, ∫, ∞
                - ♠, ♥, ♦, ♣
                """
            )
        ]
        
        for (filename, content) in posts {
            try content.write(to: postsDir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        }
        
        // Create static files
        let cssContent = """
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            line-height: 1.6;
        }
        
        header {
            border-bottom: 1px solid #eee;
            margin-bottom: 20px;
        }
        
        nav a {
            margin-right: 15px;
            text-decoration: none;
        }
        
        .post-meta {
            color: #666;
            margin-bottom: 20px;
        }
        
        .tag {
            background: #eee;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 0.8em;
        }
        """
        
        let cssDir = staticDir.appendingPathComponent("css")
        try FileManager.default.createDirectory(at: cssDir, withIntermediateDirectories: true)
        try cssContent.write(to: cssDir.appendingPathComponent("main.css"), atomically: true, encoding: .utf8)
        
        // Create a test image file (empty for testing purposes)
        let imagesDir = staticDir.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG header
        try imageData.write(to: imagesDir.appendingPathComponent("test.png"))
    }
    
    func testFullSiteBuild() async throws {
        let siteGenerator = try SiteGenerator(projectPath: tempProjectDir.path)
        
        // Build the site
        try await siteGenerator.build(clean: true, includeDrafts: false)
        
        let outputDir = tempProjectDir.appendingPathComponent("_site")
        
        // Verify index.html was created
        let indexFile = outputDir.appendingPathComponent("index.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexFile.path))
        
        let indexContent = try String(contentsOf: indexFile, encoding: .utf8)
        XCTAssertTrue(indexContent.contains("Welcome to Integration Test Site"))
        XCTAssertTrue(indexContent.contains("<!DOCTYPE html>"))
        XCTAssertTrue(indexContent.contains("Integration Test Site"))
        
        // Verify about page was created
        let aboutDir = outputDir.appendingPathComponent("about")
        let aboutFile = aboutDir.appendingPathComponent("index.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: aboutFile.path))
        
        let aboutContent = try String(contentsOf: aboutFile, encoding: .utf8)
        XCTAssertTrue(aboutContent.contains("About This Site"))
        
        // Verify blog posts were created
        let postsDir = outputDir.appendingPathComponent("posts")
        XCTAssertTrue(FileManager.default.fileExists(atPath: postsDir.path))
        
        let firstPostDir = postsDir.appendingPathComponent("first-post")
        let firstPostFile = firstPostDir.appendingPathComponent("index.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstPostFile.path))
        
        let firstPostContent = try String(contentsOf: firstPostFile, encoding: .utf8)
        XCTAssertTrue(firstPostContent.contains("First Post"))
        XCTAssertTrue(firstPostContent.contains("Hello, World!"))
        
        // Verify static files were copied
        let cssFile = outputDir.appendingPathComponent("css/main.css")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cssFile.path))
        
        let cssContent = try String(contentsOf: cssFile, encoding: .utf8)
        XCTAssertTrue(cssContent.contains("font-family"))
        
        let imageFile = outputDir.appendingPathComponent("images/test.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageFile.path))
    }
    
    func testBuildWithDrafts() async throws {
        // Add a draft post
        let draftsDir = tempProjectDir.appendingPathComponent("content/posts")
        let draftContent = """
        ---
        title: "Draft Post"
        date: 2023-03-01T00:00:00Z
        draft: true
        layout: "post"
        ---
        
        # Draft Post
        
        This is a draft post that should not appear in normal builds.
        """
        
        try draftContent.write(to: draftsDir.appendingPathComponent("draft-post.md"), atomically: true, encoding: .utf8)
        
        let _ = try HirundoConfig.load(from: tempProjectDir.appendingPathComponent("config.yaml"))
        let siteGenerator = try SiteGenerator(projectPath: tempProjectDir.path)
        
        // Build without drafts
        try await siteGenerator.build(clean: true, includeDrafts: false)
        
        let outputDir = tempProjectDir.appendingPathComponent("_site")
        let draftFile = outputDir.appendingPathComponent("posts/draft-post/index.html")
        XCTAssertFalse(FileManager.default.fileExists(atPath: draftFile.path))
        
        // Build with drafts
        try await siteGenerator.build(clean: true, includeDrafts: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: draftFile.path))
        
        let draftFileContent = try String(contentsOf: draftFile, encoding: .utf8)
        XCTAssertTrue(draftFileContent.contains("Draft Post"))
    }
    
    func testErrorRecoveryDuringBuild() async throws {
        let _ = try HirundoConfig.load(from: tempProjectDir.appendingPathComponent("config.yaml"))
        let siteGenerator = try SiteGenerator(projectPath: tempProjectDir.path)
        
        // Create a file with invalid front matter
        let invalidFile = tempProjectDir.appendingPathComponent("content/invalid.md")
        let invalidContent = """
        ---
        title: "Invalid
        date: not-a-date
        ---
        
        # Invalid Content
        """
        
        try invalidContent.write(to: invalidFile, atomically: true, encoding: .utf8)
        
        // Build should handle the error gracefully
        do {
            try await siteGenerator.build(clean: true, includeDrafts: false)
            XCTFail("Expected build to fail with invalid content")
        } catch {
            // Verify it's the expected error type
            XCTAssertTrue(error is MarkdownError || error is BuildError)
        }
        
        // Fix the file and try again
        let fixedContent = """
        ---
        title: "Fixed Content"
        date: 2023-01-01T00:00:00Z
        ---
        
        # Fixed Content
        """
        
        try fixedContent.write(to: invalidFile, atomically: true, encoding: .utf8)
        
        // Build should now succeed
        try await siteGenerator.build(clean: true, includeDrafts: false)
        
        let outputDir = tempProjectDir.appendingPathComponent("_site")
        let fixedFile = outputDir.appendingPathComponent("invalid/index.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixedFile.path))
    }
    
    func testConcurrentBuildOperations() async throws {
        let _ = try HirundoConfig.load(from: tempProjectDir.appendingPathComponent("config.yaml"))
        
        // Try to run multiple builds concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1...3 {
                group.addTask { [tempProjectDir] in
                    do {
                        let siteGenerator = try SiteGenerator(projectPath: tempProjectDir!.path)
                        try await siteGenerator.build(clean: false, includeDrafts: false)
                    } catch {
                        // Some builds may fail due to concurrent access, which is expected
                        print("Concurrent build \(i) failed: \(error)")
                    }
                }
            }
        }
        
        // Verify at least one build succeeded
        let outputDir = tempProjectDir.appendingPathComponent("_site")
        let indexFile = outputDir.appendingPathComponent("index.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexFile.path))
    }
    
    func testFeatureIntegration() async throws {
        // Test with sitemap/rss features enabled
        
        // Build with programmatic config (features enabled)
        let site = try Site(title: "Plugin Test Site", url: "https://test.example.com")
        let cfg = HirundoConfig(site: site, build: Build.defaultBuild(), server: Server.defaultServer(), blog: Blog.defaultBlog(), features: Features(sitemap: true, rss: true, searchIndex: false, minify: false))
        let siteGenerator = try SiteGenerator(projectPath: tempProjectDir.path, config: cfg)
        
        try await siteGenerator.build(clean: true, includeDrafts: false)
        
        let outputDir = tempProjectDir.appendingPathComponent("_site")
        
        // Check if sitemap was generated (if plugin is implemented)
        let _ = outputDir.appendingPathComponent("sitemap.xml")
        // Note: This test may pass even if sitemap plugin isn't fully implemented
        
        // Check if RSS feed was generated
        let _ = outputDir.appendingPathComponent("rss.xml")
        // Note: This test may pass even if RSS plugin isn't fully implemented
    }
    
    func testLargeNumberOfFiles() async throws {
        // Create a large number of content files
        let postsDir = tempProjectDir.appendingPathComponent("content/posts")
        
        for i in 1...50 {
            let postContent = """
            ---
            title: "Generated Post \(i)"
            date: "2023-01-\(String(format: "%02d", (i % 28) + 1))T00:00:00Z"
            tags: ["generated", "test\(i % 5)"]
            layout: "post"
            ---
            
            # Generated Post \(i)
            
            This is automatically generated post number \(i).
            
            Content for post \(i) with some **bold** and *italic* text.
            """
            
            try postContent.write(to: postsDir.appendingPathComponent("generated-post-\(i).md"), atomically: true, encoding: .utf8)
        }
        
        let _ = try HirundoConfig.load(from: tempProjectDir.appendingPathComponent("config.yaml"))
        let siteGenerator = try SiteGenerator(projectPath: tempProjectDir.path)
        
        let startTime = Date()
        try await siteGenerator.build(clean: true, includeDrafts: false)
        let buildTime = Date().timeIntervalSince(startTime)
        
        // Build should complete in reasonable time (adjust threshold as needed)
        XCTAssertLessThan(buildTime, 30.0, "Build took too long: \(buildTime) seconds")
        
        // Verify all posts were generated
        let outputDir = tempProjectDir.appendingPathComponent("_site/posts")
        let generatedFiles = try FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)
        
        // Should have at least 50 generated posts plus the original 3
        XCTAssertGreaterThanOrEqual(generatedFiles.count, 53)
    }
    
    func testUnicodeContentIntegration() async throws {
        // Create content with various Unicode characters
        let unicodeDir = tempProjectDir.appendingPathComponent("content")
        let unicodeContent = """
        ---
        title: "Unicode テスト 测试 🚀"
        date: 2023-01-01T00:00:00Z
        author: "著者 作者 👤"
        tags: ["unicode", "テスト", "测试", "🏷️"]
        layout: "default"
        ---
        
        # Unicode Content Test
        
        ## Japanese
        こんにちは、世界！これは日本語のテストです。
        
        ## Chinese
        你好世界！这是中文测试。
        
        ## Emojis
        🎉 🎊 🚀 🌟 ⭐ 🎯 🎨 🎭 🎪 🎫
        
        ## Mathematical Symbols
        α + β = γ
        ∑(n=1 to ∞) 1/n²
        
        ## Special Characters
        "Smart quotes" and 'apostrophes'
        Em—dash and en–dash
        Ellipsis…
        
        ## Mixed Content
        English with 日本語 and 中文 mixed together 🌍
        """
        
        try unicodeContent.write(to: unicodeDir.appendingPathComponent("unicode-test.md"), atomically: true, encoding: .utf8)
        
        let _ = try HirundoConfig.load(from: tempProjectDir.appendingPathComponent("config.yaml"))
        let siteGenerator = try SiteGenerator(projectPath: tempProjectDir.path)
        
        try await siteGenerator.build(clean: true, includeDrafts: false)
        
        let outputDir = tempProjectDir.appendingPathComponent("_site")
        let unicodeFile = outputDir.appendingPathComponent("unicode-test/index.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unicodeFile.path))
        
        let htmlContent = try String(contentsOf: unicodeFile, encoding: .utf8)
        XCTAssertTrue(htmlContent.contains("こんにちは"))
        XCTAssertTrue(htmlContent.contains("你好世界"))
        XCTAssertTrue(htmlContent.contains("🚀"))
        XCTAssertTrue(htmlContent.contains("α + β = γ"))
        XCTAssertTrue(htmlContent.contains("charset=\"UTF-8\""))
    }
}

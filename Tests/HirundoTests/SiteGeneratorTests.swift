import XCTest
@testable import HirundoCore

final class SiteGeneratorTests: XCTestCase {
    
    var tempDir: URL!
    var generator: SiteGenerator!
    
    override func setUp() {
        super.setUp()
        
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("hirundo-test-\(UUID())")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        setupTestSite()
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    private func setupTestSite() {
        let config = """
        site:
          title: "テストサイト"
          url: "https://test.example.com"
          author:
            name: "テスト太郎"
            email: "test@example.com"
        
        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          staticDirectory: "static"
          templatesDirectory: "templates"
        
        blog:
          postsPerPage: 2
          generateArchive: true
          generateCategories: true
          generateTags: true
        """
        
        let baseTemplate = """
        <!DOCTYPE html>
        <html lang="ja">
        <head>
            <meta charset="UTF-8">
            <title>{% block title %}{{ page.title }} - {{ site.title }}{% endblock %}</title>
        </head>
        <body>
            <header>
                <h1><a href="/">{{ site.title }}</a></h1>
            </header>
            <main>
                {% block content %}{% endblock %}
            </main>
            <footer>
                <p>&copy; {{ site.author.name }}</p>
            </footer>
        </body>
        </html>
        """
        
        let pageTemplate = """
        {% extends "base.html" %}
        
        {% block content %}
        <article>
            <h1>{{ page.title }}</h1>
            {{ content }}
        </article>
        {% endblock %}
        """
        
        let postTemplate = """
        {% extends "base.html" %}
        
        {% block content %}
        <article>
            <h1>{{ page.title }}</h1>
            <time>{{ page.date | date: "%Y-%m-%d" }}</time>
            {% if page.categories %}
            <div class="categories">
                {% for category in page.categories %}
                <a href="/categories/{{ category | slugify }}">{{ category }}</a>
                {% endfor %}
            </div>
            {% endif %}
            {{ content }}
        </article>
        {% endblock %}
        """
        
        let indexContent = """
        ---
        title: "ホーム"
        layout: "page"
        ---
        
        # ようこそ
        
        これはHirundoで作成されたテストサイトです。
        """
        
        let aboutContent = """
        ---
        title: "About"
        layout: "page"
        ---
        
        # このサイトについて
        
        静的サイトジェネレーターのテストです。
        """
        
        let post1Content = """
        ---
        title: "最初の投稿"
        date: 2024-01-01T12:00:00Z
        categories: [テスト, Swift]
        tags: [hirundo, ssg]
        layout: "post"
        ---
        
        # 最初の投稿
        
        これは最初のブログ投稿です。
        """
        
        let post2Content = """
        ---
        title: "二番目の投稿"
        date: 2024-01-02T12:00:00Z
        categories: [テスト]
        tags: [hirundo]
        layout: "post"
        ---
        
        # 二番目の投稿
        
        これは二番目のブログ投稿です。
        """
        
        try? config.write(to: tempDir.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        
        let templatesDir = tempDir.appendingPathComponent("templates")
        try? FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        try? baseTemplate.write(to: templatesDir.appendingPathComponent("base.html"), atomically: true, encoding: .utf8)
        try? pageTemplate.write(to: templatesDir.appendingPathComponent("page.html"), atomically: true, encoding: .utf8)
        try? pageTemplate.write(to: templatesDir.appendingPathComponent("default.html"), atomically: true, encoding: .utf8)
        try? postTemplate.write(to: templatesDir.appendingPathComponent("post.html"), atomically: true, encoding: .utf8)
        
        // Add archive template
        let archiveTemplate = """
        {% extends "base.html" %}
        
        {% block content %}
        <h1>Archive</h1>
        <ul>
        {% for post in posts %}
            <li><a href="{{ post.url }}">{{ post.title }}</a> - {{ post.date | date: "%Y-%m-%d" }}</li>
        {% endfor %}
        </ul>
        {% endblock %}
        """
        try? archiveTemplate.write(to: templatesDir.appendingPathComponent("archive.html"), atomically: true, encoding: .utf8)
        
        // Add category template
        let categoryTemplate = """
        {% extends "base.html" %}
        
        {% block content %}
        <h1>Category: {{ category }}</h1>
        <ul>
        {% for post in posts %}
            <li><a href="{{ post.url }}">{{ post.title }}</a> - {{ post.date | date: "%Y-%m-%d" }}</li>
        {% endfor %}
        </ul>
        {% endblock %}
        """
        try? categoryTemplate.write(to: templatesDir.appendingPathComponent("category.html"), atomically: true, encoding: .utf8)
        
        // Add tag template
        let tagTemplate = """
        {% extends "base.html" %}
        
        {% block content %}
        <h1>Tag: {{ tag }}</h1>
        <ul>
        {% for post in posts %}
            <li><a href="{{ post.url }}">{{ post.title }}</a> - {{ post.date | date: "%Y-%m-%d" }}</li>
        {% endfor %}
        </ul>
        {% endblock %}
        """
        try? tagTemplate.write(to: templatesDir.appendingPathComponent("tag.html"), atomically: true, encoding: .utf8)
        
        let contentDir = tempDir.appendingPathComponent("content")
        try? FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try? indexContent.write(to: contentDir.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
        try? aboutContent.write(to: contentDir.appendingPathComponent("about.md"), atomically: true, encoding: .utf8)
        
        let postsDir = contentDir.appendingPathComponent("posts")
        try? FileManager.default.createDirectory(at: postsDir, withIntermediateDirectories: true)
        try? post1Content.write(to: postsDir.appendingPathComponent("first-post.md"), atomically: true, encoding: .utf8)
        try? post2Content.write(to: postsDir.appendingPathComponent("second-post.md"), atomically: true, encoding: .utf8)
        
        let staticDir = tempDir.appendingPathComponent("static")
        let cssDir = staticDir.appendingPathComponent("css")
        try? FileManager.default.createDirectory(at: cssDir, withIntermediateDirectories: true)
        try? "body { font-family: sans-serif; }".write(
            to: cssDir.appendingPathComponent("style.css"),
            atomically: true,
            encoding: .utf8
        )
    }
    
    func testBasicSiteGeneration() async throws {
        generator = try SiteGenerator(projectPath: tempDir.path)
        
        try await generator.build()
        
        let outputDir = tempDir.appendingPathComponent("_site")
        
        // Debug: List all files in output directory recursively
        func listFiles(at url: URL, indent: String = "") {
            if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) {
                for item in contents {
                    let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    print("\(indent)\(item.lastPathComponent)\(isDir ? "/" : "")")
                    if isDir {
                        listFiles(at: item, indent: indent + "  ")
                    }
                }
            }
        }
        
        if FileManager.default.fileExists(atPath: outputDir.path) {
            print("Output directory structure:")
            listFiles(at: outputDir)
        } else {
            print("Output directory does not exist")
        }
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path), "Output directory should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("index.html").path), "index.html should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("about/index.html").path), "about/index.html should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("posts/first-post/index.html").path), "posts/first-post/index.html should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("posts/second-post/index.html").path), "posts/second-post/index.html should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("css/style.css").path), "css/style.css should exist")
    }
    
    func testPageContent() async throws {
        generator = try SiteGenerator(projectPath: tempDir.path)
        try await generator.build()
        
        let indexPath = tempDir.appendingPathComponent("_site/index.html")
        let indexContent = try String(contentsOf: indexPath, encoding: .utf8)
        
        XCTAssertTrue(indexContent.contains("<title>ホーム - テストサイト</title>"))
        XCTAssertTrue(indexContent.contains("<h1>ようこそ</h1>"))
        XCTAssertTrue(indexContent.contains("これはHirundoで作成されたテストサイトです。"))
        XCTAssertTrue(indexContent.contains("&copy; テスト太郎"))
    }
    
    func testBlogPostGeneration() async throws {
        generator = try SiteGenerator(projectPath: tempDir.path)
        try await generator.build()
        
        let postPath = tempDir.appendingPathComponent("_site/posts/first-post/index.html")
        let postContent = try String(contentsOf: postPath, encoding: .utf8)
        
        XCTAssertTrue(postContent.contains("<title>最初の投稿 - テストサイト</title>"))
        XCTAssertTrue(postContent.contains("<time>2024-01-01</time>"))
        XCTAssertTrue(postContent.contains("<a href=\"/categories/%E3%83%86%E3%82%B9%E3%83%88\">テスト</a>"))
        XCTAssertTrue(postContent.contains("<a href=\"/categories/swift\">Swift</a>"))
    }
    
    func testCategoryPageGeneration() async throws {
        generator = try SiteGenerator(projectPath: tempDir.path)
        try await generator.build()
        
        let categoryDir = tempDir.appendingPathComponent("_site/categories/%E3%83%86%E3%82%B9%E3%83%88")
        XCTAssertTrue(FileManager.default.fileExists(atPath: categoryDir.appendingPathComponent("index.html").path))
        
        let categoryContent = try String(
            contentsOf: categoryDir.appendingPathComponent("index.html"),
            encoding: .utf8
        )
        
        XCTAssertTrue(categoryContent.contains("最初の投稿"))
        XCTAssertTrue(categoryContent.contains("二番目の投稿"))
    }
    
    func testTagPageGeneration() async throws {
        generator = try SiteGenerator(projectPath: tempDir.path)
        try await generator.build()
        
        let tagDir = tempDir.appendingPathComponent("_site/tags/hirundo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tagDir.appendingPathComponent("index.html").path))
        
        let tagContent = try String(
            contentsOf: tagDir.appendingPathComponent("index.html"),
            encoding: .utf8
        )
        
        XCTAssertTrue(tagContent.contains("最初の投稿"))
        XCTAssertTrue(tagContent.contains("二番目の投稿"))
    }
    
    func testArchiveGeneration() async throws {
        generator = try SiteGenerator(projectPath: tempDir.path)
        try await generator.build()
        
        let archivePath = tempDir.appendingPathComponent("_site/archive/index.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivePath.path))
        
        let archiveContent = try String(contentsOf: archivePath, encoding: .utf8)
        
        XCTAssertTrue(archiveContent.contains("最初の投稿"))
        XCTAssertTrue(archiveContent.contains("二番目の投稿"))
        XCTAssertTrue(archiveContent.contains("2024-01-01"))
        XCTAssertTrue(archiveContent.contains("2024-01-02"))
    }
    
    func testStaticFileCopying() async throws {
        generator = try SiteGenerator(projectPath: tempDir.path)
        try await generator.build()
        
        let copiedCssPath = tempDir.appendingPathComponent("_site/css/style.css")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedCssPath.path))
        
        let cssContent = try String(contentsOf: copiedCssPath, encoding: .utf8)
        XCTAssertEqual(cssContent, "body { font-family: sans-serif; }")
    }
    
    func testIncrementalBuild() async throws {
        generator = try SiteGenerator(projectPath: tempDir.path)
        
        try await generator.build()
        
        _ = Date()
        
        try await Task.sleep(for: .milliseconds(100))
        
        let newPostContent = """
        ---
        title: "三番目の投稿"
        date: 2024-01-03T12:00:00Z
        categories: [新規]
        layout: "post"
        ---
        
        # 三番目の投稿
        
        新しく追加された投稿です。
        """
        
        let postsDir = tempDir.appendingPathComponent("content/posts")
        try newPostContent.write(
            to: postsDir.appendingPathComponent("third-post.md"),
            atomically: true,
            encoding: .utf8
        )
        
        try await generator.build()
        
        let thirdPostPath = tempDir.appendingPathComponent("_site/posts/third-post/index.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: thirdPostPath.path))
        
        let thirdPostContent = try String(contentsOf: thirdPostPath, encoding: .utf8)
        XCTAssertTrue(thirdPostContent.contains("三番目の投稿"))
        
        let newCategoryPath = tempDir.appendingPathComponent("_site/categories/%E6%96%B0%E8%A6%8F/index.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newCategoryPath.path))
    }
    
    func testCleanBuild() async throws {
        generator = try SiteGenerator(projectPath: tempDir.path)
        
        try await generator.build()
        
        let testFilePath = tempDir.appendingPathComponent("_site/test.txt")
        try "test".write(to: testFilePath, atomically: true, encoding: .utf8)
        
        try await generator.build(clean: true)
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFilePath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("_site/index.html").path))
    }
    
    func testDraftHandling() async throws {
        let draftContent = """
        ---
        title: "下書き投稿"
        date: 2024-01-04T12:00:00Z
        draft: true
        layout: "post"
        ---
        
        # 下書き投稿
        
        これは下書きです。
        """
        
        let postsDir = tempDir.appendingPathComponent("content/posts")
        try draftContent.write(
            to: postsDir.appendingPathComponent("draft-post.md"),
            atomically: true,
            encoding: .utf8
        )
        
        generator = try SiteGenerator(projectPath: tempDir.path)
        
        try await generator.build()
        
        let draftPath = tempDir.appendingPathComponent("_site/posts/draft-post/index.html")
        XCTAssertFalse(FileManager.default.fileExists(atPath: draftPath.path))
        
        try await generator.build(includeDrafts: true)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: draftPath.path))
    }
    
    func testErrorHandling() async throws {
        let invalidContent = """
        ---
        title: "無効な投稿"
        date: "invalid-date"
        layout: "nonexistent"
        ---
        
        # エラーテスト
        """
        
        let postsDir = tempDir.appendingPathComponent("content/posts")
        try invalidContent.write(
            to: postsDir.appendingPathComponent("invalid-post.md"),
            atomically: true,
            encoding: .utf8
        )
        
        generator = try SiteGenerator(projectPath: tempDir.path)
        
        // The build should throw an error for invalid content
        do {
            try await generator.build()
            XCTFail("Expected error to be thrown for invalid content")
        } catch {
            // Any error is acceptable here - could be template error, date parsing error, etc.
            // The important thing is that invalid content causes an error
            print("Build correctly failed with error: \(error)")
        }
    }
}
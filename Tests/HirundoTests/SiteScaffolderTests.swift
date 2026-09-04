import XCTest
@testable import HirundoCore

final class SiteScaffolderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-scaffold-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testScaffold_whenDestinationEmpty_createsEssentialFiles() throws {
        let dest = tempDir.appendingPathComponent("my-site")
        let result = try SiteScaffolder().scaffold(
            at: dest,
            options: SiteScaffoldOptions(title: "My Hirundo Site", includeBlog: false)
        )

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("config.yaml").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("content/index.md").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("content/about.md").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("templates/base.html").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("templates/default.html").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("static/css/style.css").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent(".gitignore").path))
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("templates/post.html").path))
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("content/posts").path))
        XCTAssertTrue(result.createdRelativePaths.contains("config.yaml"))
    }

    func testScaffold_whenDefaultOptions_writesParseableConfig() throws {
        let dest = tempDir.appendingPathComponent("site")
        _ = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())
        let config = try HirundoConfig.load(from: dest.appendingPathComponent("config.yaml"))
        XCTAssertEqual(config.site.title, "My Hirundo Site")
        XCTAssertEqual(config.site.url, "https://example.com")
        XCTAssertEqual(config.site.language, "en-US")
        XCTAssertEqual(config.build.contentDirectory, "content")
        XCTAssertEqual(config.server.port, 8080)
        XCTAssertTrue(config.features.sitemap)
        XCTAssertFalse(config.features.rss)
        XCTAssertFalse(config.features.minify)
        XCTAssertFalse(config.blog.generateArchive)
        XCTAssertFalse(config.blog.generateCategories)
        XCTAssertFalse(config.blog.generateTags)
    }

    func testScaffold_whenBlogEnabled_createsPostTemplateAndSamplePost() throws {
        let dest = tempDir.appendingPathComponent("blog")
        _ = try SiteScaffolder().scaffold(
            at: dest,
            options: SiteScaffoldOptions(includeBlog: true)
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("templates/post.html").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("content/posts/hello-world.md").path))
        let config = try HirundoConfig.load(from: dest.appendingPathComponent("config.yaml"))
        XCTAssertTrue(config.features.rss)
        XCTAssertTrue(config.blog.generateArchive)
        XCTAssertTrue(config.blog.generateCategories)
        XCTAssertTrue(config.blog.generateTags)
        let base = try String(contentsOf: dest.appendingPathComponent("templates/base.html"), encoding: .utf8)
        XCTAssertTrue(base.contains("/archive/"))
    }

    func testScaffold_whenDestinationHasOnlyGit_succeedsWithoutForce() throws {
        let dest = tempDir.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: dest.appendingPathComponent(".git"), withIntermediateDirectories: true)
        _ = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("config.yaml").path))
    }

    func testScaffold_whenDestinationNotEmpty_throwsWithoutForce() throws {
        let dest = tempDir.appendingPathComponent("full")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try "keep".write(to: dest.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(
            try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())
        ) { error in
            guard case ScaffoldError.destinationNotEmpty = error else {
                return XCTFail("expected destinationNotEmpty, got \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("notes.txt").path))
    }

    func testScaffold_whenForce_overwritesOwnedFilesAndKeepsOthers() throws {
        let dest = tempDir.appendingPathComponent("full")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try "keep".write(to: dest.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "old".write(to: dest.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        _ = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions(title: "Forced", force: true))
        let yaml = try String(contentsOf: dest.appendingPathComponent("config.yaml"), encoding: .utf8)
        XCTAssertTrue(yaml.contains("Forced"))
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("notes.txt"), encoding: .utf8), "keep")
    }

    func testScaffold_whenTitleEmpty_throwsInvalidTitle() {
        let dest = tempDir.appendingPathComponent("t")
        XCTAssertThrowsError(
            try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions(title: "   "))
        ) { error in
            guard case ScaffoldError.invalidTitle = error else {
                return XCTFail("expected invalidTitle, got \(error)")
            }
        }
    }

    func testScaffold_whenTitleContainsQuotes_writesValidYAML() throws {
        let dest = tempDir.appendingPathComponent("q")
        _ = try SiteScaffolder().scaffold(
            at: dest,
            options: SiteScaffoldOptions(title: #"Alice's "Blog""#)
        )
        let config = try HirundoConfig.load(from: dest.appendingPathComponent("config.yaml"))
        XCTAssertEqual(config.site.title, #"Alice's "Blog""#)
    }

    func testScaffold_whenBlogEnabled_siteGeneratorBuildSucceeds() async throws {
        let dest = tempDir.appendingPathComponent("built")
        _ = try SiteScaffolder().scaffold(
            at: dest,
            options: SiteScaffoldOptions(title: "Built Site", includeBlog: true)
        )
        let generator = try SiteGenerator(projectPath: dest.path)
        try await generator.build(clean: true)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("_site/index.html").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("_site/about/index.html").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("_site/posts/hello-world/index.html").path))
    }

    func testScaffold_whenExistingGitignoreWithoutForce_preservesContentAndAddsSiteIgnore() throws {
        let dest = tempDir.appendingPathComponent("repo")
        let fm = FileManager.default
        try fm.createDirectory(at: dest.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let gitignore = dest.appendingPathComponent(".gitignore")
        try "*.log\n".write(to: gitignore, atomically: true, encoding: .utf8)

        _ = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())

        let contents = try String(contentsOf: gitignore, encoding: .utf8)
        XCTAssertTrue(contents.contains("*.log"))
        XCTAssertTrue(contents.contains("_site/"))
    }

    func testScaffold_whenTitleContainsNewline_throwsInvalidTitle() {
        let dest = tempDir.appendingPathComponent("nl")
        XCTAssertThrowsError(
            try SiteScaffolder().scaffold(
                at: dest,
                options: SiteScaffoldOptions(title: "Foo\nBar")
            )
        ) { error in
            guard case ScaffoldError.invalidTitle = error else {
                return XCTFail("expected invalidTitle, got \(error)")
            }
        }
    }

    func testScaffold_whenBlogDisabled_buildDoesNotWriteArchive() async throws {
        let dest = tempDir.appendingPathComponent("noblog")
        _ = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())
        let generator = try SiteGenerator(projectPath: dest.path)
        try await generator.build(clean: true)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("_site/archive").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("_site/categories").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("_site/tags").path))
    }
}

final class POSIXShellQuotingTests: XCTestCase {
    func testPosixShellQuoted_whenPathContainsSpacesAndQuotes_escapesForSingleQuotes() {
        XCTAssertEqual("my-site".posixShellQuoted, "'my-site'")
        XCTAssertEqual("My Site".posixShellQuoted, "'My Site'")
        XCTAssertEqual("it's".posixShellQuoted, "'it'\\''s'")
    }
}

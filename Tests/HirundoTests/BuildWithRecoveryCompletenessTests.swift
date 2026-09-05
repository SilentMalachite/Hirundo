import XCTest
@testable import HirundoCore

/// `buildWithRecovery` is not a reduced build — it is `build` with per-item error recovery.
///
/// This matters beyond `hirundo build --continue-on-error`: `hirundo serve` uses this path for
/// its initial build *and* every rebuild, so anything missing here is missing from the whole
/// development experience.
final class BuildWithRecoveryCompletenessTests: XCTestCase {
    private var tempDirectory: URL!
    private var projectPath: String!
    private var outputURL: URL!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-recovery-completeness-\(UUID().uuidString)")
        projectPath = tempDirectory.path
        outputURL = tempDirectory.appendingPathComponent("_site")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let config = """
        site:
          title: "Recovery Site"
          url: "https://example.com"

        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          templatesDirectory: "templates"
          staticDirectory: "static"

        blog:
          generateArchive: true
          generateCategories: true
          generateTags: true

        features:
          sitemap: true
          rss: true
          searchIndex: true
        """
        try write(config, to: "config.yaml")

        let template = """
        <!DOCTYPE html>
        <html><head><title>{{ page.title }}</title></head><body>{{ content }}</body></html>
        """
        try write(template, to: "templates/default.html")
        try write(template, to: "templates/post.html")

        try write("---\ntitle: Home\n---\n# Home\n", to: "content/index.md")
        try write("""
        ---
        title: First Post
        date: 2024-01-01
        categories: ["swift"]
        tags: ["ssg"]
        ---
        # First Post

        Hello.
        """, to: "content/posts/first-post.md")

        try write("body { color: red; }\n", to: "static/css/style.css")
    }

    override func tearDown() async throws {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    // MARK: - Tests

    func testRecoveryBuildCopiesStaticAssets() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)

        let result = try await generator.buildWithRecovery()

        XCTAssertTrue(result.success, "Build reported failures: \(result.errors)")
        XCTAssertTrue(exists("css/style.css"), "static/ was never copied into the output")
    }

    func testRecoveryBuildGeneratesBlogArchivePages() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)

        let result = try await generator.buildWithRecovery()

        XCTAssertTrue(result.success, "Build reported failures: \(result.errors)")
        XCTAssertTrue(exists("archive/index.html"))
        XCTAssertTrue(exists("categories/index.html"))
        XCTAssertTrue(exists("tags/index.html"))
    }

    func testRecoveryBuildHonorsFeatureFlags() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)

        let result = try await generator.buildWithRecovery()

        XCTAssertTrue(result.success, "Build reported failures: \(result.errors)")
        XCTAssertTrue(exists("sitemap.xml"))
        XCTAssertTrue(exists("rss.xml"))
        XCTAssertTrue(exists("search-index.json"))
    }

    func testRecoveryBuildReportsAFinalizationFailureAndKeepsGoing() async throws {
        // A directory where the sitemap wants to write a file: the write fails, but it is one
        // step out of several and must neither abort the build nor be reported as success.
        try FileManager.default.createDirectory(
            at: outputURL.appendingPathComponent("sitemap.xml"),
            withIntermediateDirectories: true
        )
        let generator = try SiteGenerator(projectPath: projectPath)

        let result = try await generator.buildWithRecovery(clean: false)

        XCTAssertFalse(result.success, "A failed finalization step must not be reported as success")
        XCTAssertEqual(result.failCount, 1)
        XCTAssertEqual(result.errors.first?.stage, .writing)
        XCTAssertTrue(exists("rss.xml"), "Steps after the failing one must still run")
    }

    // MARK: - Helpers

    private func write(_ contents: String, to relativePath: String) throws {
        let url = tempDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exists(_ relativePath: String) -> Bool {
        return FileManager.default.fileExists(atPath: outputURL.appendingPathComponent(relativePath).path)
    }
}

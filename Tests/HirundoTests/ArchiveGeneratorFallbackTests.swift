import XCTest
@testable import HirundoCore

/// The `categories/index.html` and `tags/index.html` pages a site gets when it has no
/// `categories.html` or `tags.html` template — which `hirundo init` never writes, so that is
/// every site until an author writes them.
final class ArchiveGeneratorFallbackTests: XCTestCase {

    private var tempDir: URL!
    private var generator: ArchiveGenerator!

    override func setUp() {
        super.setUp()
        tempDir = FileSystemHelper.createTempDirectory()
        let config = try! HirundoConfig.parse(from: TestFixtures.sampleYAML)
        let renderer = SiteTemplateRenderer(
            templatesDirectory: tempDir.appendingPathComponent("templates").path,
            config: config
        )
        generator = ArchiveGenerator(
            fileManager: SiteFileManager(config: config, projectPath: tempDir.path),
            templateRenderer: renderer,
            config: config,
            templateEngine: renderer.templateEngine
        )
    }

    override func tearDown() {
        FileSystemHelper.cleanup(tempDir)
        tempDir = nil
        generator = nil
        super.tearDown()
    }

    private func indexContext(
        key: String,
        entries: [[String: Any]],
        siteTitle: String = "Site",
        pageTitle: String
    ) -> [String: Any] {
        return [
            "site": ["title": siteTitle, "language": "en"],
            key: entries,
            "page": ["title": pageTitle],
        ]
    }

    func testACategoryNameContainingATagIsEscapedInTheCategoriesIndex() {
        let html = generator.generateDefaultCategoriesHTML(
            context: indexContext(
                key: "categories",
                entries: [["name": "<iframe src=//example.invalid>", "url": "/categories/x/"]],
                pageTitle: "Categories"
            )
        )
        XCTAssertFalse(html.contains("<iframe"))
        XCTAssertTrue(html.contains("&lt;iframe src=//example.invalid&gt;"))
    }

    func testATagNameContainingATagIsEscapedInTheTagsIndex() {
        let html = generator.generateDefaultTagsHTML(
            context: indexContext(
                key: "tags",
                entries: [["name": "<b>bold</b>", "url": "/tags/x/"]],
                pageTitle: "Tags"
            )
        )
        XCTAssertFalse(html.contains("<b>bold</b>"))
        XCTAssertTrue(html.contains("&lt;b&gt;bold&lt;/b&gt;"))
    }

    func testACategoryURLIsEscapedAsAnAttributeValue() {
        let html = generator.generateDefaultCategoriesHTML(
            context: indexContext(
                key: "categories",
                entries: [["name": "x", "url": "/categories/a\" onmouseover=\"alert(1)/"]],
                pageTitle: "Categories"
            )
        )
        XCTAssertFalse(html.contains("onmouseover=\"alert(1)"))
        XCTAssertTrue(html.contains("href=\"/categories/a&quot; onmouseover=&quot;alert(1)/\""))
    }

    func testASiteTitleContainingMarkupIsEscapedInTheCategoriesIndexTitle() {
        let html = generator.generateDefaultCategoriesHTML(
            context: indexContext(
                key: "categories",
                entries: [],
                siteTitle: "</title><script>alert(1)</script>",
                pageTitle: "Categories"
            )
        )
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;/title&gt;&lt;script&gt;"))
    }

    func testAnOrdinaryURLIsNotReplacedByAFragment() {
        // Pins the decision not to put `sanitizeURL` on this path; see
        // `DefaultHTMLGeneratorTests.testAnOrdinaryURLIsNotReplacedByAFragment`.
        let html = generator.generateDefaultTagsHTML(
            context: indexContext(
                key: "tags",
                entries: [["name": "x", "url": "/tags/my tag/"]],
                pageTitle: "Tags"
            )
        )
        XCTAssertTrue(html.contains("href=\"/tags/my tag/\""))
        XCTAssertFalse(html.contains("href=\"#\""))
    }

    func testAnInvalidContextStillReturnsTheFixedErrorDocument() {
        let html = generator.generateDefaultTagsHTML(context: ["site": ["title": "Site"]])
        XCTAssertEqual(html, "<html><body><h1>Error: Invalid context</h1></body></html>")
    }
}

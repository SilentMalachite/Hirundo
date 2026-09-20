import XCTest
@testable import HirundoCore

/// The archive, category and tag pages every site made with `hirundo init --blog` actually gets,
/// because `hirundo init` never scaffolds `archive.html`, `category.html` or `tag.html`. Nothing
/// downstream sanitizes this output — `HTMLSanitizer` sits inside `HTMLRenderer`, not here — so
/// the escaping in the generator is the whole of the defence.
final class DefaultHTMLGeneratorTests: XCTestCase {

    private let generator = DefaultHTMLGenerator()

    private func archiveContext(
        siteTitle: String = "Site",
        language: String = "en",
        posts: [[String: Any]] = []
    ) -> [String: Any] {
        return [
            "site": ["title": siteTitle, "language": language],
            "posts": posts,
        ]
    }

    // MARK: - Values from a post's front matter

    func testAPostTitleContainingATagIsEscapedInTheArchiveList() {
        let html = generator.generateArchiveHTML(
            context: archiveContext(
                posts: [["title": "<iframe src=//example.invalid>", "url": "/posts/a/"]]
            )
        )
        XCTAssertFalse(html.contains("<iframe"))
        XCTAssertTrue(html.contains("&lt;iframe src=//example.invalid&gt;"))
    }

    func testAPostURLContainingAQuoteCannotEscapeTheHrefAttribute() {
        // A post's URL is derived from its file name, and a macOS file name may contain a quote.
        // `MarkdownValidator` never sees file names, so nothing upstream catches this.
        let html = generator.generateArchiveHTML(
            context: archiveContext(
                posts: [["title": "Post", "url": "/posts/a\" onmouseover=\"alert(1)/"]]
            )
        )
        XCTAssertFalse(html.contains("onmouseover=\"alert(1)"))
        XCTAssertTrue(html.contains("href=\"/posts/a&quot; onmouseover=&quot;alert(1)/\""))
    }

    func testACategoryNameIsEscapedInBothTheTitleAndTheHeading() {
        let html = generator.generateCategoryHTML(
            context: [
                "site": ["title": "Site", "language": "en"],
                "posts": [[String: Any]](),
                "category": "<b>bold</b>",
            ]
        )
        XCTAssertFalse(html.contains("<b>bold</b>"))
        XCTAssertEqual(
            html.components(separatedBy: "&lt;b&gt;bold&lt;/b&gt;").count - 1, 2,
            "the category name appears in both <title> and <h1>"
        )
    }

    func testATagNameIsEscapedInBothTheTitleAndTheHeading() {
        let html = generator.generateTagHTML(
            context: [
                "site": ["title": "Site", "language": "en"],
                "posts": [[String: Any]](),
                "tag": "<b>bold</b>",
            ]
        )
        XCTAssertFalse(html.contains("<b>bold</b>"))
        XCTAssertEqual(html.components(separatedBy: "&lt;b&gt;bold&lt;/b&gt;").count - 1, 2)
    }

    // MARK: - Values from config.yaml

    func testASiteTitleContainingATagIsEscapedInTheTitleElement() {
        // `site.title` is checked for length and nothing else, so markup in it reaches here.
        let html = generator.generateArchiveHTML(
            context: archiveContext(siteTitle: "</title><script>alert(1)</script>")
        )
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;/title&gt;&lt;script&gt;"))
    }

    func testAnAmpersandInASiteTitleIsEscapedExactlyOnce() {
        let html = generator.generateArchiveHTML(context: archiveContext(siteTitle: "Tom & Jerry"))
        XCTAssertTrue(html.contains("<title>Archive - Tom &amp; Jerry</title>"))
        XCTAssertFalse(html.contains("&amp;amp;"))
    }

    func testALanguageContainingAQuoteCannotEscapeTheLangAttribute() {
        // `config.yaml`'s `site.language` is validated against a BCP 47 shape, so this cannot
        // come from a configuration file today. These are `public` methods taking an untyped
        // `[String: Any]`, though, so the type cannot assume where its context was built.
        let html = generator.generateArchiveHTML(
            context: archiveContext(language: "en\" onload=\"alert(1)")
        )
        XCTAssertFalse(html.contains("onload=\"alert(1)"))
        XCTAssertTrue(html.contains("<html lang=\"en&quot; onload=&quot;alert(1)\">"))
    }

    // MARK: - Unchanged behaviour

    func testAMissingTitleStillFallsBackToUntitled() {
        let html = generator.generateArchiveHTML(
            context: archiveContext(posts: [["url": "/posts/a/"]])
        )
        XCTAssertTrue(html.contains("<li><a href=\"/posts/a/\">Untitled</a></li>"))
    }

    func testAnInvalidContextStillReturnsTheFixedErrorDocument() {
        let html = generator.generateCategoryHTML(context: ["site": ["title": "Site"]])
        XCTAssertEqual(html, "<html><body><h1>Error: Invalid context</h1></body></html>")
    }

    func testAnOrdinaryURLIsNotReplacedByAFragment() {
        // Deliberately *not* run through `sanitizeURL`: it returns "#" for anything
        // `URLComponents` cannot parse, and a project path containing a space would turn every
        // link on the page into a fragment. The danger here is breaking out of the attribute,
        // which escaping closes, not an unwanted scheme.
        let html = generator.generateArchiveHTML(
            context: archiveContext(posts: [["title": "Post", "url": "/posts/my post/"]])
        )
        XCTAssertTrue(html.contains("href=\"/posts/my post/\""))
        XCTAssertFalse(html.contains("href=\"#\""))
    }
}

import XCTest
import Markdown
@testable import HirundoCore

/// The renderer builds every tag itself from the Markdown tree, so what matters is whether the
/// values it interpolates can leave the attribute they are interpolated into.
final class HTMLRendererTests: XCTestCase {

    private let renderer = HTMLRenderer()

    private func render(_ markdown: String) -> String {
        renderer.render(Document(parsing: markdown))
    }

    // MARK: - Code block language

    func testCodeBlockLanguageIsRenderedAsALanguageClass() {
        let html = render("```swift\nlet x = 1\n```")

        XCTAssertTrue(html.contains("class=\"language-swift\""), html)
    }

    func testCodeBlockLanguageContainingAQuoteCannotEscapeTheClassAttribute() {
        // The fence info string is author-controlled. Unescaped it produced
        // `<code class="language-foo"onmouseover="alert(1)">`, and the sanitizer's event-handler
        // pattern requires whitespace before `on`, so nothing downstream caught it.
        let html = render("```foo\"onmouseover=\"alert(1)\nx\n```")

        XCTAssertFalse(html.contains("onmouseover=\"alert(1)\""), html)
        XCTAssertTrue(html.contains("&quot;onmouseover=&quot;"), html)
    }

    func testCodeBlockBodyIsEscaped() {
        let html = render("```\n<script>alert(1)</script>\n```")

        XCTAssertFalse(html.contains("<script>"), html)
        XCTAssertTrue(html.contains("&lt;script&gt;"), html)
    }

    // MARK: - Link and image attributes

    func testLinkDestinationContainingAQuoteCannotEscapeTheHrefAttribute() {
        let html = render("[click](https://example.com/\"onmouseover=\"alert(1))")

        XCTAssertFalse(html.contains("onmouseover=\"alert(1)\""), html)
    }

    func testAJavaScriptURLBecomesAFragment() {
        let html = render("[click](javascript:alert(1))")

        XCTAssertTrue(html.contains("href=\"#\""), html)
        XCTAssertFalse(html.contains("javascript:"), html)
    }

    func testAnAmpersandInATitleIsEscaped() {
        let html = render("[click](https://example.com/ \"Tom & Jerry\")")

        XCTAssertTrue(html.contains("title=\"Tom &amp; Jerry\""), html)
    }

    func testAnAmpersandInALinkDestinationIsEscaped() {
        let html = render("[click](https://example.com/?a=1&b=2)")

        XCTAssertTrue(html.contains("href=\"https://example.com/?a=1&amp;b=2\""), html)
    }

    // MARK: - Raw HTML

    func testRawHTMLInMarkdownIsDropped() {
        // This, not the sanitizer's regexes, is why the XSS tests pass: the renderer has no case
        // for HTMLBlock or InlineHTML, and both are leaves, so they render to nothing.
        let html = render("<iframe src=\"https://evil.example\"></iframe>\n\nplain text\n")

        XCTAssertFalse(html.contains("<iframe"), html)
        XCTAssertTrue(html.contains("plain text"), html)
    }
}

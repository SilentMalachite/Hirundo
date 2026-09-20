import XCTest
@testable import HirundoCore

/// Pins what this pass does *and* what it does not, so nobody mistakes it for a sanitizer that
/// can be pointed at untrusted HTML.
final class HTMLSanitizerTests: XCTestCase {

    private let sanitizer = HTMLSanitizer()

    func testScriptTagsAndTheirContentsAreRemoved() {
        let html = sanitizer.sanitizeHTML("<p>a</p><script>alert(1)</script><p>b</p>")

        XCTAssertEqual(html, "<p>a</p><p>b</p>")
    }

    func testStyleAndMetaTagsAreRemoved() {
        XCTAssertEqual(sanitizer.sanitizeHTML("<style>body{}</style>x"), "x")
        XCTAssertEqual(sanitizer.sanitizeHTML("<meta http-equiv=\"refresh\" content=\"0\">x"), "x")
    }

    func testEventHandlersAreRemoved() {
        let html = sanitizer.sanitizeHTML("<p onclick=\"alert(1)\">a</p>")

        XCTAssertEqual(html, "<p>a</p>")
    }

    func testDoesNotRemoveAHandlerThatButtsAgainstThePrecedingQuote() {
        // The shape an attribute-escaping bug produces. This pass once caught it, by accepting
        // a quote as the delimiter before `on`. That was a mistake: the gap it covered is
        // closed where it belongs — `HTMLRenderer` escapes the attribute — and the widened
        // pattern deleted valid markup, which the test below pins. Another reason not to read
        // this type as a sanitizer for untrusted HTML.
        let html = sanitizer.sanitizeHTML("<code class=\"language-foo\"onmouseover=\"alert(1)\">x</code>")

        XCTAssertTrue(html.contains("onmouseover"), html)
    }

    func testLeavesALinkWhoseTitleStartsWithAWordBeginningWithOn() {
        // `<a href="/a" title="once = ">x</a> <a href="/b">y</a>`: with a quote accepted as the
        // delimiter, `on\w+` matched "once", `=` matched, and `["'][^"']*["']` swallowed
        // everything to the next attribute's opening quote — taking the first link's text and
        // the second link's opening tag with it.
        let html = sanitizer.sanitizeHTML(
            "<p><a href=\"/a\" title=\"once = \">x</a> <a href=\"/b\">y</a></p>"
        )

        XCTAssertTrue(html.contains(">x</a>"), html)
        XCTAssertTrue(html.contains("href=\"/b\""), html)
    }

    func testJavaScriptURLsBecomeAFragment() {
        let html = sanitizer.sanitizeHTML("<a href=\"javascript:alert(1)\">x</a>")

        XCTAssertEqual(html, "<a href=\"#\">x</a>")
    }

    func testHTTPURLsAreLeftAlone() {
        let html = sanitizer.sanitizeHTML("<a href=\"https://example.com/a?b=1\">x</a>")

        XCTAssertEqual(html, "<a href=\"https://example.com/a?b=1\">x</a>")
    }

    func testDoesNotRemoveArbitraryDangerousElements() {
        // Deliberately asserting the limitation. This pass is defence in depth over markup
        // HTMLRenderer built; it is not a filter for untrusted HTML, and an <iframe> reaching it
        // would mean the renderer had already gone wrong.
        let html = sanitizer.sanitizeHTML("<iframe src=\"https://evil.example\"></iframe>")

        XCTAssertTrue(html.contains("<iframe"), html)
    }

    // MARK: - Ranges are UTF-16, not Characters

    func testSanitizesAURLInAPageContainingAstralCharacters() {
        // `NSRegularExpression` reports UTF-16 offsets. Walking them with
        // `String.index(_:offsetBy:)` counts Characters, and one emoji is one Character and two
        // UTF-16 units — so a link far enough past an emoji was sliced short, or past the end,
        // and the build died with `String index is out of bounds`.
        let emoji = String(repeating: "\u{1F600}", count: 20)
        let html = "<p>\(emoji) <a href=\"/ok\">x</a></p>"

        let sanitized = HTMLSanitizer().sanitizeHTML(html)

        XCTAssertEqual(sanitized, html)
    }

    func testRewritesAJavaScriptURLAfterAstralCharacters() {
        let emoji = String(repeating: "\u{1F600}", count: 20)
        let sanitized = HTMLSanitizer().sanitizeHTML(
            "<p>\(emoji) <a href=\"javascript:alert(1)\">x</a></p>"
        )

        XCTAssertTrue(sanitized.contains("href=\"#\""))
        XCTAssertFalse(sanitized.contains("javascript:"))
        XCTAssertTrue(sanitized.contains(emoji), "the emoji must survive intact")
    }
}

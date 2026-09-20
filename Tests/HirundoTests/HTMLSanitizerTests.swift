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

    func testEventHandlerWithoutLeadingWhitespaceIsRemoved() {
        // The shape an attribute-escaping bug produces: the handler butts straight against the
        // closing quote of the attribute before it.
        let html = sanitizer.sanitizeHTML("<code class=\"language-foo\"onmouseover=\"alert(1)\">x</code>")

        XCTAssertFalse(html.contains("onmouseover"), html)
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
}

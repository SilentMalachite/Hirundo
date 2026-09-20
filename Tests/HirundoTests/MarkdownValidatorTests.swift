import XCTest
@testable import HirundoCore

/// What the Markdown content check does and, more usefully, what it does not.
///
/// The second half is the point. `validateDangerousPatterns` is twelve lowercased substrings, so
/// a payload that avoids all twelve reaches the renderer untouched — and the boundary is the
/// output side: `HTMLRenderer` building its own tags, `HTMLEscaping.escaped`, the `escape`
/// filter. Pinning the gaps keeps anyone from reading this type as a sanitizer, the same way
/// `HTMLSanitizerTests.testDoesNotRemoveArbitraryDangerousElements` does for that one.
final class MarkdownValidatorTests: XCTestCase {

    private let validator = MarkdownValidator()

    private func isRejected(_ content: String) -> Bool {
        do {
            try validator.validateMarkdownContent(content)
            return false
        } catch is MarkdownError {
            return true
        } catch {
            XCTFail("unexpected error type: \(type(of: error))")
            return false
        }
    }

    // MARK: - What it catches

    func testRejectsAScriptTag() {
        XCTAssertTrue(isRejected("# Title\n\n<script>alert(1)</script>\n"))
    }

    func testRejectsAJavaScriptURL() {
        XCTAssertTrue(isRejected("[click](javascript:alert(1))\n"))
    }

    func testRejectsEachOfTheNamedEventHandlers() {
        for handler in [
            "onload", "onerror", "onclick", "onmouseover",
            "onfocus", "onblur", "onchange", "onsubmit",
        ] {
            XCTAssertTrue(isRejected("<img src=x \(handler)=alert(1)>"), handler)
        }
    }

    func testMatchesRegardlessOfCase() {
        XCTAssertTrue(isRejected("<IMG SRC=x ONERROR=alert(1)>"))
    }

    func testRejectsAPatternAnywhereIncludingFrontMatter() {
        // The check runs over the whole file before the front matter is split off.
        XCTAssertTrue(isRejected("---\ntitle: \"<script>\"\n---\n\nBody.\n"))
    }

    // MARK: - What it lets through

    func testDoesNotRejectAnIframe() {
        XCTAssertFalse(isRejected("<iframe src=//example.invalid></iframe>"))
    }

    func testDoesNotRejectAnObjectOrEmbed() {
        XCTAssertFalse(isRejected("<object data=//example.invalid></object>"))
        XCTAssertFalse(isRejected("<embed src=//example.invalid>"))
    }

    func testDoesNotRejectAnEventHandlerOutsideTheTwelveNamedPatterns() {
        for handler in ["onpointerover", "ontoggle", "onwheel", "onanimationstart"] {
            XCTAssertFalse(isRejected("<img src=x \(handler)=alert(1)>"), handler)
        }
    }

    func testDoesNotRejectAnEventHandlerWithWhitespaceBeforeTheEquals() {
        XCTAssertFalse(isRejected("<img src=x onerror =alert(1)>"))
    }

    // MARK: - It is the wrong layer even for what it does catch

    func testAPatternInsideACodeBlockIsRejectedToo() {
        // The check reads the file as text, so an article *about* XSS fails the build. Widening
        // the list widens this.
        XCTAssertTrue(isRejected("```html\n<img src=x onerror=alert(1)>\n```\n"))
    }

    func testAnEscapedPatternIsStillRejected() {
        XCTAssertTrue(isRejected("Write `onclick=` to bind a handler.\n"))
    }
}

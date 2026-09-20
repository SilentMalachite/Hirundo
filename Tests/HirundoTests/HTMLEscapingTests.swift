import XCTest
@testable import HirundoCore

/// Pure string arithmetic. `HTMLEscaping` is the one place that decides how a value becomes
/// markup that means the value, so these tests pin the table itself rather than any generator
/// that uses it — including the parts it deliberately does *not* handle.
final class HTMLEscapingTests: XCTestCase {

    // MARK: - The table

    func testEscapesTheFiveCharactersThatCanChangeSurroundingMarkup() {
        XCTAssertEqual(
            HTMLEscaping.escaped("&\"'<>"),
            "&amp;&quot;&#39;&lt;&gt;"
        )
    }

    func testLeavesAStringWithoutSpecialCharactersUntouched() {
        XCTAssertEqual(HTMLEscaping.escaped("テスト site 2026"), "テスト site 2026")
    }

    func testLeavesTheEmptyStringEmpty() {
        XCTAssertEqual(HTMLEscaping.escaped(""), "")
    }

    // MARK: - Ordering

    func testReplacesTheAmpersandFirstSoEntitiesAreNotEscapedTwice() {
        // Replacing `&` last would find the ampersands of the entities the earlier passes just
        // introduced: `"` would come out as `&amp;quot;` rather than `&quot;`.
        XCTAssertEqual(HTMLEscaping.escaped("\""), "&quot;")
        XCTAssertEqual(HTMLEscaping.escaped("&lt;"), "&amp;lt;")
        XCTAssertEqual(HTMLEscaping.escaped("a & b < c"), "a &amp; b &lt; c")
    }

    func testEscapingIsNotIdempotent() {
        // Applying the table twice double-escapes, which is why already-rendered HTML — a page's
        // `content`, the `markdown` filter's output — must never be passed through it.
        XCTAssertEqual(HTMLEscaping.escaped(HTMLEscaping.escaped("&")), "&amp;amp;")
    }

    // MARK: - One table for both positions

    func testEscapesTheSameWhicheverPositionTheValueIsHeadedFor() {
        // `HTMLRenderer` used to carry two tables, one named for element text and one for
        // attribute values. They replaced the same five characters with the same five entities
        // and differed only in the order of the four passes after `&`, so their output was
        // always identical. This pins that: a future split into a weaker "text" table and a
        // stronger "attribute" one fails here rather than in whatever page first embeds a quote.
        func textOrder(_ text: String) -> String {
            return text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        }
        for sample in [
            "", "&", "<", ">", "\"", "'",
            "&amp;", "&lt;", "&quot;", "&#39;", "&apos;",
            "<a href=\"x\">'&'</a>",
            "\"onmouseover=\"alert(1)",
            "a&b<c>d\"e'f",
            "&&&", "<<<", "\"\"\"", "'''",
        ] {
            XCTAssertEqual(
                HTMLEscaping.escaped(sample), textOrder(sample),
                "the two orders disagree on \(sample.debugDescription)"
            )
        }
    }

    // MARK: - What it does not do

    func testDoesNotTouchControlCharacters() {
        // Not a gap this type promises to close: HTML tolerates them, and a value that needs
        // stripping rather than escaping is the caller's problem.
        XCTAssertEqual(HTMLEscaping.escaped("a\u{0001}b"), "a\u{0001}b")
    }

    func testDoesNotMakeAValueSafeInAnUnquotedAttribute() {
        // A space still ends an unquoted attribute value, and nothing here removes one. Every
        // call site in this module writes its attributes with quotes for exactly this reason.
        XCTAssertEqual(HTMLEscaping.escaped("x onfocus=alert(1)"), "x onfocus=alert(1)")
    }

    // MARK: - unescaped

    func testUnescapeReversesEscape() {
        for text in ["Tom & Jerry", "<b>bold</b>", "a \"quoted\" 'value'", "plain", ""] {
            XCTAssertEqual(HTMLEscaping.unescaped(HTMLEscaping.escaped(text)), text)
        }
    }

    func testUnescapeRestoresTheAmpersandLast() {
        // An author writing a literal `&lt;` gets `&amp;lt;`. Undoing `&amp;` first would turn
        // that back into `<` — the mirror of why `escaped` replaces `&` first.
        XCTAssertEqual(HTMLEscaping.unescaped("&amp;lt;"), "&lt;")
        XCTAssertEqual(HTMLEscaping.unescaped("&amp;amp;"), "&amp;")
    }

    func testUnescapeHandlesDecimalAndHexReferences() {
        XCTAssertEqual(HTMLEscaping.unescaped("it&#39;s"), "it's")
        XCTAssertEqual(HTMLEscaping.unescaped("it&#x27;s"), "it's")
        XCTAssertEqual(HTMLEscaping.unescaped("&#12486;&#12473;&#12488;"), "テスト")
    }

    func testUnescapeLeavesAnEscapedNumericReferenceAlone() {
        // `&amp;#39;` is an author writing `&#39;`, not an apostrophe.
        XCTAssertEqual(HTMLEscaping.unescaped("&amp;#39;"), "&#39;")
    }

    func testUnescapeLeavesAnUnknownEntityAlone() {
        // The limit, stated: this is not a general entity decoder.
        XCTAssertEqual(HTMLEscaping.unescaped("a&nbsp;b &copy; c"), "a&nbsp;b &copy; c")
        XCTAssertEqual(HTMLEscaping.unescaped("AT&amp;T &lt 5"), "AT&T &lt 5")
    }

    func testUnescapeLeavesAReferenceNamingNoCharacterAlone() {
        XCTAssertEqual(HTMLEscaping.unescaped("&#xD800;"), "&#xD800;")
        XCTAssertEqual(HTMLEscaping.unescaped("&#0;"), "&#0;")
        XCTAssertEqual(HTMLEscaping.unescaped("&#1114112;"), "&#1114112;")
    }

    func testUnescapeLeavesAStringWithoutEntitiesUntouched() {
        XCTAssertEqual(HTMLEscaping.unescaped("nothing to do here"), "nothing to do here")
    }
}

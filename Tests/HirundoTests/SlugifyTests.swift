import XCTest
@testable import HirundoCore

/// A slug is a name, not a URL. It used to be percent-encoded here, which put
/// `%E3%83%86%E3%82%B9%E3%83%88` on disk as a directory name — and static hosting decodes a
/// request path before it looks for a file, so every non-ASCII category and tag page 404ed.
final class SlugifyTests: XCTestCase {

    func testLowercasesAndJoinsWordsWithHyphens() {
        XCTAssertEqual("Hello World".slugify(), "hello-world")
    }

    func testKeepsNonASCIIAsItIs() {
        XCTAssertEqual("テスト".slugify(), "テスト")
        XCTAssertEqual("これは タイトル です".slugify(), "これは-タイトル-です")
    }

    func testDropsPathSeparators() {
        // A slug names one directory. A separator in it would move the page.
        XCTAssertEqual("a/b".slugify(), "ab")
        XCTAssertEqual("a\\b".slugify(), "ab")
        XCTAssertEqual("c:name".slugify(), "cname")
    }

    func testDropsURLDelimiters() {
        // `#` would cut the request at a fragment, `?` at a query, and `%` would be
        // indistinguishable from an escape `URLUtils.encodedComponent` introduced.
        XCTAssertEqual("foo#bar".slugify(), "foobar")
        XCTAssertEqual("foo?bar".slugify(), "foobar")
        XCTAssertEqual("100%pure".slugify(), "100pure")
    }

    func testDropsMarkupPunctuation() {
        XCTAssertEqual("<b>tom & jerry</b>".slugify(), "btom-jerryb")
        XCTAssertEqual("it's \"quoted\"".slugify(), "its-quoted")
    }

    func testDropsWindowsIllegalCharacters() {
        XCTAssertEqual("a*b|c".slugify(), "abc")
    }

    func testDropsALeadingDotSoTheNameIsNotHidden() {
        // A hidden directory is built and then skipped by the sitemap's enumerator.
        XCTAssertEqual(".hidden".slugify(), "hidden")
    }

    func testFallsBackToUntitledForADotAndADoubleDot() {
        // `..` reached `ArchiveGenerator` as a directory name and failed the build in
        // `OutputPathGuard`, from a category name that reads fine.
        XCTAssertEqual(".".slugify(), "untitled")
        XCTAssertEqual("..".slugify(), "untitled")
    }

    func testKeepsADotInsideAName() {
        XCTAssertEqual("v1.0 release".slugify(), "v1.0-release")
    }

    func testNeverReturnsAnEmptyString() {
        for title in ["", " ", "---", "...", "///", "&&&", "\u{0000}", "?#%"] {
            XCTAssertFalse(title.slugify().isEmpty, "empty slug for \(title.debugDescription)")
        }
    }

    func testDropsControlCharacters() {
        XCTAssertEqual("a\u{0000}b\u{0007}c".slugify(), "abc")
    }

    func testCollapsesAndTrimsHyphens() {
        XCTAssertEqual("  a   --  b  ".slugify(), "a-b")
        XCTAssertEqual("-lead and trail-".slugify(), "lead-and-trail")
    }

    func testNormalisesToNFC() {
        // Decomposed "が" (か + combining dakuten) and the precomposed form must be one name,
        // because Linux file systems compare bytes and a URL decodes to NFC.
        let decomposed = "\u{304B}\u{3099}"
        XCTAssertEqual(decomposed.slugify(), "\u{304C}")
        XCTAssertEqual(decomposed.slugify(), "が".slugify())
    }

    func testFallsBackToUntitledWhenNothingIsLeft() {
        XCTAssertEqual("".slugify(), "untitled")
        XCTAssertEqual("///".slugify(), "untitled")
        XCTAssertEqual("----".slugify(), "untitled")
    }

    func testFallsBackToUntitledWhenTruncationLeavesNothing() {
        // The fallback used to sit before the truncating branch, so this returned "" and
        // published a category at `/categories//`.
        XCTAssertEqual(String(repeating: "-", count: 60).slugify(maxLength: 40), "untitled")
        XCTAssertEqual("あ".slugify(maxLength: 2), "untitled")
    }

    func testTruncatesToAByteBudgetOnCharacterBoundaries() {
        // `maxLength` counts UTF-8 bytes, which is what NAME_MAX counts. A three-byte
        // character never gets split.
        let japanese = String(repeating: "あ", count: 20)
        let slug = japanese.slugify(maxLength: 10)
        XCTAssertEqual(slug, "あああ", "10 bytes holds three 3-byte characters")
        XCTAssertLessThanOrEqual(slug.utf8.count, 10)
    }

    func testAnASCIITitleTruncatesExactlyAsItDidBefore() {
        XCTAssertEqual(String(repeating: "a", count: 300).slugify(maxLength: 40),
                       String(repeating: "a", count: 40))
    }

    func testProducesAValidURLComponentOnceEncoded() {
        // The pair that makes the rule work: the name goes on disk, the encoding goes in the URL.
        let slug = "テスト".slugify()
        XCTAssertEqual(URLUtils.encodedComponent(slug), "%E3%83%86%E3%82%B9%E3%83%88")
        XCTAssertEqual(URLUtils.encodedComponent(slug).removingPercentEncoding, slug)
    }
}

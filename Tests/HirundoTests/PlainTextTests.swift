import XCTest
@testable import HirundoCore

/// The order in which a rendered page becomes an excerpt. Both outputs that publish a page's
/// words as data — `search-index.json` and the feed's `<description>` — got it wrong in a
/// different way, so the order lives in one place now.
final class PlainTextTests: XCTestCase {

    func testStripsTagsBeforeDecodingEntities() {
        XCTAssertEqual(
            PlainText.excerpt(fromHTML: "<p>Tom &amp; Jerry</p>", maxCharacters: 200),
            "Tom & Jerry"
        )
    }

    func testDecodingComesBeforeTheCutSoAnEntityDoesNotEatTheBudget() {
        // `&amp;` is five characters of budget for one character of text, and a cut landing
        // inside one leaves `&am` at the end of what a reader is shown.
        let html = "<p>" + String(repeating: "&amp;", count: 10) + "</p>"
        XCTAssertEqual(PlainText.excerpt(fromHTML: html, maxCharacters: 10),
                       String(repeating: "&", count: 10))
    }

    func testCutsToTheGivenNumberOfCharacters() {
        let html = "<p>" + String(repeating: "a", count: 300) + "</p>"
        XCTAssertEqual(PlainText.excerpt(fromHTML: html, maxCharacters: 200).count, 200)
    }

    func testSqueezesWhitespaceLeftBehindByTheTags() {
        XCTAssertEqual(
            PlainText.excerpt(fromHTML: "<h1>Title</h1>\n\n<p>Body</p>", maxCharacters: 200),
            "Title Body"
        )
    }

    func testDoesNotCutInsideACharacter() {
        let html = "<p>" + String(repeating: "あ", count: 10) + "</p>"
        XCTAssertEqual(PlainText.excerpt(fromHTML: html, maxCharacters: 3), "あああ")
    }
}

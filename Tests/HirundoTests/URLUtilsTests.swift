import XCTest
@testable import HirundoCore

/// The one rule the whole URL side rests on: a name on disk is the decoded form, a URL is the
/// encoded form, and the encoding happens once. These pin the encoding half.
final class URLUtilsTests: XCTestCase {

    // MARK: - encodedComponent

    func testEncodesAHashInAPathComponent() {
        // A file named `foo#bar.md` published raw makes a browser cut the request at `#`.
        XCTAssertEqual(URLUtils.encodedComponent("foo#bar"), "foo%23bar")
    }

    func testEncodesAQuestionMarkInAPathComponent() {
        XCTAssertEqual(URLUtils.encodedComponent("foo?bar"), "foo%3Fbar")
    }

    func testEncodesAPercentSoAnAlreadyEncodedStringIsNotMistakenForARawOne() {
        // The point of excluding `%`: encoding twice is visible rather than silent.
        XCTAssertEqual(URLUtils.encodedComponent("%E3%83%86"), "%25E3%2583%2586")
    }

    func testEncodesASlashInsideAComponent() {
        // A component is one name. A slash in it is data, not a separator.
        XCTAssertEqual(URLUtils.encodedComponent("a/b"), "a%2Fb")
    }

    func testEncodesNonASCIIAsUTF8() {
        XCTAssertEqual(URLUtils.encodedComponent("テスト"), "%E3%83%86%E3%82%B9%E3%83%88")
    }

    func testEncodesASpace() {
        XCTAssertEqual(URLUtils.encodedComponent("my tag"), "my%20tag")
    }

    func testEncodesAnAmpersandAndAnApostrophe() {
        // Both are legal in a path and both are refused anyway: HTML expands `&lt` without its
        // semicolon when what follows is neither alphanumeric nor `=`, and the repository spells
        // an apostrophe two ways depending on which sink a value reaches.
        XCTAssertEqual(URLUtils.encodedComponent("tom&jerry"), "tom%26jerry")
        XCTAssertEqual(URLUtils.encodedComponent("it's"), "it%27s")
    }

    func testEncodesTheRemainingSubDelimiters() {
        XCTAssertEqual(URLUtils.encodedComponent("a+b"), "a%2Bb")
        XCTAssertEqual(URLUtils.encodedComponent("a,b;c=d"), "a%2Cb%3Bc%3Dd")
        XCTAssertEqual(URLUtils.encodedComponent("take(1)"), "take%281%29")
    }

    func testKeepsTheUnreservedSetAlone() {
        XCTAssertEqual(URLUtils.encodedComponent("aZ09-._~"), "aZ09-._~")
    }

    func testLeavesAnOrdinarySlugAlone() {
        XCTAssertEqual(URLUtils.encodedComponent("hello-world"), "hello-world")
    }

    func testLeavesAFileExtensionAlone() {
        XCTAssertEqual(URLUtils.encodedPath("/css/style.css"), "/css/style.css")
    }

    // MARK: - encodedPath

    func testKeepsSeparatorsWhenEncodingAWholePath() {
        XCTAssertEqual(
            URLUtils.encodedPath("/tags/テスト/"),
            "/tags/%E3%83%86%E3%82%B9%E3%83%88/"
        )
    }

    func testKeepsALeadingAndTrailingSlash() {
        XCTAssertEqual(URLUtils.encodedPath("/"), "/")
        XCTAssertEqual(URLUtils.encodedPath("/a/b/"), "/a/b/")
    }

    func testEncodesEachComponentSeparately() {
        XCTAssertEqual(URLUtils.encodedPath("/a b/c#d/"), "/a%20b/c%23d/")
    }

    // MARK: - joinSiteURL

    func testJoinDoesNotReEncodeAnAlreadyEncodedPath() {
        XCTAssertEqual(
            URLUtils.joinSiteURL(
                base: "https://example.com", path: "/tags/%E3%83%86%E3%82%B9%E3%83%88/"
            ),
            "https://example.com/tags/%E3%83%86%E3%82%B9%E3%83%88/"
        )
    }

    func testJoinUsesOnlyTheOriginOfTheBase() {
        // The path part of `site.url` reaches the URL through `sitePathPrefix`, which
        // `siteRelativePath` prepends. Taking it from both sides would publish `/blog/blog/…`.
        XCTAssertEqual(
            URLUtils.joinSiteURL(base: "https://example.com/blog", path: "/blog/about/"),
            "https://example.com/blog/about/"
        )
    }

    func testJoinKeepsAPortInTheOrigin() {
        XCTAssertEqual(
            URLUtils.joinSiteURL(base: "http://localhost:8080/blog/", path: "/blog/about/"),
            "http://localhost:8080/blog/about/"
        )
    }

    func testJoinKeepsATrailingSlash() {
        // Regression pin: the sitemap and the feed have always published `/about/`, not `/about`.
        XCTAssertEqual(
            URLUtils.joinSiteURL(base: "https://example.com", path: "/about/"),
            "https://example.com/about/"
        )
    }

    func testJoinPublishesTheRootAsASingleSlash() {
        XCTAssertEqual(URLUtils.joinSiteURL(base: "https://example.com", path: "/"),
                       "https://example.com/")
        XCTAssertEqual(URLUtils.joinSiteURL(base: "https://example.com/", path: "/"),
                       "https://example.com/")
    }

    func testJoinAddsTheLeadingSlashAPathIsMissing() {
        XCTAssertEqual(
            URLUtils.joinSiteURL(base: "https://example.com", path: "rss.xml"),
            "https://example.com/rss.xml"
        )
    }

    // MARK: - sitePathPrefix

    func testSitePathPrefixIsEmptyForARootHostedSite() {
        XCTAssertEqual(URLUtils.sitePathPrefix(of: "https://example.com"), "")
        XCTAssertEqual(URLUtils.sitePathPrefix(of: "https://example.com/"), "")
    }

    func testSitePathPrefixNormalisesATrailingSlash() {
        XCTAssertEqual(URLUtils.sitePathPrefix(of: "https://example.com/blog"), "/blog")
        XCTAssertEqual(URLUtils.sitePathPrefix(of: "https://example.com/blog/"), "/blog")
    }

    func testSitePathPrefixKeepsANestedPath() {
        XCTAssertEqual(URLUtils.sitePathPrefix(of: "https://example.com/a/b/"), "/a/b")
    }

    func testSitePathPrefixLeavesAnEncodedPathEncoded() {
        // Already a URL, because the author wrote it as one.
        XCTAssertEqual(
            URLUtils.sitePathPrefix(of: "https://example.com/%E3%83%86"), "/%E3%83%86"
        )
    }
}

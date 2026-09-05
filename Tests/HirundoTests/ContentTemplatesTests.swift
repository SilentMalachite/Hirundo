import XCTest
@testable import HirundoCore

/// The generated front matter must round-trip through the same parser the build uses.
/// A template that only "looks like YAML" is not good enough.
final class ContentTemplatesTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSince1970: 1_772_000_000) // 2026-02-25T06:13:20Z

    private func frontMatter(of markdown: String) throws -> [String: Any] {
        let result = try MarkdownParser().parse(markdown)
        return try XCTUnwrap(result.frontMatter, "Expected parseable front matter in:\n\(markdown)")
    }

    // MARK: - Post

    func testPost_writesTitleDateAndTemplate() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "My Post Title",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertEqual(fm["title"] as? String, "My Post Title")
        XCTAssertEqual(fm["template"] as? String, "post.html")
        XCTAssertNotNil(fm["date"], "A post must carry a date")
    }

    func testPost_datesUseInternetDateTimeInUTC() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "T",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "post.html"
        )

        XCTAssertTrue(
            markdown.contains("date: 2026-02-25T06:13:20Z"),
            "Expected an ISO8601 internet date-time in UTC, got:\n\(markdown)"
        )
    }

    func testPost_neverWritesASlugKey() throws {
        // The output URL comes from the file name while RSS links come from Post.slug.
        // Writing a slug: key lets those two drift apart.
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "My Post Title",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertNil(fm["slug"], "The generated front matter must not pin a slug")
    }

    func testPost_omitsEmptyCategoriesAndTags() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "T",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertNil(fm["categories"])
        XCTAssertNil(fm["tags"])
    }

    func testPost_writesCategoriesAndTagsAsArrays() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "T",
            date: fixedDate,
            categories: ["swift", "development"],
            tags: ["static-site"],
            draft: false,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertEqual(fm["categories"] as? [String], ["swift", "development"])
        XCTAssertEqual(fm["tags"] as? [String], ["static-site"])
    }

    func testPost_omitsDraftKeyWhenNotADraft() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "T",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertNil(fm["draft"], "draft: false is the default; writing it is noise")
    }

    func testPost_writesDraftTrueWhenADraft() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "T",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: true,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertEqual(fm["draft"] as? Bool, true)
    }

    // MARK: - Page

    func testPage_writesTitleAndTemplateButNoDate() throws {
        let markdown = ContentTemplates.markdown(
            kind: .page,
            title: "About",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "default.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertEqual(fm["title"] as? String, "About")
        XCTAssertEqual(fm["template"] as? String, "default.html")
        XCTAssertNil(fm["date"], "Pages match the starter content, which carries no date")
    }

    // MARK: - Escaping

    func testTitlesWithQuotesAndBackslashesRoundTrip() throws {
        let tricky = #"He said "hello" \ goodbye"#
        let markdown = ContentTemplates.markdown(
            kind: .page,
            title: tricky,
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "default.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertEqual(fm["title"] as? String, tricky)
    }

    func testCategoriesWithQuotesRoundTrip() throws {
        let markdown = ContentTemplates.markdown(
            kind: .post,
            title: "T",
            date: fixedDate,
            categories: [#"say "hi""#],
            tags: [],
            draft: false,
            template: "post.html"
        )
        let fm = try frontMatter(of: markdown)

        XCTAssertEqual(fm["categories"] as? [String], [#"say "hi""#])
    }

    // MARK: - Body

    func testBodyStartsWithTheTitleAsAHeading() {
        let markdown = ContentTemplates.markdown(
            kind: .page,
            title: "About",
            date: fixedDate,
            categories: [],
            tags: [],
            draft: false,
            template: "default.html"
        )

        XCTAssertTrue(markdown.contains("\n# About\n"), "Got:\n\(markdown)")
    }

    // MARK: - Defaults

    func testDefaultTemplatePerKind() {
        XCTAssertEqual(ContentKind.post.defaultTemplate, "post.html")
        XCTAssertEqual(ContentKind.page.defaultTemplate, "default.html")
    }
}

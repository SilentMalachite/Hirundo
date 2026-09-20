import XCTest
@testable import HirundoCore

/// `rss.xml`. The feed is the one place a reader's software follows a link without a human
/// looking at it first, so a link that does not resolve is silent.
final class RSSFeedTests: XCTestCase {

    private var projectDir: URL!

    override func setUp() {
        super.setUp()
        projectDir = FileSystemHelper.createTempDirectory()
    }

    override func tearDown() {
        FileSystemHelper.cleanup(projectDir)
        projectDir = nil
        super.tearDown()
    }

    private func scaffoldSite(title: String = "Test Site") throws {
        let templates = projectDir.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
        for name in ["base.html", "default.html", "post.html"] {
            try "<!DOCTYPE html><html><body>{{ content }}</body></html>".write(
                to: templates.appendingPathComponent(name), atomically: true, encoding: .utf8
            )
        }
        try """
        site:
          title: "\(title)"
          url: https://example.com
          language: en-US
        build:
          contentDirectory: content
          outputDirectory: _site
          templatesDirectory: templates
          staticDirectory: static
        features:
          rss: true
        """.write(
            to: projectDir.appendingPathComponent("config.yaml"),
            atomically: true, encoding: .utf8
        )
    }

    private func writeContent(_ relativePath: String, _ body: String) throws {
        let url = projectDir.appendingPathComponent("content").appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    private func build() async throws {
        try await SiteGenerator(projectPath: projectDir.path)
            .build(clean: true, includeDrafts: false)
    }

    private func feed() throws -> String {
        return try String(
            contentsOf: projectDir.appendingPathComponent("_site/rss.xml"), encoding: .utf8
        )
    }

    private func itemLinks() throws -> [String] {
        let xml = try feed()
        let pattern = try NSRegularExpression(pattern: "<link>([^<]*)</link>")
        let range = NSRange(xml.startIndex..., in: xml)
        return pattern.matches(in: xml, range: range)
            .compactMap { Range($0.range(at: 1), in: xml).map { String(xml[$0]) } }
            .filter { $0 != "https://example.com" }
    }

    /// Every link resolves to a file the build actually wrote.
    private func assertEveryItemLinkWasPublished() throws {
        let output = projectDir.appendingPathComponent("_site")
        for link in try itemLinks() {
            let path = link.replacingOccurrences(of: "https://example.com", with: "")
            let file = output.appendingPathComponent(path).appendingPathComponent("index.html")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: file.path),
                "\(link) is not a page this build produced"
            )
        }
    }

    // MARK: - Links

    func testAPostIsLinkedWhereItIsPublished() async throws {
        try scaffoldSite()
        try writeContent("posts/hello.md", """
        ---
        title: "Hello"
        date: 2026-01-01
        ---

        Body.
        """)
        try await build()

        XCTAssertEqual(try itemLinks(), ["https://example.com/posts/hello/"])
        try assertEveryItemLinkWasPublished()
    }

    func testAPostWhoseSlugDiffersFromItsFilenameIsLinkedWhereItIsPublished() async throws {
        // The output path comes from the file's place under `content/`; `slug` does not move it.
        try scaffoldSite()
        try writeContent("posts/hello.md", """
        ---
        title: "Hello"
        slug: a-different-slug
        date: 2026-01-01
        ---

        Body.
        """)
        try await build()

        XCTAssertEqual(try itemLinks(), ["https://example.com/posts/hello/"])
        try assertEveryItemLinkWasPublished()
    }

    func testAPostOutsideThePostsDirectoryIsLinkedWhereItIsPublished() async throws {
        try scaffoldSite()
        try writeContent("notes/memo.md", """
        ---
        title: "Memo"
        type: post
        date: 2026-01-01
        ---

        Body.
        """)
        try await build()

        XCTAssertEqual(try itemLinks(), ["https://example.com/notes/memo/"])
        try assertEveryItemLinkWasPublished()
    }

    // MARK: - Escaping

    func testTheFeedParsesAsXMLWhenTheSiteTitleContainsMarkup() async throws {
        try scaffoldSite(title: "Tom & Jerry <b>")
        try writeContent("posts/hello.md", """
        ---
        title: "A \\"quoted\\" & <b>bold</b> title"
        date: 2026-01-01
        ---

        Body.
        """)
        try await build()

        let xml = try feed()
        XCTAssertTrue(xml.contains("<title>Tom &amp; Jerry &lt;b&gt;</title>"))
        XCTAssertFalse(xml.contains("<b>bold</b>"))

        let parser = XMLParser(data: Data(xml.utf8))
        XCTAssertTrue(parser.parse(), "the feed is not well-formed XML: \(String(describing: parser.parserError))")
    }

    // MARK: - Item descriptions

    private func itemDescriptions() throws -> [String] {
        let xml = try feed()
        let pattern = try NSRegularExpression(
            pattern: "<item>.*?<description>(.*?)</description>", options: [.dotMatchesLineSeparators]
        )
        let range = NSRange(xml.startIndex..., in: xml)
        return pattern.matches(in: xml, range: range)
            .compactMap { Range($0.range(at: 1), in: xml).map { String(xml[$0]) } }
    }

    /// The fallback description was the rendered body cut to 200 characters — HTML, with its
    /// tags and entities intact, handed to an element that is text.
    func testTheFeedDescriptionHoldsTextRatherThanMarkup() async throws {
        try scaffoldSite()
        try writeContent("posts/hello.md", """
        ---
        title: "Hello"
        date: 2026-01-01
        ---

        # Heading

        Body text.
        """)
        try await build()

        let description = try XCTUnwrap(try itemDescriptions().first)
        XCTAssertFalse(description.contains("&lt;p&gt;"), description)
        XCTAssertFalse(description.contains("&lt;h1"), description)
        XCTAssertTrue(description.contains("Body text."), description)
    }

    func testTheFeedDescriptionIsEscapedExactlyOnce() async throws {
        // `escapeXML` runs over whatever arrives, so an entity already in the string was
        // escaped a second time and a reader saw `&amp;`.
        try scaffoldSite()
        try writeContent("posts/amp.md", """
        ---
        title: "Amp"
        date: 2026-01-01
        ---

        Tom & Jerry
        """)
        try await build()

        let description = try XCTUnwrap(try itemDescriptions().first)
        XCTAssertTrue(description.contains("Tom &amp; Jerry"), description)
        XCTAssertFalse(description.contains("&amp;amp;"), description)
    }

    func testADescriptionTheAuthorWroteIsNotDecoded() async throws {
        // Front matter is already text: decoding it would turn a literal `&amp;` into `&`.
        try scaffoldSite()
        try writeContent("posts/explicit.md", """
        ---
        title: "Explicit"
        date: 2026-01-01
        description: "A &amp; B"
        ---

        Body.
        """)
        try await build()

        let description = try XCTUnwrap(try itemDescriptions().first)
        XCTAssertEqual(description, "A &amp;amp; B")
    }
}

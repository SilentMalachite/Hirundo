import XCTest
@testable import HirundoCore

/// What a generated page links to. `Page.url` and `Post.url` used to hold the absolute path the
/// page had been written to, and the archive, category and tag pages put that straight into an
/// `href` — so a published site carried `/Users/<name>/…/_site/posts/foo/index.html` as a link,
/// which is both broken and a disclosure of the build machine's layout.
final class PublishedURLTests: XCTestCase {

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

    /// A site with no archive/category/tag templates, which is what `hirundo init` produces.
    private func scaffoldSite() throws {
        let templates = projectDir.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
        for name in ["base.html", "default.html", "post.html"] {
            try "<!DOCTYPE html><html><body>{{ content }}</body></html>".write(
                to: templates.appendingPathComponent(name), atomically: true, encoding: .utf8
            )
        }
        try """
        site:
          title: Test Site
          url: https://example.com
          language: en-US
        build:
          contentDirectory: content
          outputDirectory: _site
          templatesDirectory: templates
          staticDirectory: static
        features:
          searchIndex: true
        """.write(
            to: projectDir.appendingPathComponent("config.yaml"),
            atomically: true, encoding: .utf8
        )
    }

    private func writeTemplate(_ name: String, _ body: String) throws {
        try body.write(
            to: projectDir.appendingPathComponent("templates").appendingPathComponent(name),
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

    private func post(title: String) -> String {
        return """
        ---
        title: "\(title)"
        date: 2026-01-01
        categories: ["news"]
        tags: ["swift"]
        ---

        Body.
        """
    }

    private func build() async throws {
        try await SiteGenerator(projectPath: projectDir.path)
            .build(clean: true, includeDrafts: false)
    }

    private func output(_ relativePath: String) throws -> String {
        return try String(
            contentsOf: projectDir.appendingPathComponent("_site").appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func hrefs(in html: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "href=\"([^\"]*)\"")
        let range = NSRange(html.startIndex..., in: html)
        return pattern.matches(in: html, range: range).compactMap {
            Range($0.range(at: 1), in: html).map { String(html[$0]) }
        }
    }

    // MARK: - Links on the generated index pages

    func testTheArchivePageLinksEachPostAtItsSiteRelativeURL() async throws {
        try scaffoldSite()
        try writeContent("posts/hello.md", post(title: "Hello"))
        try await build()

        XCTAssertEqual(hrefs(in: try output("archive/index.html")), ["/posts/hello/"])
    }

    func testTheCategoryAndTagPagesLinkEachPostAtItsSiteRelativeURL() async throws {
        try scaffoldSite()
        try writeContent("posts/hello.md", post(title: "Hello"))
        try await build()

        XCTAssertEqual(hrefs(in: try output("categories/news/index.html")), ["/posts/hello/"])
        XCTAssertEqual(hrefs(in: try output("tags/swift/index.html")), ["/posts/hello/"])
    }

    func testAPostOutsideThePostsDirectoryIsLinkedWhereItIsPublished() async throws {
        // A post is one by its path *or* by `type: post` in its front matter, and the output
        // path comes from the file's place under `content/` either way — never from the slug.
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

        XCTAssertEqual(hrefs(in: try output("archive/index.html")), ["/notes/memo/"])
    }

    func testAPostWhoseSlugDiffersFromItsFilenameIsLinkedWhereItIsPublished() async throws {
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

        XCTAssertEqual(hrefs(in: try output("archive/index.html")), ["/posts/hello/"])
    }

    func testAPageAtTheOutputRootIsPublishedAtASlash() async throws {
        try scaffoldSite()
        try writeContent("index.md", "---\ntitle: \"Home\"\n---\n\nBody.\n")
        try writeContent("about.md", "---\ntitle: \"About\"\n---\n\nBody.\n")
        try await build()

        let urls = try searchIndexURLs()
        XCTAssertEqual(urls, ["/", "/about/"])
    }

    // MARK: - The page's own URL

    func testTheRenderedPageKnowsItsOwnSiteRelativeURL() async throws {
        try scaffoldSite()
        try writeTemplate("default.html", "<!DOCTYPE html><html><body>[{{ page.url }}]</body></html>")
        try writeContent("about.md", "---\ntitle: \"About\"\n---\n\nBody.\n")
        try await build()

        XCTAssertTrue(try output("about/index.html").contains("[/about/]"))
    }

    func testTheRenderedPageDoesNotExposeItsSourceMarkdownPath() async throws {
        // `{{ page.url }}` was handed `content.url.path`: the `.md` file's absolute path.
        try scaffoldSite()
        try writeTemplate("default.html", "<!DOCTYPE html><html><body>[{{ page.url }}]</body></html>")
        try writeContent("about.md", "---\ntitle: \"About\"\n---\n\nBody.\n")
        try await build()

        let html = try output("about/index.html")
        XCTAssertFalse(html.contains(".md"))
        XCTAssertFalse(html.contains(projectDir.path))
    }

    func testTheRenderedPostAndTheArchiveAgreeOnItsURL() async throws {
        try scaffoldSite()
        try writeTemplate("post.html", "<!DOCTYPE html><html><body>[{{ page.url }}]</body></html>")
        try writeContent("posts/hello.md", post(title: "Hello"))
        try await build()

        XCTAssertTrue(try output("posts/hello/index.html").contains("[/posts/hello/]"))
        XCTAssertEqual(hrefs(in: try output("archive/index.html")), ["/posts/hello/"])
    }

    // MARK: - No filesystem path reaches the output

    func testNoGeneratedFileContainsTheProjectPath() async throws {
        try scaffoldSite()
        try writeContent("index.md", "---\ntitle: \"Home\"\n---\n\nBody.\n")
        try writeContent("posts/hello.md", post(title: "Hello"))
        try await build()

        let outputDir = projectDir.appendingPathComponent("_site")
        let enumerator = FileManager.default.enumerator(at: outputDir, includingPropertiesForKeys: nil)
        var checked = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            guard ["html", "json", "xml"].contains(fileURL.pathExtension) else { continue }
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(
                text.contains(projectDir.path),
                "the build machine's path reached \(fileURL.lastPathComponent)"
            )
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "the build produced nothing to check")
    }

    // MARK: - The two derivations agree

    func testTheSearchIndexAndTheArchivePageAgreeOnEveryPostURL() async throws {
        try scaffoldSite()
        try writeContent("posts/hello.md", post(title: "Hello"))
        try writeContent("posts/second.md", post(title: "Second"))
        try await build()

        let fromArchive = Set(hrefs(in: try output("archive/index.html")))
        let fromIndex = Set(try searchIndexURLs())
        XCTAssertEqual(fromArchive, fromIndex.subtracting(["/"]))
    }

    // MARK: - A name on disk is the decoded form, a URL is the encoded form

    func testAFilenameContainingAHashIsPublishedUnderAnEncodedURL() async throws {
        // Raw, a browser cuts the request at the `#` and asks for `/foo`.
        try scaffoldSite()
        try writeContent("foo#bar.md", "---\ntitle: \"H\"\n---\n\nBody.\n")
        try await build()

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: projectDir.appendingPathComponent("_site/foo#bar/index.html").path
            ),
            "the directory on disk keeps the name the file had"
        )
        XCTAssertTrue(try searchIndexURLs().contains("/foo%23bar/"))
    }

    func testAFilenameContainingAQuestionMarkIsPublishedUnderAnEncodedURL() async throws {
        try scaffoldSite()
        try writeContent("foo?bar.md", "---\ntitle: \"Q\"\n---\n\nBody.\n")
        try await build()

        XCTAssertTrue(try searchIndexURLs().contains("/foo%3Fbar/"))
    }

    func testANonASCIICategoryPageIsReachableAtTheURLTheIndexLinksTo() async throws {
        // The bug this whole change exists for: the link said
        // `/categories/%E3%83%86%E3%82%B9%E3%83%88/` and the directory was named that literally,
        // so hosting — which decodes before it looks — asked for `categories/テスト/` and 404ed.
        try scaffoldSite()
        try writeContent("posts/hello.md", """
        ---
        title: "Hello"
        date: 2026-01-01
        categories: ["テスト"]
        ---

        Body.
        """)
        try await build()

        let href = try XCTUnwrap(
            hrefs(in: try output("categories/index.html")).first { $0.hasPrefix("/categories/") }
        )
        XCTAssertEqual(href, "/categories/%E3%83%86%E3%82%B9%E3%83%88/")

        let decoded = try XCTUnwrap(href.removingPercentEncoding)
        XCTAssertEqual(decoded, "/categories/テスト/")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: projectDir.appendingPathComponent("_site" + decoded + "index.html").path
            ),
            "the decoded href is the path on disk"
        )
    }

    func testTheDirectoryOnDiskIsTheDecodedFormOfTheURL() async throws {
        // The rule itself, over a whole build rather than one page. Every href the index pages
        // emit, decoded once, must name something that exists.
        try scaffoldSite()
        try writeContent("posts/hello.md", """
        ---
        title: "Hello"
        date: 2026-01-01
        categories: ["テスト", "news"]
        tags: ["タグ", "swift"]
        ---

        Body.
        """)
        try writeContent("foo#bar.md", "---\ntitle: \"H\"\n---\n\nBody.\n")
        try await build()

        let site = projectDir.appendingPathComponent("_site")
        for page in ["categories/index.html", "tags/index.html", "archive/index.html"] {
            for href in hrefs(in: try output(page)) where href.hasPrefix("/") {
                let decoded = try XCTUnwrap(href.removingPercentEncoding, href)
                let target = site.appendingPathComponent(decoded)
                    .appendingPathComponent("index.html")
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: target.path),
                    "\(page) links \(href), which decodes to a path that does not exist"
                )
            }
        }
    }

    private func searchIndexURLs() throws -> [String] {
        struct Entry: Decodable { let url: String }
        struct Index: Decodable { let entries: [Entry] }
        let data = try Data(
            contentsOf: projectDir.appendingPathComponent("_site/search-index.json")
        )
        return try JSONDecoder().decode(Index.self, from: data).entries.map(\.url).sorted()
    }
}

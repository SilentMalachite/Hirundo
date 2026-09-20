import XCTest
@testable import HirundoCore

/// A site published under a path — `site.url: https://example.com/blog`.
///
/// `ConfigValidation.isValidURL` has always accepted one: it checks a scheme and a host and
/// nothing else. Nothing downstream read the path, so every link a build produced pointed at the
/// host's root and 404ed, while the sitemap and the feed — the only two places that built an
/// absolute URL — got it right. The path now reaches a URL from one side: `siteRelativePath`
/// prepends it, and `joinSiteURL` takes only the origin of `site.url`.
final class BasePathTests: XCTestCase {

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

    private func scaffoldSite(url: String) throws {
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
          url: \(url)
          language: en-US
        build:
          contentDirectory: content
          outputDirectory: _site
          templatesDirectory: templates
          staticDirectory: static
        features:
          sitemap: true
          rss: true
          searchIndex: true
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

    private let hello = """
    ---
    title: "Hello"
    date: 2026-01-01
    categories: ["news"]
    tags: ["swift"]
    ---

    Body.
    """

    private func build() async throws {
        try await SiteGenerator(projectPath: projectDir.path)
            .build(clean: true, includeDrafts: false)
    }

    private func output(_ relativePath: String) throws -> String {
        return try String(
            contentsOf: projectDir.appendingPathComponent("_site")
                .appendingPathComponent(relativePath),
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

    private func searchIndexURLs() throws -> [String] {
        struct Entry: Decodable { let url: String }
        struct Index: Decodable { let entries: [Entry] }
        let data = try Data(
            contentsOf: projectDir.appendingPathComponent("_site/search-index.json")
        )
        return try JSONDecoder().decode(Index.self, from: data).entries.map(\.url).sorted()
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    // MARK: - The build

    func testPagesArePublishedUnderTheBasePath() async throws {
        try scaffoldSite(url: "https://example.com/blog")
        try writeContent("posts/hello.md", hello)
        try writeContent("index.md", "---\ntitle: \"Home\"\n---\n\nBody.\n")
        try await build()

        let urls = try searchIndexURLs()
        XCTAssertTrue(urls.contains("/blog/posts/hello/"), "\(urls)")
        XCTAssertTrue(urls.contains("/blog/"), "the output root's own index, too: \(urls)")
    }

    func testTheOutputTreeDoesNotHoldTheBasePath() async throws {
        // The prefix describes where the site is served, not where the build writes.
        try scaffoldSite(url: "https://example.com/blog")
        try writeContent("posts/hello.md", hello)
        try await build()

        let site = projectDir.appendingPathComponent("_site")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: site.appendingPathComponent("posts/hello/index.html").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: site.appendingPathComponent("blog").path
        ))
    }

    func testTheArchiveAndIndexPagesLinkUnderTheBasePath() async throws {
        try scaffoldSite(url: "https://example.com/blog")
        try writeContent("posts/hello.md", hello)
        try await build()

        XCTAssertEqual(hrefs(in: try output("archive/index.html")), ["/blog/posts/hello/"])
        XCTAssertEqual(
            hrefs(in: try output("categories/index.html")), ["/blog/categories/news/"]
        )
        XCTAssertEqual(hrefs(in: try output("tags/index.html")), ["/blog/tags/swift/"])
    }

    func testTheSitemapDoesNotRepeatTheBasePath() async throws {
        // `joinSiteURL` takes only the origin of `site.url`, so the path arrives once.
        try scaffoldSite(url: "https://example.com/blog")
        try writeContent("posts/hello.md", hello)
        try await build()

        let locs = matches("<loc>([^<]*)</loc>", in: try output("sitemap.xml"))
        XCTAssertTrue(locs.contains("https://example.com/blog/posts/hello/"), "\(locs)")
        XCTAssertFalse(locs.contains { $0.contains("/blog/blog/") }, "\(locs)")
    }

    func testTheFeedDoesNotRepeatTheBasePath() async throws {
        try scaffoldSite(url: "https://example.com/blog")
        try writeContent("posts/hello.md", hello)
        try await build()

        let links = matches("<link>([^<]*)</link>", in: try output("rss.xml"))
        XCTAssertTrue(links.contains("https://example.com/blog/posts/hello/"), "\(links)")
        XCTAssertFalse(links.contains { $0.contains("/blog/blog/") }, "\(links)")
    }

    func testARootHostedSiteIsUnchanged() async throws {
        // Regression pin: an empty prefix has to be exactly the old behaviour.
        try scaffoldSite(url: "https://example.com")
        try writeContent("posts/hello.md", hello)
        try await build()

        XCTAssertEqual(hrefs(in: try output("archive/index.html")), ["/posts/hello/"])
        let locs = matches("<loc>([^<]*)</loc>", in: try output("sitemap.xml"))
        XCTAssertTrue(locs.contains("https://example.com/posts/hello/"), "\(locs)")
    }

    // MARK: - The development server

    private func makeServer(basePath: String) -> DevelopmentServer {
        DevelopmentServer(
            projectPath: projectDir.path,
            port: 8080,
            host: "localhost",
            liveReload: false,
            outputDirectory: "_site",
            basePath: basePath
        )
    }

    func testTheDevelopmentServerServesUnderTheBasePath() async throws {
        try scaffoldSite(url: "https://example.com/blog")
        try writeContent("posts/hello.md", hello)
        try await build()

        let expected = projectDir.appendingPathComponent("_site/posts/hello/index.html").path
        XCTAssertEqual(
            makeServer(basePath: "/blog").resolveFilePath(forRequestPath: "/blog/posts/hello/"),
            expected
        )
    }

    func testTheDevelopmentServerStillServesWithoutThePrefix() async throws {
        // Deliberately laxer than a host: the point is to see what was just written.
        try scaffoldSite(url: "https://example.com/blog")
        try writeContent("posts/hello.md", hello)
        try await build()

        let expected = projectDir.appendingPathComponent("_site/posts/hello/index.html").path
        XCTAssertEqual(
            makeServer(basePath: "/blog").resolveFilePath(forRequestPath: "/posts/hello/"),
            expected
        )
    }

    func testTheDevelopmentServerDoesNotStripASiblingPath() async throws {
        try scaffoldSite(url: "https://example.com/blog")
        try writeContent("blogging/note.md", "---\ntitle: \"N\"\n---\n\nBody.\n")
        try await build()

        let expected = projectDir.appendingPathComponent("_site/blogging/note/index.html").path
        XCTAssertEqual(
            makeServer(basePath: "/blog").resolveFilePath(forRequestPath: "/blogging/note/"),
            expected
        )
    }
}

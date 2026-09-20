import XCTest
@testable import HirundoCore

/// `sitemap.xml` is built by walking the output tree, so its `<loc>` values come from a separate
/// derivation to the one the pages themselves use. These pin that the two agree, and that the
/// derivation is anchored: it used to strip the output directory's spelling wherever it appeared
/// and `/index.html` wherever it appeared, neither of which is a prefix or a suffix rule.
final class SitemapTests: XCTestCase {

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
          sitemap: true
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

    private func page(_ title: String) -> String {
        return "---\ntitle: \"\(title)\"\n---\n\nBody.\n"
    }

    private func build(clean: Bool = true) async throws {
        try await SiteGenerator(projectPath: projectDir.path)
            .build(clean: clean, includeDrafts: false)
    }

    private func locations() throws -> [String] {
        let xml = try String(
            contentsOf: projectDir.appendingPathComponent("_site/sitemap.xml"), encoding: .utf8
        )
        let pattern = try NSRegularExpression(pattern: "<loc>([^<]*)</loc>")
        let range = NSRange(xml.startIndex..., in: xml)
        return pattern.matches(in: xml, range: range)
            .compactMap { Range($0.range(at: 1), in: xml).map { String(xml[$0]) } }
            .sorted()
    }

    // MARK: - Shape of a location

    func testEachPageAppearsAtItsDirectoryURL() async throws {
        try scaffoldSite()
        try writeContent("index.md", page("Home"))
        try writeContent("about.md", page("About"))
        try await build()

        // The walk covers the whole output tree, so the generated archive, category and tag
        // index pages are listed alongside the content pages. Every entry is a directory URL.
        XCTAssertEqual(
            try locations(),
            [
                "https://example.com/",
                "https://example.com/about/",
                "https://example.com/archive/",
                "https://example.com/categories/",
                "https://example.com/tags/",
            ]
        )
    }

    func testNoLocationContainsTheOutputDirectoryOrTheProjectPath() async throws {
        try scaffoldSite()
        try writeContent("about.md", page("About"))
        try await build()

        for loc in try locations() {
            XCTAssertFalse(loc.contains("/_site"), loc)
            XCTAssertFalse(loc.contains(projectDir.path), loc)
        }
    }

    func testAFileWhoseNameMerelyContainsIndexHtmlKeepsItsWholeName() async throws {
        // `replacingOccurrences(of: "/index.html", with: "/")` matched anywhere, so this came
        // out as `/docs/.html`.
        try scaffoldSite()
        try writeContent("about.md", page("About"))
        try await build()

        let docs = projectDir.appendingPathComponent("_site/docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try "<html></html>".write(
            to: docs.appendingPathComponent("index.html.html"), atomically: true, encoding: .utf8
        )
        try await build(clean: false)

        let locs = try locations()
        XCTAssertTrue(locs.contains("https://example.com/docs/index.html.html"), "\(locs)")
    }

    // MARK: - Agreement with the other derivation

    func testEverySearchIndexURLAlsoAppearsInTheSitemap() async throws {
        try scaffoldSite()
        try writeContent("index.md", page("Home"))
        try writeContent("about.md", page("About"))
        try writeContent("docs/guide.md", page("Guide"))
        try await build()

        struct Entry: Decodable { let url: String }
        struct Index: Decodable { let entries: [Entry] }
        let data = try Data(
            contentsOf: projectDir.appendingPathComponent("_site/search-index.json")
        )
        let indexed = Set(
            try JSONDecoder().decode(Index.self, from: data).entries
                .map { "https://example.com" + $0.url }
        )
        // Not equality: the sitemap also lists the generated archive, category and tag indexes,
        // which the search index does not cover. What must hold is that the two derivations
        // spell a content page's URL the same way.
        let locs = try locations()
        XCTAssertTrue(
            indexed.isSubset(of: Set(locs)),
            "search index \(indexed.sorted()) vs sitemap \(locs)"
        )
    }
}

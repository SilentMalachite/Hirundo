import XCTest
@testable import HirundoCore

/// `search-index.json` is the only output whose URLs are derived from the absolute path a page
/// was written to, so it is the only one that can leak the build layout into a published URL.
final class SearchIndexTests: XCTestCase {
    private var tempDirectory: URL!
    private var projectPath: String!
    private var outputURL: URL!

    private struct Entry: Decodable { let url: String; let title: String; let content: String }
    private struct Index: Decodable { let entries: [Entry] }

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-search-index-\(UUID().uuidString)")
        projectPath = tempDirectory.path
        outputURL = tempDirectory.appendingPathComponent("_site")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        try write("""
        site:
          title: "Search Site"
          url: "https://example.com"

        features:
          searchIndex: true
        """, to: "config.yaml")

        let template = "<!DOCTYPE html><html><body>{{ content }}</body></html>"
        try write(template, to: "templates/default.html")
        try write(template, to: "templates/post.html")

        try write("---\ntitle: Home\n---\n# Home\n", to: "content/index.md")
        try write("---\ntitle: About\n---\n# About\n", to: "content/about.md")
        try write("""
        ---
        title: First Post
        date: 2024-01-01
        ---
        # First Post
        """, to: "content/posts/first-post.md")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    private func write(_ contents: String, to relativePath: String) throws {
        let url = tempDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func buildAndReadIndex() async throws -> [String] {
        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build()
        let data = try Data(contentsOf: outputURL.appendingPathComponent("search-index.json"))
        return try JSONDecoder().decode(Index.self, from: data).entries.map(\.url).sorted()
    }

    func testSearchIndexEntriesUseSiteRelativeURLs() async throws {
        let urls = try await buildAndReadIndex()

        XCTAssertFalse(urls.isEmpty)
        for url in urls {
            XCTAssertFalse(url.contains("_site"), "the output directory leaked into \(url)")
            XCTAssertFalse(url.contains(projectPath), "the project path leaked into \(url)")
            XCTAssertTrue(url.hasPrefix("/"), url)
        }
    }

    func testSearchIndexPublishesEachPageAtItsDirectoryURL() async throws {
        let urls = try await buildAndReadIndex()

        XCTAssertEqual(urls, ["/", "/about/", "/posts/first-post/"])
    }

    // MARK: - Bodies

    private func buildAndReadEntries() async throws -> [Entry] {
        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build()
        let data = try Data(contentsOf: outputURL.appendingPathComponent("search-index.json"))
        return try JSONDecoder().decode(Index.self, from: data).entries
    }

    /// The index is read with `textContent`, so a body has to be the text the author wrote.
    /// It used to be the rendered page with its tags stripped and nothing else, so `Tom & Jerry`
    /// was indexed as `Tom &amp;amp; Jerry` — shown wrong, and matching no search for the words.
    func testTheIndexedBodyHoldsTheTextTheAuthorWrote() async throws {
        try write("---\ntitle: Amp\n---\n\nTom & Jerry <3\n", to: "content/amp.md")

        let entries = try await buildAndReadEntries()
        let entry = try XCTUnwrap(entries.first { $0.url == "/amp/" })
        XCTAssertTrue(entry.content.contains("Tom & Jerry <3"), entry.content)
        XCTAssertFalse(entry.content.contains("&amp;"), entry.content)
    }

    func testTheIndexedBodyIsNotCutInTheMiddleOfAnEntity() async throws {
        // Decoding after the cut spent five characters of the budget per ampersand and could
        // leave `&am` at the end.
        try write(
            "---\ntitle: Long\n---\n\n" + String(repeating: "a & ", count: 80) + "\n",
            to: "content/long.md"
        )

        let entries = try await buildAndReadEntries()
        let entry = try XCTUnwrap(entries.first { $0.url == "/long/" })
        XCTAssertEqual(entry.content.count, 200)
        XCTAssertFalse(entry.content.contains("&am"), entry.content)
    }
}

import XCTest
@testable import HirundoCore

/// `sitemap.xml`, `rss.xml`, `search-index.json` and `asset-manifest.json` are generated files
/// like any other page, but each was written straight through `write(to:)` rather than
/// `SiteFileManager` — so a symbolic link left at one of those names in the output root was
/// followed, and the build wrote over whatever it pointed at.
///
/// `hirundo serve` rebuilds without cleaning, which is how a link planted once survives to be
/// followed on every later build.
final class FeatureOutputConfinementTests: XCTestCase {

    private var projectDir: URL!
    private var victim: URL!

    override func setUp() {
        super.setUp()
        projectDir = FileSystemHelper.createTempDirectory()
        victim = projectDir.appendingPathComponent("victim.txt")
    }

    override func tearDown() {
        FileSystemHelper.cleanup(projectDir)
        projectDir = nil
        victim = nil
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
          rss: true
          searchIndex: true
          fingerprint: true
        """.write(
            to: projectDir.appendingPathComponent("config.yaml"),
            atomically: true, encoding: .utf8
        )

        let posts = projectDir.appendingPathComponent("content/posts")
        try FileManager.default.createDirectory(at: posts, withIntermediateDirectories: true)
        try "---\ntitle: \"Hello\"\ndate: 2026-01-01\n---\n\nBody.\n".write(
            to: posts.appendingPathComponent("hello.md"), atomically: true, encoding: .utf8
        )

        let css = projectDir.appendingPathComponent("static/css")
        try FileManager.default.createDirectory(at: css, withIntermediateDirectories: true)
        try "body{}".write(
            to: css.appendingPathComponent("style.css"), atomically: true, encoding: .utf8
        )

        try "do not touch".write(to: victim, atomically: true, encoding: .utf8)
    }

    private func build(clean: Bool) async throws {
        try await SiteGenerator(projectPath: projectDir.path)
            .build(clean: clean, includeDrafts: false)
    }

    /// Builds once, plants a link at `name` in the output root pointing at `victim.txt`, then
    /// rebuilds without cleaning — the shape `hirundo serve` produces.
    private func assertOutputIsNotWrittenThroughALinkAt(_ name: String) async throws {
        try scaffoldSite()
        try await build(clean: true)

        let output = projectDir.appendingPathComponent("_site").appendingPathComponent(name)
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.createSymbolicLink(at: output, withDestinationURL: victim)

        try await build(clean: false)

        XCTAssertEqual(
            try String(contentsOf: victim, encoding: .utf8), "do not touch",
            "\(name) was written through the link"
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        XCTAssertNotEqual(
            attributes[.type] as? FileAttributeType, .typeSymbolicLink,
            "\(name) is still a link, so the output tree cannot repair itself"
        )
        XCTAssertGreaterThan(
            try Data(contentsOf: output).count, 0, "\(name) was not regenerated"
        )
    }

    func testTheSitemapIsNotWrittenThroughALinkLeftAtItsName() async throws {
        try await assertOutputIsNotWrittenThroughALinkAt("sitemap.xml")
    }

    func testTheFeedIsNotWrittenThroughALinkLeftAtItsName() async throws {
        try await assertOutputIsNotWrittenThroughALinkAt("rss.xml")
    }

    func testTheSearchIndexIsNotWrittenThroughALinkLeftAtItsName() async throws {
        try await assertOutputIsNotWrittenThroughALinkAt("search-index.json")
    }

    func testTheAssetManifestIsNotWrittenThroughALinkLeftAtItsName() async throws {
        try await assertOutputIsNotWrittenThroughALinkAt("asset-manifest.json")
    }

    func testTheSearchIndexLeavesNoPartialFileBehind() async throws {
        // It was the one generated file written without `.atomic`.
        try scaffoldSite()
        try await build(clean: true)

        let output = projectDir.appendingPathComponent("_site")
        let names = try FileManager.default.contentsOfDirectory(atPath: output.path)
        XCTAssertFalse(
            names.contains { $0.hasPrefix(".") && $0.contains("search-index") }, "\(names)"
        )
    }
}

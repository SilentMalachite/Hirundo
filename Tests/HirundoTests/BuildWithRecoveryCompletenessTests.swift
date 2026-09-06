import XCTest
import CryptoKit
@testable import HirundoCore

/// `buildWithRecovery` is not a reduced build — it is `build` with per-item error recovery.
///
/// This matters beyond `hirundo build --continue-on-error`: `hirundo serve` uses this path for
/// its initial build *and* every rebuild, so anything missing here is missing from the whole
/// development experience.
final class BuildWithRecoveryCompletenessTests: XCTestCase {
    private var tempDirectory: URL!
    private var projectPath: String!
    private var outputURL: URL!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-recovery-completeness-\(UUID().uuidString)")
        projectPath = tempDirectory.path
        outputURL = tempDirectory.appendingPathComponent("_site")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let config = """
        site:
          title: "Recovery Site"
          url: "https://example.com"

        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          templatesDirectory: "templates"
          staticDirectory: "static"

        blog:
          generateArchive: true
          generateCategories: true
          generateTags: true

        features:
          sitemap: true
          rss: true
          searchIndex: true
        """
        try write(config, to: "config.yaml")

        let template = """
        <!DOCTYPE html>
        <html><head><title>{{ page.title }}</title></head><body>{{ content }}</body></html>
        """
        try write(template, to: "templates/default.html")
        try write(template, to: "templates/post.html")

        try write("---\ntitle: Home\n---\n# Home\n", to: "content/index.md")
        try write("""
        ---
        title: First Post
        date: 2024-01-01
        categories: ["swift"]
        tags: ["ssg"]
        ---
        # First Post

        Hello.
        """, to: "content/posts/first-post.md")

        try write("body { color: red; }\n", to: "static/css/style.css")
    }

    override func tearDown() async throws {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    // MARK: - Tests

    func testRecoveryBuildCopiesStaticAssets() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)

        let result = try await generator.buildWithRecovery()

        XCTAssertTrue(result.success, "Build reported failures: \(result.errors)")
        XCTAssertTrue(exists("css/style.css"), "static/ was never copied into the output")
    }

    func testRecoveryBuildGeneratesBlogArchivePages() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)

        let result = try await generator.buildWithRecovery()

        XCTAssertTrue(result.success, "Build reported failures: \(result.errors)")
        XCTAssertTrue(exists("archive/index.html"))
        XCTAssertTrue(exists("categories/index.html"))
        XCTAssertTrue(exists("tags/index.html"))
    }

    func testRecoveryBuildHonorsFeatureFlags() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)

        let result = try await generator.buildWithRecovery()

        XCTAssertTrue(result.success, "Build reported failures: \(result.errors)")
        XCTAssertTrue(exists("sitemap.xml"))
        XCTAssertTrue(exists("rss.xml"))
        XCTAssertTrue(exists("search-index.json"))
    }

    func testRecoveryBuildReportsAFinalizationFailureAndKeepsGoing() async throws {
        // A directory where the sitemap wants to write a file: the write fails, but it is one
        // step out of several and must neither abort the build nor be reported as success.
        try FileManager.default.createDirectory(
            at: outputURL.appendingPathComponent("sitemap.xml"),
            withIntermediateDirectories: true
        )
        let generator = try SiteGenerator(projectPath: projectPath)

        let result = try await generator.buildWithRecovery(clean: false)

        XCTAssertFalse(result.success, "A failed finalization step must not be reported as success")
        XCTAssertEqual(result.failCount, 1)
        XCTAssertEqual(result.errors.first?.stage, .writing)
        XCTAssertTrue(exists("rss.xml"), "Steps after the failing one must still run")
    }

    func testRecoveryBuildRewritesAssetReferencesWhenFingerprintingIsOn() async throws {
        let config = """
        site:
          title: "Recovery Site"
          url: "https://example.com"

        features:
          fingerprint: true
        """
        try write(config, to: "config.yaml")
        try write("""
        <!DOCTYPE html>
        <html><head><link rel="stylesheet" href="/css/style.css"></head><body>{{ content }}</body></html>
        """, to: "templates/default.html")

        let generator = try SiteGenerator(projectPath: projectPath)
        let result = try await generator.buildWithRecovery()
        XCTAssertTrue(result.success, "Build reported failures: \(result.errors)")

        let html = try String(contentsOf: outputURL.appendingPathComponent("index.html"), encoding: .utf8)
        XCTAssertFalse(html.contains("/css/style.css"), "元のパスが残っている: \(html)")

        // 書き換え先が実在すること。これが今まさに壊れている挙動。
        let manifest = try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: outputURL.appendingPathComponent("asset-manifest.json"))
        )
        let fingerprinted = try XCTUnwrap(manifest["css/style.css"])
        XCTAssertTrue(html.contains("/" + fingerprinted), "書き換え後のパスが HTML に無い: \(html)")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent(fingerprinted).path),
            "HTML が実在しないファイルを指している"
        )
    }

    func testRepeatedRebuildKeepsOnlyOneGenerationOfEachAsset() async throws {
        let config = """
        site:
          title: "Recovery Site"
          url: "https://example.com"

        features:
          fingerprint: true
        """
        try write(config, to: "config.yaml")

        let generator = try SiteGenerator(projectPath: projectPath)
        _ = try await generator.buildWithRecovery()

        try write("body { color: blue; }\n", to: "static/css/style.css")
        _ = try await generator.buildWithRecovery()

        let cssFiles = try FileManager.default
            .contentsOfDirectory(atPath: outputURL.appendingPathComponent("css").path)
            .filter { $0.hasSuffix(".css") }
        XCTAssertEqual(cssFiles.count, 1, "古い世代が残っている: \(cssFiles)")
    }

    func testFingerprintingIsOffByDefault() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)
        _ = try await generator.buildWithRecovery()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("css/style.css").path),
            "既定ではハッシュを付けない"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("asset-manifest.json").path),
            "既定ではマニフェストを書かない"
        )
    }

    func testAssetReferenceRewriteNeverTouchesCSSHashedByThePipeline() async throws {
        // The design's guard against a specific regression: pass 2 (inside AssetPipeline)
        // deliberately leaves CSS→CSS `@import` unresolved because all stylesheets are hashed
        // together. If pass 3 (this finalization step) later "fixed" that by rewriting the
        // reference, it would change the bytes of a.css *after* its hash was already baked into
        // its own filename — the file would no longer match its name.
        let config = """
        site:
          title: "Recovery Site"
          url: "https://example.com"

        features:
          fingerprint: true
        """
        try write(config, to: "config.yaml")
        try write("""
        @import url("b.css");
        body { color: red; }
        """, to: "static/css/a.css")
        try write("body { color: blue; }\n", to: "static/css/b.css")

        let generator = try SiteGenerator(projectPath: projectPath)
        let result = try await generator.buildWithRecovery()
        XCTAssertTrue(result.success, "Build reported failures: \(result.errors)")

        let cssDirectory = outputURL.appendingPathComponent("css")
        let cssFiles = try FileManager.default.contentsOfDirectory(atPath: cssDirectory.path)
        let hashedA = try XCTUnwrap(
            cssFiles.first { $0.hasPrefix("a-") && $0.hasSuffix(".css") },
            "static/css/a.css was not fingerprinted: \(cssFiles)"
        )

        let stem = URL(fileURLWithPath: hashedA).deletingPathExtension().lastPathComponent
        let dash = try XCTUnwrap(stem.lastIndex(of: "-"), "unexpected filename shape: \(hashedA)")
        let hashInFilename = String(stem[stem.index(after: dash)...])

        let data = try Data(contentsOf: cssDirectory.appendingPathComponent(hashedA))
        let hashOfContent = SHA256.hash(data: data)
            .compactMap { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
            .lowercased()

        XCTAssertEqual(
            String(hashOfContent), hashInFilename,
            "asset references ステップがパイプライン生成の CSS を書き換え、ファイル名のハッシュと中身が一致しなくなった"
        )
    }

    func testAssetReferenceRewriteResolvesRelativeHrefsFromNestedPages() async throws {
        // The one other rewrite test builds a root `index.html` with a root-relative href, which
        // `AssetManifest.rewrite` resolves without ever consulting `inDirectory`. This test uses
        // a post two directories below the output root (`posts/<slug>/index.html`) with a
        // *relative* href, so it only passes if `inDirectory` is computed per file rather than
        // hard-wired to "" (or anything else fixed).
        let config = """
        site:
          title: "Recovery Site"
          url: "https://example.com"

        features:
          fingerprint: true
        """
        try write(config, to: "config.yaml")
        try write("""
        <!DOCTYPE html>
        <html><head><link rel="stylesheet" href="../../css/style.css"></head><body>{{ content }}</body></html>
        """, to: "templates/post.html")

        let generator = try SiteGenerator(projectPath: projectPath)
        let result = try await generator.buildWithRecovery()
        XCTAssertTrue(result.success, "Build reported failures: \(result.errors)")

        let postURL = outputURL.appendingPathComponent("posts/first-post/index.html")
        let html = try String(contentsOf: postURL, encoding: .utf8)

        let hrefRange = try XCTUnwrap(
            html.range(of: #"href="([^"]+)""#, options: .regularExpression),
            "no href found in \(html)"
        )
        let href = String(html[hrefRange])
            .replacingOccurrences(of: "href=\"", with: "")
            .replacingOccurrences(of: "\"", with: "")

        XCTAssertNotEqual(href, "../../css/style.css", "元の相対パスが残っている: \(html)")

        // Resolve the rewritten href exactly as a browser would: relative to the file that
        // contains it, not relative to the output root.
        let resolved = postURL.deletingLastPathComponent()
            .appendingPathComponent(href)
            .standardizedFileURL
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resolved.path),
            "書き換え後の相対パスが実在しない: \(href) (resolved: \(resolved.path))"
        )
    }

    // MARK: - Helpers

    private func write(_ contents: String, to relativePath: String) throws {
        let url = tempDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exists(_ relativePath: String) -> Bool {
        return FileManager.default.fileExists(atPath: outputURL.appendingPathComponent(relativePath).path)
    }
}

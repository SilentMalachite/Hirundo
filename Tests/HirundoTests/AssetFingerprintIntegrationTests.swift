import XCTest
@testable import HirundoCore

/// `hirundo build` の出力を、ブラウザが見るのと同じ目で確かめる。
///
/// フィンガープリントの本当の合格条件はハッシュが付くことではなく、**生成された HTML が実在
/// するファイルを指していること**である。これが長らく壊れていた。
final class AssetFingerprintIntegrationTests: XCTestCase {

    private var tempDirectory: URL!
    private var projectPath: String!
    private var outputURL: URL!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-fingerprint-\(UUID().uuidString)")
        projectPath = tempDirectory.path
        outputURL = tempDirectory.appendingPathComponent("_site")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        try write("""
        site:
          title: "Fingerprint Site"
          url: "https://example.com"

        features:
          fingerprint: true
          minify: true
        """, to: "config.yaml")

        try write("""
        <!DOCTYPE html>
        <html>
        <head><link rel="stylesheet" href="/css/style.css"></head>
        <body>
          <img src="/images/logo.png" alt="logo">
          <script src="/js/app.js"></script>
          {{ content }}
        </body>
        </html>
        """, to: "templates/default.html")

        try write("---\ntitle: Home\n---\n# Home\n", to: "content/index.md")
        try write("---\ntitle: Deep\n---\n# Deep\n", to: "content/guides/deep.md")

        try write("body{background:url(../images/logo.png)}", to: "static/css/style.css")
        try write("console.log('hi');", to: "static/js/app.js")
        try write("not really a png", to: "static/images/logo.png")
        try write("User-agent: *\n", to: "static/robots.txt")
    }

    override func tearDown() async throws {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    private func write(_ contents: String, to relativePath: String) throws {
        let url = tempDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func manifest() throws -> [String: String] {
        try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: outputURL.appendingPathComponent("asset-manifest.json"))
        )
    }

    /// HTML と CSS のローカルなアセット参照が、出力に実在するファイルを指しているか。
    ///
    /// ルート絶対（`/css/x.css`）と、そのファイルからの相対（`../images/x.png`）の両方を辿る。
    private func assertEveryReferenceResolves(in relativePath: String) throws {
        let fileURL = outputURL.appendingPathComponent(relativePath)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"(?:href|src)="([^"]+)"|url\(([^)"']+)\)"#)
        let range = NSRange(content.startIndex..., in: content)
        let directory = fileURL.deletingLastPathComponent()

        var checked = 0
        for match in regex.matches(in: content, range: range) {
            for group in 1...2 {
                guard let r = Range(match.range(at: group), in: content) else { continue }
                let reference = String(content[r]).trimmingCharacters(in: .whitespaces)
                guard reference.hasSuffix(".css") || reference.hasSuffix(".js") || reference.hasSuffix(".png")
                else { continue }
                guard !reference.contains(":"), !reference.hasPrefix("//") else { continue }

                let target = reference.hasPrefix("/")
                    ? outputURL.appendingPathComponent(String(reference.dropFirst()))
                    : directory.appendingPathComponent(reference).standardizedFileURL
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: target.path),
                    "\(relativePath) が実在しない \(reference) を指している"
                )
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0, "\(relativePath) に検査対象の参照が無い")
    }

    func testBuiltSiteOnlyReferencesFilesThatExist() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build()

        try assertEveryReferenceResolves(in: "index.html")
        try assertEveryReferenceResolves(in: "guides/deep/index.html")

        let stylesheet = try XCTUnwrap(manifest()["css/style.css"])
        try assertEveryReferenceResolves(in: stylesheet)
    }

    func testEveryAssetIsFingerprinted() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build()

        let manifest = try manifest()
        for key in ["css/style.css", "js/app.js", "images/logo.png"] {
            let value = try XCTUnwrap(manifest[key], "\(key) がマニフェストに無い")
            XCTAssertNotEqual(value, key, "\(key) にハッシュが付いていない")
            XCTAssertTrue(AssetPruner.isFingerprintedName(URL(fileURLWithPath: value).lastPathComponent))
        }
    }

    /// フィンガープリント有効時、`clean: true` のビルドがハッシュ無しの名前を一切書き出さない
    /// ことを確かめる。世代をまたいだ古いハッシュ付き出力の掃除（`AssetPruner`）は別の性質で、
    /// こちらは `BuildWithRecoveryCompletenessTests.testRepeatedRebuildKeepsOnlyOneGenerationOfEachAsset`
    /// が担保している。
    /// `robots.txt` はどのページからも参照されないため、フィンガープリントすると404になる。
    /// `AssetFingerprintExclusions` の組み込みパターンにより、フィンガープリント有効時でも
    /// 元の名前のまま出力されるべき。
    func testFingerprintExcludedAssetKeepsItsOriginalName() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("robots.txt").path),
            "robots.txt が元の名前で出力されていない"
        )
        XCTAssertEqual(try manifest()["robots.txt"], "robots.txt")
    }

    /// `config.assets.fingerprintExclude` から `assetPipeline.fingerprintExclusions` への配線
    /// （`SiteGenerator.configureAssetPipeline`、`SiteGenerator.swift:430-432`）を、実際に
    /// `config.yaml` を経由して検証する。`ads.txt` は組み込みパターンのどれにも一致しないので、
    /// これが除外されるのは配線が効いている場合に限られる ── その配線を消せばこのテストは
    /// 落ちる（RED として確認済み。詳細は task-3-report.md のフィックスラウンド参照）。
    func testConfigSuppliedFingerprintExcludePatternExemptsAFileEndToEnd() async throws {
        try write("""
        site:
          title: "Fingerprint Site"
          url: "https://example.com"

        features:
          fingerprint: true
          minify: true

        assets:
          fingerprintExclude:
            - "ads.txt"
        """, to: "config.yaml")
        try write("place: /ads.txt\n", to: "static/ads.txt")

        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("ads.txt").path),
            "ads.txt が元の名前で出力されていない"
        )
        let builtManifest = try manifest()
        XCTAssertEqual(builtManifest["ads.txt"], "ads.txt")

        // 同じビルドの中で、除外対象ではない通常のアセットは変わらずハッシュされるべき。
        // (この後半のアサーションが無いと、フィンガープリント自体が丸ごと無効化されていても
        // このテストは通ってしまう。)
        let hashedStylesheet = try XCTUnwrap(builtManifest["css/style.css"])
        XCTAssertNotEqual(hashedStylesheet, "css/style.css", "除外対象ではないアセットはハッシュされるべき")
    }

    func testCleanBuildNeverWritesTheUnhashedFilename() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build(clean: true)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("css/style.css").path),
            "ハッシュ無しの名前でも出力されている"
        )
    }
}

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

    func testCleanBuildLeavesNoUnfingerprintedAssetBehind() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build(clean: true)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("css/style.css").path),
            "ハッシュ無しの名前でも出力されている"
        )
    }
}

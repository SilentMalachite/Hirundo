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

    func testRebuildRemovesAnAssetWhoseDirectoryWasDeletedFromStatic() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build()

        let stale = try XCTUnwrap(manifest()["images/logo.png"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.appendingPathComponent(stale).path))

        try FileManager.default.removeItem(at: tempDirectory.appendingPathComponent("static/images"))
        try write("body{background:none}", to: "static/css/style.css")

        try await SiteGenerator(projectPath: projectPath).build()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent(stale).path),
            "static から消えたアセットの公開済み出力が既知の URL で残っている"
        )
    }

    func testRebuildRemovesTheHashedOutputWhenTheStaticDirectoryIsDeleted() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build()

        let hashed = try manifest().values.filter {
            AssetPruner.isFingerprintedName(URL(fileURLWithPath: $0).lastPathComponent)
        }
        XCTAssertFalse(hashed.isEmpty, "前提: 1回目のビルドがハッシュ名のアセットを出している")

        try FileManager.default.removeItem(at: tempDirectory.appendingPathComponent("static"))

        try await SiteGenerator(projectPath: projectPath).build()

        for path in hashed.sorted() {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: outputURL.appendingPathComponent(path).path),
                "\(path) が残っている"
            )
        }

        // フィンガープリントを外したアセット（`robots.txt` など）は残る。掃除がハッシュ名の
        // ファイルしか消さないのは、生成されたページと出力パスがぶつかったときにページの方を
        // 消してしまわないための条件で、消し残しよりページを失う方が痛い。直し方は --clean。
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("robots.txt").path),
            "掃除の範囲がハッシュ名以外にも広がっている"
        )
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

    /// パス3（`SiteGenerator.rewriteAssetReferences`）が UTF-8 として読めないファイルに出会った
    /// ときの挙動。スキップ自体は仕様どおり（バイナリを壊さない）だが、無言でスキップすると
    /// ページに未解決の参照が残ったまま気づけない。1行の警告を出すべき。
    func testNonUTF8FileInOutputTreeIsSkippedAndWarnedAbout() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)

        // `build()` は clean しない限り既存の出力を消さないので、事前に置いたファイルは
        // パス3の巡回対象として残る。
        try FileManager.default.createDirectory(
            at: outputURL.appendingPathComponent("legacy"),
            withIntermediateDirectories: true
        )
        let brokenFile = outputURL.appendingPathComponent("legacy/mystery.html")
        let invalidUTF8 = Data([0xFF, 0xFE, 0x00, 0x01])
        try invalidUTF8.write(to: brokenFile)

        let stderrOutput = try await capturingStandardError {
            try await generator.build()
        }

        XCTAssertEqual(
            try Data(contentsOf: brokenFile), invalidUTF8,
            "UTF-8 として読めないファイルの中身を書き換えてはいけない"
        )
        XCTAssertTrue(
            stderrOutput.contains("legacy/mystery.html"),
            "警告がファイルを名指ししていない: \(stderrOutput)"
        )
        XCTAssertTrue(stderrOutput.contains("UTF-8"), "警告が理由を説明していない: \(stderrOutput)")
    }

    /// `.htm` は Hirundo がどこでも書き出さない拡張子なので、パス3が触ってよい理由が無い。
    /// `generateSitemap` と同じく `html` だけに一致させる。
    func testHtmFileInOutputTreeIsNoLongerRewritten() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let htmFile = outputURL.appendingPathComponent("legacy.htm")
        let original = "<img src=\"/images/logo.png\">"
        try original.write(to: htmFile, atomically: true, encoding: .utf8)

        try await generator.build()

        let content = try String(contentsOf: htmFile, encoding: .utf8)
        XCTAssertEqual(content, original, ".htm ファイルは書き換え対象から外れているべき")
    }

    /// パス2は全 CSS を同時に扱うため、CSS→CSS の `@import url(...)` は常に未解決のまま残る
    /// （`AssetPipelineTests.testCSSToCSSReferenceIsLeftUnresolved` が固定済み）。そのとき
    /// `AssetPipeline` がファイルと参照先を名指しした警告を stderr に1行書くはずだが、
    /// 未検証だった。
    func testUnresolvedCSSToCSSImportWarnsOnStderr() async throws {
        try write(
            "@import url(\"other.css\");\nbody{background:url(../images/logo.png)}",
            to: "static/css/style.css"
        )

        let generator = try SiteGenerator(projectPath: projectPath)

        let stderrOutput = try await capturingStandardError {
            try await generator.build()
        }

        XCTAssertTrue(
            stderrOutput.contains("css/style.css"),
            "警告がファイルを名指ししていない: \(stderrOutput)"
        )
        XCTAssertTrue(
            stderrOutput.contains("other.css"),
            "警告が未解決の参照を名指ししていない: \(stderrOutput)"
        )
    }

    // MARK: - stderr capture

    /// `body` の実行中だけ stderr をパイプにつなぎ替えて、そこに書かれたものを文字列で返す。
    /// `SiteGenerator`/`AssetPipeline` の警告は stderr への直接書き込みなので、これが確かめる
    /// 唯一の方法。パイプの書き込み端を閉じてから読むので、詰まって待ち続けることはない。
    private func capturingStandardError(_ body: () async throws -> Void) async throws -> String {
        let pipe = Pipe()
        fflush(stderr)
        let saved = dup(STDERR_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        var restored = false
        func restore() {
            guard !restored else { return }
            restored = true
            fflush(stderr)
            dup2(saved, STDERR_FILENO)
            close(saved)
            try? pipe.fileHandleForWriting.close()
        }

        do {
            try await body()
        } catch {
            restore()
            throw error
        }
        restore()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

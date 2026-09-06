import XCTest
@testable import HirundoCore

/// `AssetFileManager` の閉じ込め判定（列挙時）とソースの読み込みの間に起きる変化を、
/// 決定的に再現するためのフック。`resolveConfinedSource` は読み込みの直前に呼ばれるので、
/// `beforeResolving` は「列挙は通ったが読む前に差し替えられた」、`afterResolving` は
/// 「判定は通ったがコピーの前に書き換えられた」を表す。
final class HookedAssetPipeline: AssetPipeline {
    var beforeResolving: ((URL) throws -> Void)?
    var afterResolving: ((URL) throws -> Void)?

    override func resolveConfinedSource(_ fileURL: URL, sourceRoot: String) throws -> ConfinedSource {
        try beforeResolving?(fileURL)
        let resolved = try super.resolveConfinedSource(fileURL, sourceRoot: sourceRoot)
        try afterResolving?(fileURL)
        return resolved
    }
}

final class AssetPipelineTests: XCTestCase {
    
    var tempDir: URL!
    var pipeline: AssetPipeline!
    
    override func setUp() {
        super.setUp()
        
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asset-pipeline-test-\(UUID())")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        pipeline = AssetPipeline()
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testBasicAssetCopy() throws {
        // Create source and destination directories
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // Create test files
        let cssFile = sourceDir.appendingPathComponent("style.css")
        try "body { color: red; }".write(to: cssFile, atomically: true, encoding: .utf8)
        
        let jsFile = sourceDir.appendingPathComponent("script.js")
        try "console.log('hello');".write(to: jsFile, atomically: true, encoding: .utf8)
        
        // Process assets
        let _ = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
        // Verify files were copied
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("style.css").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("script.js").path))
    }
    
    func testDirectoryStructurePreservation() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        
        // Create nested directory structure
        let cssDir = sourceDir.appendingPathComponent("css")
        let jsDir = sourceDir.appendingPathComponent("js")
        let imgDir = sourceDir.appendingPathComponent("images")
        
        try FileManager.default.createDirectory(at: cssDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: jsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imgDir, withIntermediateDirectories: true)
        
        // Create files in subdirectories
        try "body { margin: 0; }".write(to: cssDir.appendingPathComponent("main.css"), atomically: true, encoding: .utf8)
        try "function init() {}".write(to: jsDir.appendingPathComponent("app.js"), atomically: true, encoding: .utf8)
        try Data().write(to: imgDir.appendingPathComponent("logo.png"))
        
        // Process assets
        let _ = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
        // Verify directory structure
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("css/main.css").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("js/app.js").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("images/logo.png").path))
    }
    
    func testAssetTypeDetection() throws {
        let assets = [
            ("style.css", AssetType.css),
            ("app.js", AssetType.javascript),
            ("logo.png", AssetType.image("png")),
            ("banner.jpg", AssetType.image("jpg")),
            ("readme.txt", AssetType.other("txt"))
        ]
        
        for (filename, expectedType) in assets {
            let detectedType = pipeline.detectAssetType(for: filename)
            XCTAssertEqual(detectedType, expectedType, "Failed to detect type for \(filename)")
        }
    }
    
    func testAssetMinification() throws {
        // Enable built-in minification
        pipeline.cssOptions.minify = true
        
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // Create CSS file with whitespace
        let cssFile = sourceDir.appendingPathComponent("style.css")
        let cssContent = """
        body {
            margin: 0;
            padding: 0;
            color: #333;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        """
        try cssContent.write(to: cssFile, atomically: true, encoding: .utf8)
        
        // Process assets
        let _ = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
        // Verify minification (no newlines, compact braces)
        let processedCSS = try String(contentsOf: destDir.appendingPathComponent("style.css"), encoding: .utf8)
        XCTAssertFalse(processedCSS.contains("\n"))
        XCTAssertTrue(processedCSS.contains("body{"))
    }
    
    func testImageOptimization() throws {
        // This test would require actual image data
        // For now, we'll test the pipeline recognizes image types
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // Create fake image files
        let imageTypes = ["png", "jpg", "jpeg", "gif", "webp"]
        for ext in imageTypes {
            let imagePath = sourceDir.appendingPathComponent("test.\(ext)")
            try Data([0xFF, 0xD8, 0xFF]).write(to: imagePath) // Fake JPEG header
        }
        
        // Process assets
        let _ = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
        // Verify all images were processed
        for ext in imageTypes {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: destDir.appendingPathComponent("test.\(ext)").path
            ))
        }
    }
    
    func testAssetFiltering() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // Configure exclusions
        pipeline.excludePatterns = ["*.tmp", ".*", "_*", "*.log"]
        
        // Create various files
        try "keep".write(to: sourceDir.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        try "skip".write(to: sourceDir.appendingPathComponent("temp.tmp"), atomically: true, encoding: .utf8)
        try "skip".write(to: sourceDir.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        try "skip".write(to: sourceDir.appendingPathComponent("_draft.css"), atomically: true, encoding: .utf8)
        try "skip".write(to: sourceDir.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        
        // Process assets
        let _ = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
        // Verify only non-excluded files were copied
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("style.css").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("temp.tmp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.appendingPathComponent(".hidden").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("_draft.css").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("debug.log").path))
    }
    
    func testAssetFingerprinting() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        pipeline.enableFingerprinting = true

        let cssFile = sourceDir.appendingPathComponent("style.css")
        let cssContent = "body { color: blue; }"
        try cssContent.write(to: cssFile, atomically: true, encoding: .utf8)

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        let fingerprintedPath = try XCTUnwrap(manifest["style.css"])
        XCTAssertTrue(fingerprintedPath.contains("-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent(fingerprintedPath).path))

        let processedContent = try String(contentsOf: destDir.appendingPathComponent(fingerprintedPath), encoding: .utf8)
        XCTAssertEqual(processedContent, cssContent)
    }

    /// パススルーアセット（画像など）の書き出しが `Data` 経由の全バイト書き換えに戻っていないか。
    /// `FileManager.copyItem` を使えば、ソースの POSIX パーミッションを引き継ぐはず。通常の
    /// umask では新規書き込みが 0644 になりがちな値をあえて避けて 0640 にすることで、
    /// 「たまたま一致した」を排除する。ハッシュ名も、書き込んだバイト列（＝ソースのバイト列、
    /// パススルーなので変化しない）から計算した値と一致するべき。
    func testPassThroughAssetPreservesSourcePermissionsAndHashesTheBytesWritten() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let logoFile = sourceDir.appendingPathComponent("logo.png")
        let logoContent = Data("not really a png, just some bytes to hash".utf8)
        try logoContent.write(to: logoFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: logoFile.path)

        pipeline.enableFingerprinting = true
        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        let fingerprintedPath = try XCTUnwrap(manifest["logo.png"])
        let expectedFingerprint = AssetProcessor().generateFingerprint(for: logoContent)
        XCTAssertEqual(
            fingerprintedPath, "logo-\(expectedFingerprint).png",
            "出力名 \(fingerprintedPath) が書き込んだバイト列のハッシュ \(expectedFingerprint) から作られる正確な名前と一致しない"
        )

        let outputURL = destDir.appendingPathComponent(fingerprintedPath)
        XCTAssertEqual(try Data(contentsOf: outputURL), logoContent)

        let outputAttributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let outputPermissions = try XCTUnwrap(outputAttributes[.posixPermissions] as? Int)
        XCTAssertEqual(
            outputPermissions, 0o640,
            "コピーがソースのパーミッションを引き継いでいない（Data 経由の書き込みに戻っている）"
        )
    }

    /// レビューで見つかった Critical の回帰: `copyItem` はシンボリックリンクをリンクのまま
    /// コピーするため、ベンダリングでよくある `static/img/logo.png -> ../../shared/logo.png`
    /// のような配置だと、`_site` の画像が出力先の外を指すリンクになってしまう。
    /// ハッシュはリンク先の実体（`FileHandle` は辿る）に対して取られるので、書き込まれる
    /// バイト列と食い違う。ここでは、出力が通常ファイルとしてリンク先のバイト列を持つことを
    /// 固定する。
    func testSymlinkedPassThroughAssetIsWrittenAsARegularFileWithTheTargetsBytes() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent("img"),
            withIntermediateDirectories: true
        )

        // リンク先は static の中に置く。外を指すリンクは `AssetFileManager` が列挙の時点で
        // 飛ばすので、`write` まで届くのは中で完結するリンクだけ。
        let sharedDir = sourceDir.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        let targetContent = Data("this is the real image bytes".utf8)
        let targetFile = sharedDir.appendingPathComponent("logo-real.png")
        try targetContent.write(to: targetFile)

        let logoLink = sourceDir.appendingPathComponent("img/logo.png")
        try FileManager.default.createSymbolicLink(at: logoLink, withDestinationURL: targetFile)

        pipeline.enableFingerprinting = true
        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        let outputRelativePath = try XCTUnwrap(manifest["img/logo.png"])
        let outputURL = destDir.appendingPathComponent(outputRelativePath)

        let resourceValues = try outputURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertNotEqual(
            resourceValues.isSymbolicLink, true,
            "出力がシンボリックリンクのまま書き出されている: \(outputURL.path)"
        )
        XCTAssertEqual(
            try Data(contentsOf: outputURL), targetContent,
            "出力のバイト列がリンク先の実体と一致しない"
        )

        // フィンガープリントは「書き込んだバイト列」を覆っていなければならない。
        let expectedFingerprint = AssetProcessor().generateFingerprint(for: targetContent)
        XCTAssertEqual(outputRelativePath, "img/logo-\(expectedFingerprint).png")
    }

    /// レビューで見つかった Critical の回帰の核心: シンボリックリンクをリンクのまま書き出すと、
    /// `write` 冒頭の閉じ込め判定は候補パスを `resolvingSymlinksInPath()` で解決するため、
    /// 次の非クリーンビルド（`hirundo serve` の再ビルド相当）でそのリンクの解決先が出力先の
    /// 外だと判定され、ビルドが `Output path escapes destination directory` で落ちる。
    ///
    /// リンク先は **static の中** に置く。外を指すリンクは `AssetFileManager` が列挙の時点で
    /// 飛ばすので、外に置くと両方のビルドで `write` に届かず、このテストは何も検証しない
    /// （以前はそうなっていた）。`XCTUnwrap(first["img/logo.png"])` が、リンクが実際に処理
    /// されたことの証拠になる。
    func testSecondBuildAfterASymlinkedAssetDoesNotThrow() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent("img"),
            withIntermediateDirectories: true
        )

        let sharedDir = sourceDir.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        let targetContent = Data("this is the real image bytes".utf8)
        let targetFile = sharedDir.appendingPathComponent("logo-real.png")
        try targetContent.write(to: targetFile)

        let logoLink = sourceDir.appendingPathComponent("img/logo.png")
        try FileManager.default.createSymbolicLink(at: logoLink, withDestinationURL: targetFile)

        // 1回目: リンクが実体として書き出されていること。リンクのまま出ると、2回目の閉じ込め
        // 判定がその解決先を見て落ちる。フィンガープリント無効でも壊れる経路なので無効のまま。
        let first = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        let firstOutput = destDir.appendingPathComponent(try XCTUnwrap(first["img/logo.png"]))
        XCTAssertNotEqual(
            try firstOutput.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true,
            "1回目のビルドがシンボリックリンクのまま書き出している: \(firstOutput.path)"
        )

        // 2回目: `hirundo serve` はクリーンせずに同じ出力先へ再ビルドする。
        var second = AssetManifest()
        XCTAssertNoThrow(
            second = try pipeline.processAssets(from: sourceDir.path, to: destDir.path),
            "1回目のビルドが残した出力の上に2回目のビルドが書けない"
        )
        XCTAssertEqual(second["img/logo.png"], "img/logo.png")
        XCTAssertEqual(
            try Data(contentsOf: firstOutput), targetContent,
            "2回目のビルド後の出力がリンク先の実体と一致しない"
        )
    }

    /// 上の修正を入れる前のビルドが残した `_site` には、出力先そのものがシンボリックリンクに
    /// なっているファイルがある。`replaceItemAt` は差し替え先が実在のファイルでないと
    /// "file doesn't exist" で失敗するため、そのままでは非クリーン再ビルドが再び詰まる。
    /// 修正前のコード（`removeItem` してから `copyItem`）はこの状態から自己修復できていたので、
    /// 回復能力を落とさないことを固定する。
    func testBuildOverAnOutputLeftAsASymlinkRecovers() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let sharedDir = tempDir.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        let targetFile = sharedDir.appendingPathComponent("logo-real.png")
        let targetContent = Data("the real bytes".utf8)
        try targetContent.write(to: targetFile)

        try Data("fresh bytes".utf8).write(to: sourceDir.appendingPathComponent("logo.png"))

        // 修正前のビルドが残した出力を再現する: 出力先が出力ツリーの外を指すリンクになっている。
        let staleOutput = destDir.appendingPathComponent("logo.png")
        try FileManager.default.createSymbolicLink(at: staleOutput, withDestinationURL: targetFile)

        XCTAssertNoThrow(
            try pipeline.processAssets(from: sourceDir.path, to: destDir.path),
            "リンクとして残った出力の上に書けず、非クリーン再ビルドが回復できない"
        )

        let resourceValues = try staleOutput.resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertNotEqual(resourceValues.isSymbolicLink, true)
        XCTAssertEqual(try Data(contentsOf: staleOutput), Data("fresh bytes".utf8))
        // リンク先が書き換えられていないこと（リンク越しに書いてしまうと出力先の外を壊す）。
        XCTAssertEqual(try Data(contentsOf: targetFile), targetContent)
    }

    /// 上の自己修復のために閉じ込め判定は最後の要素を解決しなくなったが、途中のディレクトリは
    /// 引き続き解決して判定する。出力ツリー内のディレクトリが外を指すリンクにすり替えられていたら、
    /// 書き込みは拒否されなければならない。
    func testWriteThroughASymlinkedOutputDirectoryIsRefused() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent("img"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try Data("bytes".utf8).write(to: sourceDir.appendingPathComponent("img/logo.png"))

        // 出力先の `img/` が出力ツリーの外を指すリンクになっている。
        let outsideDir = tempDir.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: destDir.appendingPathComponent("img"),
            withDestinationURL: outsideDir
        )

        XCTAssertThrowsError(
            try pipeline.processAssets(from: sourceDir.path, to: destDir.path),
            "出力ツリーの外を指すディレクトリリンク越しに書き込んでいる"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outsideDir.appendingPathComponent("logo.png").path),
            "出力先の外にファイルが書き出された"
        )
    }

    /// `resolvingSymlinksInPath()` は最後の要素が解決できない壊れたリンクには何もしないため、
    /// 解決したつもりのパスがリンクのままになり、`copyItem` がリンクをコピーしてしまう。
    /// このブランチ以前の `Data(contentsOf:)` はここで失敗していたので、同じく失敗させる。
    func testBrokenSymlinkedAssetThrowsInsteadOfCopyingTheLink() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let missingTarget = sourceDir.appendingPathComponent("never-created.png")
        try FileManager.default.createSymbolicLink(
            at: sourceDir.appendingPathComponent("logo.png"),
            withDestinationURL: missingTarget
        )

        XCTAssertThrowsError(
            try pipeline.processAssets(from: sourceDir.path, to: destDir.path),
            "壊れたシンボリックリンクが黙ってリンクのままコピーされている"
        )

        let output = destDir.appendingPathComponent("logo.png")
        if FileManager.default.fileExists(atPath: output.path) {
            let resourceValues = try output.resourceValues(forKeys: [.isSymbolicLinkKey])
            XCTAssertNotEqual(resourceValues.isSymbolicLink, true)
        }
    }

    /// `replaceItemAt` は既定で差し替え先（＝前回の出力）のメタデータを引き継ぐ。それだと
    /// `static/` 側でパーミッションを変えても非クリーン再ビルドに反映されない。修正前の
    /// `copyItem` はソース由来のパーミッションで書いていたので、同じ結果になることを固定する。
    func testPassThroughPermissionChangeReachesANonCleanRebuild() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let sourceFile = sourceDir.appendingPathComponent("logo.png")
        try Data("bytes".utf8).write(to: sourceFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sourceFile.path)
        _ = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: sourceFile.path)
        _ = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        let output = destDir.appendingPathComponent("logo.png")
        let permissions = try FileManager.default.attributesOfItem(atPath: output.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(
            permissions?.int16Value, 0o644,
            "再ビルドの出力が前回の出力のパーミッションを引きずっている"
        )
    }

    func testManifestValueKeepsItsDirectory() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent("css"),
            withIntermediateDirectories: true
        )
        pipeline.enableFingerprinting = true
        try "body{}".write(to: sourceDir.appendingPathComponent("css/style.css"), atomically: true, encoding: .utf8)

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        let value = try XCTUnwrap(manifest["css/style.css"])
        XCTAssertTrue(value.hasPrefix("css/"), "値は出力相対パスであるべき。実際: \(value)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent(value).path))
    }

    func testManifestIsCompleteWithoutFingerprinting() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "body{}".write(to: sourceDir.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        try Data().write(to: sourceDir.appendingPathComponent("logo.png"))

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        XCTAssertEqual(manifest["style.css"], "style.css")
        XCTAssertEqual(manifest["logo.png"], "logo.png")
    }

    func testManifestRoundTripsThroughDisk() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent("css"),
            withIntermediateDirectories: true
        )
        pipeline.enableFingerprinting = true
        try "body{}".write(to: sourceDir.appendingPathComponent("css/style.css"), atomically: true, encoding: .utf8)

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        let path = destDir.appendingPathComponent("asset-manifest.json").path
        try pipeline.saveManifest(manifest, to: path)

        XCTAssertEqual(try pipeline.loadManifest(from: path), manifest)
    }

    func testFingerprintCoversTheProcessedBytesNotTheSource() throws {
        // 同じソースを、最小化あり・なしで別々の出力に処理する。ハッシュが処理後のバイト列に
        // 対して取られていれば、ふたつの出力名は違うものになる。
        let sourceDir = tempDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "body {\n  color: red;\n}\n".write(
            to: sourceDir.appendingPathComponent("style.css"),
            atomically: true,
            encoding: .utf8
        )

        let plain = AssetPipeline()
        plain.enableFingerprinting = true
        let plainManifest = try plain.processAssets(
            from: sourceDir.path,
            to: tempDir.appendingPathComponent("dest-plain").path
        )

        let minified = AssetPipeline()
        minified.enableFingerprinting = true
        minified.cssOptions.minify = true
        let minifiedManifest = try minified.processAssets(
            from: sourceDir.path,
            to: tempDir.appendingPathComponent("dest-minified").path
        )

        XCTAssertNotEqual(
            plainManifest["style.css"],
            minifiedManifest["style.css"],
            "最小化でバイト列が変わったのにハッシュが同じなのは、ソースをハッシュしている証拠"
        )
    }

    func testJSFingerprintCoversTheMinifiedBytesNotTheSource() throws {
        // CSS 側は `testFingerprintCoversTheProcessedBytesNotTheSource` で固定済み。JS も同じ
        // 性質（ハッシュは最小化後のバイト列に対して取られる）を持つはずだが、そちらは
        // 未検証だった。同じソースを最小化あり・なしで処理し、出力名のハッシュが違うことと、
        // そのハッシュが実際にディスクへ書いたバイト列と一致することの両方を確かめる。
        let sourceDir = tempDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let jsContent = """
        function greet() {
            console.log("hello");
        }
        """
        try jsContent.write(
            to: sourceDir.appendingPathComponent("app.js"),
            atomically: true,
            encoding: .utf8
        )

        let plain = AssetPipeline()
        plain.enableFingerprinting = true
        let plainDest = tempDir.appendingPathComponent("dest-plain-js")
        let plainManifest = try plain.processAssets(from: sourceDir.path, to: plainDest.path)

        let minified = AssetPipeline()
        minified.enableFingerprinting = true
        minified.jsOptions.minify = true
        let minifiedDest = tempDir.appendingPathComponent("dest-minified-js")
        let minifiedManifest = try minified.processAssets(from: sourceDir.path, to: minifiedDest.path)

        XCTAssertNotEqual(
            plainManifest["app.js"],
            minifiedManifest["app.js"],
            "最小化でバイト列が変わったのにハッシュが同じなのは、ソースをハッシュしている証拠"
        )

        let minifiedPath = try XCTUnwrap(minifiedManifest["app.js"])
        let bytesOnDisk = try Data(contentsOf: minifiedDest.appendingPathComponent(minifiedPath))
        let expectedFingerprint = AssetProcessor().generateFingerprint(for: bytesOnDisk)
        XCTAssertEqual(
            minifiedPath, "app-\(expectedFingerprint).js",
            "出力名 \(minifiedPath) が実際に書き込んだバイト列のハッシュ \(expectedFingerprint) から作られる正確な名前と一致しない"
        )
    }

    func testCSSHashCoversTheRewrittenBytes() throws {
        // CSS が参照する画像の中身だけを変える。画像のハッシュが変われば、書き換え後の CSS の
        // バイト列も変わり、CSS 自身のハッシュも変わらなければならない。
        func build(imageBytes: Data, into name: String) throws -> AssetManifest {
            let sourceDir = tempDir.appendingPathComponent("source-\(name)")
            try FileManager.default.createDirectory(
                at: sourceDir.appendingPathComponent("css"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: sourceDir.appendingPathComponent("images"),
                withIntermediateDirectories: true
            )
            try "body{background:url(../images/bg.png)}".write(
                to: sourceDir.appendingPathComponent("css/style.css"),
                atomically: true,
                encoding: .utf8
            )
            try imageBytes.write(to: sourceDir.appendingPathComponent("images/bg.png"))

            let pipeline = AssetPipeline()
            pipeline.enableFingerprinting = true
            return try pipeline.processAssets(
                from: sourceDir.path,
                to: tempDir.appendingPathComponent("dest-\(name)").path
            )
        }

        let first = try build(imageBytes: Data("one".utf8), into: "first")
        let second = try build(imageBytes: Data("two".utf8), into: "second")

        XCTAssertNotEqual(first["images/bg.png"], second["images/bg.png"], "前提: 画像のハッシュは変わる")
        XCTAssertNotEqual(
            first["css/style.css"],
            second["css/style.css"],
            "CSS のハッシュは url(...) を書き換えた後のバイト列に対して取られるべき"
        )
    }

    func testExcludedAssetIsWrittenUnderItsOriginalNameAndMapsToItself() throws {
        // robots.txt はどのページからも参照されないため、フィンガープリントすると404になる。
        // `AssetFingerprintExclusions` の組み込みパターンで常に除外されるべき。
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        pipeline.enableFingerprinting = true
        try "User-agent: *\n".write(
            to: sourceDir.appendingPathComponent("robots.txt"),
            atomically: true,
            encoding: .utf8
        )

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        XCTAssertEqual(manifest["robots.txt"], "robots.txt", "除外されたアセットはキー == 値のままであるべき")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: destDir.appendingPathComponent("robots.txt").path),
            "除外されたアセットは元の名前で書き出されるべき"
        )
    }

    func testExcludedAssetDoesNotPreventOrdinaryAssetsFromBeingFingerprinted() throws {
        // 同じビルドの中で、除外されないアセット（css/style.css）は通常どおりハッシュされる。
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent("css"),
            withIntermediateDirectories: true
        )

        pipeline.enableFingerprinting = true
        try "User-agent: *\n".write(
            to: sourceDir.appendingPathComponent("robots.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "body{}".write(
            to: sourceDir.appendingPathComponent("css/style.css"),
            atomically: true,
            encoding: .utf8
        )

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        XCTAssertEqual(manifest["robots.txt"], "robots.txt")
        let hashedStylesheet = try XCTUnwrap(manifest["css/style.css"])
        XCTAssertNotEqual(hashedStylesheet, "css/style.css", "除外対象ではないアセットはハッシュされるべき")
    }

    func testWriteGuardHonoursANonBuiltInExclusionPattern() throws {
        // このテストは `AssetPipeline` 単体の話であり、`config.assets.fingerprintExclude` から
        // `assetPipeline.fingerprintExclusions` への配線（`SiteGenerator.configureAssetPipeline`）
        // は検証しない ── そちらは `AssetFingerprintIntegrationTests.
        // testConfigSuppliedFingerprintExcludePatternExemptsAFileEndToEnd` が担う。ここで
        // 固定するのは、`write()` の除外判定が組み込みパターンだけでなく
        // `fingerprintExclusions` にセットされた任意のパターンにも従うこと。
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        pipeline.enableFingerprinting = true
        pipeline.fingerprintExclusions = AssetFingerprintExclusions(additional: ["keep-name.txt"])
        try "pinned".write(
            to: sourceDir.appendingPathComponent("keep-name.txt"),
            atomically: true,
            encoding: .utf8
        )

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        XCTAssertEqual(manifest["keep-name.txt"], "keep-name.txt")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: destDir.appendingPathComponent("keep-name.txt").path)
        )
    }

    func testResolvesACSSToCSSReferenceByProcessingDependenciesFirst() throws {
        // 参照される側のスタイルシートを先に処理すれば、参照する側はそのハッシュ名を書ける。
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        pipeline.enableFingerprinting = true

        try "@import url(\"theme.css\");\nbody { color: red; }".write(
            to: sourceDir.appendingPathComponent("style.css"),
            atomically: true,
            encoding: .utf8
        )
        try "body { margin: 0; }".write(
            to: sourceDir.appendingPathComponent("theme.css"),
            atomically: true,
            encoding: .utf8
        )

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        let themeOutput = try XCTUnwrap(manifest["theme.css"])
        XCTAssertNotEqual(themeOutput, "theme.css", "前提: theme.css はハッシュ名になる")

        let styleOutput = try XCTUnwrap(manifest["style.css"])
        let content = try String(contentsOf: destDir.appendingPathComponent(styleOutput), encoding: .utf8)
        XCTAssertTrue(
            content.contains("url(\"\(themeOutput)\")"),
            "CSS→CSS参照は書き換えられるべき。実際: \(content)"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent(themeOutput).path))
    }

    func testResolvesABareCSSImport() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        pipeline.enableFingerprinting = true

        try "@import \"theme.css\";\nbody { color: red; }".write(
            to: sourceDir.appendingPathComponent("style.css"),
            atomically: true,
            encoding: .utf8
        )
        try "body { margin: 0; }".write(
            to: sourceDir.appendingPathComponent("theme.css"),
            atomically: true,
            encoding: .utf8
        )

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        let themeOutput = try XCTUnwrap(manifest["theme.css"])
        let styleOutput = try XCTUnwrap(manifest["style.css"])
        let content = try String(contentsOf: destDir.appendingPathComponent(styleOutput), encoding: .utf8)
        XCTAssertTrue(content.contains("\"\(themeOutput)\""), "実際: \(content)")
    }

    func testCyclicCSSImportsKeepTheirOriginalNames() throws {
        // 互いに参照しあう CSS はどちらを先に処理してもハッシュ名を確定できない。参照が壊れる
        // くらいならフィンガープリントを諦めて、元の名前のまま出力する。
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        pipeline.enableFingerprinting = true

        try "@import \"b.css\";\na { color: red; }".write(
            to: sourceDir.appendingPathComponent("a.css"),
            atomically: true,
            encoding: .utf8
        )
        try "@import \"a.css\";\nb { color: blue; }".write(
            to: sourceDir.appendingPathComponent("b.css"),
            atomically: true,
            encoding: .utf8
        )

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        XCTAssertEqual(manifest["a.css"], "a.css")
        XCTAssertEqual(manifest["b.css"], "b.css")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("a.css").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("b.css").path))

        let a = try String(contentsOf: destDir.appendingPathComponent("a.css"), encoding: .utf8)
        XCTAssertTrue(a.contains("\"b.css\""), "参照は元の名前のまま残るべき。実際: \(a)")
    }

    func testACSSFileThatImportsItselfKeepsItsOriginalName() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        pipeline.enableFingerprinting = true
        try "@import \"loop.css\";\nbody{}".write(
            to: sourceDir.appendingPathComponent("loop.css"),
            atomically: true,
            encoding: .utf8
        )

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        XCTAssertEqual(manifest["loop.css"], "loop.css")
    }

    func testManifestPointsAtTheFileThatWasActuallyWritten() throws {
        // 出力ツリーの中にシンボリックリンクがあると、書き込み先はソースの相対パスからは
        // 導けない。マニフェストの値は実際に書いた場所でなければ、書き換えた参照が 404 になる。
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent("images"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destDir.appendingPathComponent("cache"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destDir.appendingPathComponent("images"),
            withIntermediateDirectories: true
        )
        try Data("icon".utf8).write(to: destDir.appendingPathComponent("cache/icon.png"))
        try FileManager.default.createSymbolicLink(
            at: destDir.appendingPathComponent("images/logo.png"),
            withDestinationURL: destDir.appendingPathComponent("cache/icon.png")
        )

        pipeline.enableFingerprinting = true
        try Data("logo".utf8).write(to: sourceDir.appendingPathComponent("images/logo.png"))

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        let value = try XCTUnwrap(manifest["images/logo.png"])
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: destDir.appendingPathComponent(value).path),
            "マニフェストの値が実在しない: \(value)"
        )
    }

    // MARK: - 固定 URL のアセット

    func testKeepsFixedUrlAssetsUnfingerprinted() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent(".well-known/acme-challenge"),
            withIntermediateDirectories: true
        )
        pipeline.enableFingerprinting = true

        try "User-agent: *".write(
            to: sourceDir.appendingPathComponent("robots.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "example.com".write(
            to: sourceDir.appendingPathComponent("CNAME"),
            atomically: true,
            encoding: .utf8
        )
        try "token".write(
            to: sourceDir.appendingPathComponent(".well-known/acme-challenge/abc123"),
            atomically: true,
            encoding: .utf8
        )

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        for path in ["robots.txt", "CNAME", ".well-known/acme-challenge/abc123"] {
            XCTAssertEqual(manifest[path], path, "\(path) は元の名前で出力されるべき")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: destDir.appendingPathComponent(path).path),
                "\(path) が元の名前で存在しない"
            )
        }
    }

    func testExcludesAFixedUrlNameAtAnyDepth() throws {
        // 組み込みパターンはファイル名だけで照合する（`/` を含まないため）。`.htaccess` は
        // Apache が各ディレクトリで読み、`sw.js` は JavaScript 内の固定 URL で登録されるので、
        // ルート直下に限ると取りこぼす。壊れる側に倒すより、ハッシュを諦める側に倒す。
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent("docs"),
            withIntermediateDirectories: true
        )
        pipeline.enableFingerprinting = true
        try "User-agent: *".write(
            to: sourceDir.appendingPathComponent("docs/robots.txt"),
            atomically: true,
            encoding: .utf8
        )

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        XCTAssertEqual(manifest["docs/robots.txt"], "docs/robots.txt")
    }

    // MARK: - シンボリックリンク

    /// 列挙時の閉じ込め判定を通ったリンクが、読まれる前に `static/` の外へ向け直される
    /// check-to-use 競合。パススルーアセットの経路。
    func testALinkRetargetedOutsideAfterEnumerationIsRefusedAtReadTime() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let insideTarget = sourceDir.appendingPathComponent("inside.png")
        try Data("inside".utf8).write(to: insideTarget)
        let outsideTarget = tempDir.appendingPathComponent("secret.png")
        try Data("secret".utf8).write(to: outsideTarget)

        let link = sourceDir.appendingPathComponent("logo.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: insideTarget)

        let hooked = HookedAssetPipeline()
        hooked.beforeResolving = { fileURL in
            guard fileURL.lastPathComponent == "logo.png" else { return }
            try FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideTarget)
        }

        XCTAssertThrowsError(
            try hooked.processAssets(from: sourceDir.path, to: destDir.path),
            "列挙後に外へ向け直されたリンクが読まれている"
        ) { error in
            guard case AssetPipelineError.pathTraversalAttempt = error else {
                return XCTFail("pathTraversalAttempt 以外のエラー: \(error)")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destDir.appendingPathComponent("logo.png").path),
            "static/ の外の中身が出力に書き出された"
        )
    }

    /// 同じ競合の CSS 経路。CSS は列挙（パス1）と読み込み（パス2）が離れているので、
    /// この窓は実際に広い。
    func testAStylesheetLinkRetargetedOutsideBetweenPassesIsRefused() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let insideTarget = sourceDir.appendingPathComponent("inside.css")
        try "body{}".write(to: insideTarget, atomically: true, encoding: .utf8)
        let outsideTarget = tempDir.appendingPathComponent("secret.css")
        try "/* secret */".write(to: outsideTarget, atomically: true, encoding: .utf8)

        let link = sourceDir.appendingPathComponent("style.css")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: insideTarget)

        let hooked = HookedAssetPipeline()
        hooked.beforeResolving = { fileURL in
            guard fileURL.lastPathComponent == "style.css" else { return }
            try FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideTarget)
        }

        XCTAssertThrowsError(try hooked.processAssets(from: sourceDir.path, to: destDir.path))
        let output = destDir.appendingPathComponent("style.css")
        if FileManager.default.fileExists(atPath: output.path) {
            XCTAssertNotEqual(
                try String(contentsOf: output, encoding: .utf8), "/* secret */",
                "static/ の外の中身が出力に書き出された"
            )
        }
    }

    /// 閉じ込め判定は通ったが、コピーの前にソースが書き換えられた。ハッシュ計算とコピーが
    /// 別々にソースを読む構造だと、出力名のハッシュと実データが食い違う。判定直後の識別情報と
    /// コピー直後の識別情報を比べて、変わっていたら失敗させる。
    func testASourceModifiedAfterItsContainmentCheckFailsTheCopy() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let sourceFile = sourceDir.appendingPathComponent("logo.png")
        try Data("original".utf8).write(to: sourceFile)

        let hooked = HookedAssetPipeline()
        hooked.enableFingerprinting = true
        hooked.afterResolving = { fileURL in
            guard fileURL.lastPathComponent == "logo.png" else { return }
            let handle = try FileHandle(forWritingTo: sourceFile)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(" + appended".utf8))
            try handle.close()
        }

        XCTAssertThrowsError(
            try hooked.processAssets(from: sourceDir.path, to: destDir.path),
            "判定後に書き換えられたソースがそのままコピーされている"
        ) { error in
            XCTAssertTrue(
                "\(error)".contains("changed while it was being copied"),
                "想定外のエラー: \(error)"
            )
        }

        // 失敗したときにステージングファイルが残っていないこと。
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            .filter { $0.hasPrefix(".hirundo-") }
        XCTAssertTrue(leftovers.isEmpty, "ステージングファイルが残っている: \(leftovers)")
    }

    /// ハッシュはステージングファイル（差し替えるバイト列そのもの）から取る。ソースを2回読む
    /// 構造ではないことを、出力名のハッシュ＝出力バイト列のハッシュで固定する。
    func testPassThroughFingerprintCoversTheBytesActuallyWritten() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let content = Data("pass-through bytes".utf8)
        try content.write(to: sourceDir.appendingPathComponent("logo.png"))

        pipeline.enableFingerprinting = true
        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        let outputRelativePath = try XCTUnwrap(manifest["logo.png"])
        let written = try Data(contentsOf: destDir.appendingPathComponent(outputRelativePath))
        XCTAssertEqual(
            outputRelativePath,
            "logo-\(AssetProcessor().generateFingerprint(for: written)).png",
            "出力名のハッシュが出力バイト列のハッシュと一致しない"
        )
    }

    func testSkipsAFileSymlinkPointingOutsideTheSourceDirectory() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        let outside = tempDir.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let secret = outside.appendingPathComponent("secret.txt")
        try "SECRET".write(to: secret, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: sourceDir.appendingPathComponent("leak.txt"),
            withDestinationURL: secret
        )

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        XCTAssertNil(manifest["leak.txt"], "外を指すリンクはマニフェストに載せない")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destDir.appendingPathComponent("leak.txt").path),
            "リンク先の中身が出力へコピーされてはならない"
        )
    }

    func testSkipsADirectorySymlinkPointingOutsideTheSourceDirectory() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        let outside = tempDir.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "SECRET".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)

        try FileManager.default.createSymbolicLink(
            at: sourceDir.appendingPathComponent("vendor"),
            withDestinationURL: outside
        )

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        XCTAssertNil(manifest["vendor/secret.txt"])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destDir.appendingPathComponent("vendor/secret.txt").path)
        )
    }

    func testFollowsASymlinkThatStaysInsideTheSourceDirectory() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let real = sourceDir.appendingPathComponent("real.txt")
        try "inside".write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: sourceDir.appendingPathComponent("alias.txt"),
            withDestinationURL: real
        )

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        XCTAssertEqual(manifest["alias.txt"], "alias.txt")
        XCTAssertEqual(
            try String(contentsOf: destDir.appendingPathComponent("alias.txt"), encoding: .utf8),
            "inside"
        )
    }
}

// (Plugin-based test helpers removed in Stage 2)

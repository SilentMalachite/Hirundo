import XCTest
@testable import HirundoCore

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
            ("style.css", AssetItem.AssetType.css),
            ("app.js", AssetItem.AssetType.javascript),
            ("logo.png", AssetItem.AssetType.image("png")),
            ("banner.jpg", AssetItem.AssetType.image("jpg")),
            ("readme.txt", AssetItem.AssetType.other("txt"))
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
}

// (Plugin-based test helpers removed in Stage 2)

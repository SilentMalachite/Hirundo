import XCTest
@testable import HirundoCore

final class AssetPipelineTests: XCTestCase {
    
    var tempDir: URL!
    var pipeline: AssetPipeline!
    var pluginManager: PluginManager!
    
    override func setUp() {
        super.setUp()
        
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("asset-pipeline-test-\(UUID())")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        pluginManager = PluginManager()
        pipeline = AssetPipeline(pluginManager: pluginManager)
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
        try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
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
        try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
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
        // Register minify plugin
        let minifyPlugin = TestMinifyPlugin()
        try pluginManager.register(minifyPlugin)
        try pluginManager.initializeAll(context: PluginContext(
            projectPath: tempDir.path,
            config: HirundoConfig(site: Site(title: "Test", url: "https://example.com"))
        ))
        
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
        try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
        // Verify minification
        let processedCSS = try String(contentsOf: destDir.appendingPathComponent("style.css"), encoding: .utf8)
        XCTAssertFalse(processedCSS.contains("\n"))
        XCTAssertTrue(processedCSS.contains("body{"))
    }
    
    func testAssetFingerprinting() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // Enable fingerprinting
        pipeline.enableFingerprinting = true
        
        // Create test file
        let cssFile = sourceDir.appendingPathComponent("style.css")
        let cssContent = "body { color: blue; }"
        try cssContent.write(to: cssFile, atomically: true, encoding: .utf8)
        
        // Process assets
        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
        // Verify fingerprinted file exists
        XCTAssertNotNil(manifest["style.css"])
        let fingerprintedName = manifest["style.css"]!
        XCTAssertTrue(fingerprintedName.contains("-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent(fingerprintedName).path))
        
        // Verify original content
        let processedContent = try String(contentsOf: destDir.appendingPathComponent(fingerprintedName), encoding: .utf8)
        XCTAssertEqual(processedContent, cssContent)
    }
    
    func testAssetManifest() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        pipeline.enableFingerprinting = true
        
        // Create multiple assets
        try "body{}".write(to: sourceDir.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        try "console.log(1)".write(to: sourceDir.appendingPathComponent("app.js"), atomically: true, encoding: .utf8)
        
        // Process assets
        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
        // Verify manifest
        XCTAssertEqual(manifest.count, 2)
        XCTAssertNotNil(manifest["style.css"])
        XCTAssertNotNil(manifest["app.js"])
        
        // Save and load manifest
        let manifestPath = destDir.appendingPathComponent("asset-manifest.json")
        try pipeline.saveManifest(manifest, to: manifestPath.path)
        
        let loadedManifest = try pipeline.loadManifest(from: manifestPath.path)
        XCTAssertEqual(loadedManifest, manifest)
    }
    
    func testAssetConcatenation() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        let jsDir = sourceDir.appendingPathComponent("js")
        try FileManager.default.createDirectory(at: jsDir, withIntermediateDirectories: true)
        
        // Create multiple JS files
        try "var a = 1;".write(to: jsDir.appendingPathComponent("1.js"), atomically: true, encoding: .utf8)
        try "var b = 2;".write(to: jsDir.appendingPathComponent("2.js"), atomically: true, encoding: .utf8)
        try "var c = 3;".write(to: jsDir.appendingPathComponent("3.js"), atomically: true, encoding: .utf8)
        
        // Configure concatenation
        pipeline.concatenationRules = [
            AssetConcatenationRule(
                pattern: "js/*.js",
                output: "js/bundle.js",
                separator: "\n"
            )
        ]
        
        // Process assets
        try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
        // Verify concatenated file
        let bundlePath = destDir.appendingPathComponent("js/bundle.js")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundlePath.path))
        
        let bundleContent = try String(contentsOf: bundlePath, encoding: .utf8)
        XCTAssertTrue(bundleContent.contains("var a = 1;"))
        XCTAssertTrue(bundleContent.contains("var b = 2;"))
        XCTAssertTrue(bundleContent.contains("var c = 3;"))
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
        try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
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
        try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
        // Verify only non-excluded files were copied
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("style.css").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("temp.tmp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.appendingPathComponent(".hidden").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("_draft.css").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destDir.appendingPathComponent("debug.log").path))
    }
    
    func testAssetPipelineIntegration() throws {
        // Test the full pipeline with multiple plugins
        let minifyPlugin = TestMinifyPlugin()
        let optimizePlugin = TestOptimizePlugin()
        
        try pluginManager.register(minifyPlugin)
        try pluginManager.register(optimizePlugin)
        try pluginManager.initializeAll(context: PluginContext(
            projectPath: tempDir.path,
            config: HirundoConfig(site: Site(title: "Test", url: "https://example.com"))
        ))
        
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // Create test assets
        try "body { margin: 0; }".write(to: sourceDir.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        try "function test() { return true; }".write(to: sourceDir.appendingPathComponent("script.js"), atomically: true, encoding: .utf8)
        
        // Process with all features enabled
        pipeline.enableFingerprinting = true
        pipeline.enableSourceMaps = true
        
        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        
        // Verify processing
        XCTAssertEqual(manifest.count, 2)
        XCTAssertTrue(minifyPlugin.processedAssets.count > 0)
        XCTAssertTrue(optimizePlugin.processedAssets.count > 0)
    }
}

// Test plugin implementations

class TestMinifyPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "TestMinifyPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Test minification"
    )
    
    var processedAssets: [String] = []
    
    required init() {}
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func processAsset(_ asset: AssetItem) throws -> AssetItem {
        processedAssets.append(asset.sourcePath)
        
        var processed = asset
        
        if asset.type == .css {
            let content = try String(contentsOfFile: asset.sourcePath, encoding: .utf8)
            let minified = content
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "  ", with: "")
                .replacingOccurrences(of: " {", with: "{")
                .replacingOccurrences(of: ": ", with: ":")
                .replacingOccurrences(of: "; ", with: ";")
            
            try minified.write(toFile: asset.outputPath, atomically: true, encoding: .utf8)
            processed.processed = true
            processed.metadata["minified"] = true
        }
        
        return processed
    }
}

class TestOptimizePlugin: Plugin {
    let metadata = PluginMetadata(
        name: "TestOptimizePlugin",
        version: "1.0.0",
        author: "Test",
        description: "Test optimization"
    )
    
    var processedAssets: [String] = []
    
    required init() {}
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func processAsset(_ asset: AssetItem) throws -> AssetItem {
        processedAssets.append(asset.sourcePath)
        return asset
    }
}


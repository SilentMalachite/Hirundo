import XCTest
@testable import HirundoCore

final class AssetPrunerTests: XCTestCase {

    private var tempDir: URL!
    private var outputDir: URL!
    private var staticDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("asset-pruner-test-\(UUID().uuidString)")
        outputDir = tempDir.appendingPathComponent("_site")
        staticDir = tempDir.appendingPathComponent("static")
        try? FileManager.default.createDirectory(at: staticDir.appendingPathComponent("css"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: outputDir.appendingPathComponent("css"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func write(_ contents: String, to relativePath: String, under root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(relativePath).path)
    }

    // MARK: - 名前の判定

    func testRecognizesFingerprintedNames() {
        XCTAssertTrue(AssetPruner.isFingerprintedName("style-9f2a1c04b7e3d5a1.css"))
        XCTAssertTrue(AssetPruner.isFingerprintedName("my-logo-1b4d0f77c2ae8e93.png"))
    }

    func testRejectsNonFingerprintedNames() {
        XCTAssertFalse(AssetPruner.isFingerprintedName("style.css"))
        XCTAssertFalse(AssetPruner.isFingerprintedName("index.html"))
        XCTAssertFalse(AssetPruner.isFingerprintedName("sitemap.xml"))
        XCTAssertFalse(AssetPruner.isFingerprintedName("my-logo.png"), "ハッシュが16桁でない")
        XCTAssertFalse(AssetPruner.isFingerprintedName("style-9F2A1C04B7E3D5A1.css"), "大文字は使わない")
        XCTAssertFalse(AssetPruner.isFingerprintedName("style-9f2a1c04b7e3d5a1"), "拡張子が無い")
        XCTAssertFalse(AssetPruner.isFingerprintedName("style-zzzzzzzzzzzzzzzz.css"), "16進数でない")
    }

    // MARK: - 削除

    func testRemovesStaleFingerprintedAsset() throws {
        try write("old", to: "css/style-0000000000000000.css", under: outputDir)
        try write("new", to: "css/style-9f2a1c04b7e3d5a1.css", under: outputDir)

        try AssetPruner.prune(
            outputDirectory: outputDir,
            staticDirectory: staticDir,
            keeping: AssetManifest(["css/style.css": "css/style-9f2a1c04b7e3d5a1.css"])
        )

        XCTAssertFalse(exists("css/style-0000000000000000.css"))
        XCTAssertTrue(exists("css/style-9f2a1c04b7e3d5a1.css"))
    }

    func testKeepsNonFingerprintedFilesInScope() throws {
        try write("keep", to: "css/README.txt", under: outputDir)

        try AssetPruner.prune(
            outputDirectory: outputDir,
            staticDirectory: staticDir,
            keeping: AssetManifest()
        )

        XCTAssertTrue(exists("css/README.txt"))
    }

    func testKeepsPageOutputThatCollidesWithAStaticTopLevelName() throws {
        // content/css/foo.md が _site/css/foo/index.html を生む場合。フィンガープリント名では
        // ないので、掃除の対象にならない。
        try write("<html></html>", to: "css/foo/index.html", under: outputDir)

        try AssetPruner.prune(
            outputDirectory: outputDir,
            staticDirectory: staticDir,
            keeping: AssetManifest()
        )

        XCTAssertTrue(exists("css/foo/index.html"))
    }

    func testDoesNotTouchAnythingOutsideStaticTopLevelNames() throws {
        try write("<html></html>", to: "index.html", under: outputDir)
        try write("<urlset/>", to: "sitemap.xml", under: outputDir)
        // static/ に posts/ は無いので、_site/posts は対象外。
        try write("stale", to: "posts/orphan-0000000000000000.css", under: outputDir)

        try AssetPruner.prune(
            outputDirectory: outputDir,
            staticDirectory: staticDir,
            keeping: AssetManifest()
        )

        XCTAssertTrue(exists("index.html"))
        XCTAssertTrue(exists("sitemap.xml"))
        XCTAssertTrue(exists("posts/orphan-0000000000000000.css"))
    }

    func testPrunesATopLevelFileFromStatic() throws {
        try "User-agent: *".write(to: staticDir.appendingPathComponent("robots.txt"), atomically: true, encoding: .utf8)
        try write("stale", to: "robots-0000000000000000.txt", under: outputDir)

        try AssetPruner.prune(
            outputDirectory: outputDir,
            staticDirectory: staticDir,
            keeping: AssetManifest(["robots.txt": "robots-9f2a1c04b7e3d5a1.txt"])
        )

        XCTAssertFalse(exists("robots-0000000000000000.txt"))
    }
}

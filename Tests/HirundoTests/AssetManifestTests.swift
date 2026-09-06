import XCTest
@testable import HirundoCore

final class AssetManifestTests: XCTestCase {

    private let manifest = AssetManifest([
        "css/style.css": "css/style-9f2a1c04b7e3d5a1.css",
        "images/logo.png": "images/logo-1b4d0f77c2ae8e93.png",
        "robots.txt": "robots.txt"
    ])

    // MARK: - ルート絶対参照

    func testRewritesRootRelativeReference() {
        XCTAssertEqual(
            manifest.rewrite(reference: "/css/style.css", inDirectory: ""),
            "/css/style-9f2a1c04b7e3d5a1.css"
        )
    }

    func testRootRelativeReferenceIsIndependentOfTheReferringDirectory() {
        XCTAssertEqual(
            manifest.rewrite(reference: "/css/style.css", inDirectory: "posts/hello"),
            "/css/style-9f2a1c04b7e3d5a1.css"
        )
    }

    // MARK: - 相対参照

    func testRewritesRelativeReferenceAndKeepsItRelative() {
        XCTAssertEqual(
            manifest.rewrite(reference: "../../css/style.css", inDirectory: "posts/hello"),
            "../../css/style-9f2a1c04b7e3d5a1.css"
        )
    }

    func testRewritesSiblingRelativeReference() {
        XCTAssertEqual(
            manifest.rewrite(reference: "logo.png", inDirectory: "images"),
            "logo-1b4d0f77c2ae8e93.png"
        )
    }

    func testResolvesDotSegments() {
        XCTAssertEqual(
            manifest.rewrite(reference: "./logo.png", inDirectory: "images"),
            "logo-1b4d0f77c2ae8e93.png"
        )
    }

    func testRewritesRelativeReferenceResolvedFromTheOutputRoot() {
        // `directory` が空文字列（出力ルート直下のページから）でも、プレーンな相対参照は
        // 通常どおり解決されるべき。ルート絶対参照（`/images/logo.png`）とは別の経路。
        XCTAssertEqual(
            manifest.rewrite(reference: "images/logo.png", inDirectory: ""),
            "images/logo-1b4d0f77c2ae8e93.png"
        )
    }

    func testSkipsReferenceThatEscapesTheOutputRoot() {
        XCTAssertNil(manifest.rewrite(reference: "../../../etc/passwd", inDirectory: "css"))
    }

    // MARK: - クエリとフラグメント

    func testKeepsQueryString() {
        XCTAssertEqual(
            manifest.rewrite(reference: "/css/style.css?v=1", inDirectory: ""),
            "/css/style-9f2a1c04b7e3d5a1.css?v=1"
        )
    }

    func testKeepsFragment() {
        XCTAssertEqual(
            manifest.rewrite(reference: "/images/logo.png#icon", inDirectory: ""),
            "/images/logo-1b4d0f77c2ae8e93.png#icon"
        )
    }

    // MARK: - 触らない参照

    func testSkipsAbsoluteURLs() {
        XCTAssertNil(manifest.rewrite(reference: "https://cdn.example.com/css/style.css", inDirectory: ""))
        XCTAssertNil(manifest.rewrite(reference: "http://example.com/css/style.css", inDirectory: ""))
    }

    func testSkipsProtocolRelativeURLs() {
        XCTAssertNil(manifest.rewrite(reference: "//cdn.example.com/css/style.css", inDirectory: ""))
    }

    func testSkipsDataAndMailtoURLs() {
        XCTAssertNil(manifest.rewrite(reference: "data:text/css,body{}", inDirectory: ""))
        XCTAssertNil(manifest.rewrite(reference: "mailto:someone@example.com", inDirectory: ""))
    }

    func testSkipsFragmentOnlyReference() {
        XCTAssertNil(manifest.rewrite(reference: "#main", inDirectory: ""))
    }

    func testSkipsEmptyReference() {
        XCTAssertNil(manifest.rewrite(reference: "", inDirectory: ""))
    }

    func testSkipsUnknownReference() {
        XCTAssertNil(manifest.rewrite(reference: "/css/missing.css", inDirectory: ""))
    }

    func testSkipsEntryWhoseValueEqualsItsKey() {
        // フィンガープリント無効時はすべての値がキーと等しくなる。書き換えは no-op であるべき。
        XCTAssertNil(manifest.rewrite(reference: "/robots.txt", inDirectory: ""))
    }

    // MARK: - 補助

    func testParentDirectory() {
        XCTAssertEqual(AssetManifest.parentDirectory(of: "css/style.css"), "css")
        XCTAssertEqual(AssetManifest.parentDirectory(of: "a/b/c.png"), "a/b")
        XCTAssertEqual(AssetManifest.parentDirectory(of: "robots.txt"), "")
    }

    func testOutputPaths() {
        XCTAssertEqual(
            manifest.outputPaths,
            ["css/style-9f2a1c04b7e3d5a1.css", "images/logo-1b4d0f77c2ae8e93.png", "robots.txt"]
        )
    }

    func testRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(manifest)
        XCTAssertEqual(try JSONDecoder().decode(AssetManifest.self, from: data), manifest)
    }
}

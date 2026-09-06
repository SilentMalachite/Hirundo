import XCTest
@testable import HirundoCore

/// 1.1.x の利用者が書いていた形がそのままコンパイルできること。
///
/// `AssetItem` は deprecated なので、このテスト自身にも `@available(*, deprecated)` を付けて
/// 警告を抑える（警告付きで通ることが、このシムの意図そのもの）。
final class AssetItemCompatibilityTests: XCTestCase {

    @available(*, deprecated)
    func testNestedAssetTypeIsTheTopLevelAssetType() {
        let nested: AssetItem.AssetType = .image("png")
        let topLevel: AssetType = nested
        XCTAssertEqual(topLevel, .image("png"))
        XCTAssertEqual(nested, AssetPipeline().detectAssetType(for: "logo.png"))
    }

    @available(*, deprecated)
    func testAssetItemStillConstructs() {
        let item = AssetItem(sourcePath: "static/a.css", outputPath: "_site/a.css", type: .css)
        XCTAssertEqual(item.sourcePath, "static/a.css")
        XCTAssertEqual(item.outputPath, "_site/a.css")
        XCTAssertEqual(item.type, .css)
        XCTAssertFalse(item.processed)
        XCTAssertTrue(item.metadata.isEmpty)
    }
}

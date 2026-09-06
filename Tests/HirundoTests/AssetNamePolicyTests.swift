import XCTest
@testable import HirundoCore

final class AssetNamePolicyTests: XCTestCase {

    func testRootLevelFixedUrlNamesRequireAStableName() {
        for name in [
            "robots.txt",
            "sitemap.xml",
            "favicon.ico",
            "CNAME",
            "_redirects",
            "_headers",
            "ads.txt",
            "app-ads.txt",
            "sw.js",
            "service-worker.js"
        ] {
            XCTAssertTrue(
                AssetNamePolicy.requiresStableName(name),
                "\(name) は固定URLで取得されるためハッシュ名にしてはならない"
            )
        }
    }

    func testWellKnownRequiresAStableNameAtAnyDepth() {
        XCTAssertTrue(AssetNamePolicy.requiresStableName(".well-known/security.txt"))
        XCTAssertTrue(AssetNamePolicy.requiresStableName(".well-known/acme-challenge/tokenvalue"))
    }

    func testTheSameNameInASubdirectoryIsFingerprinted() {
        // 固定URLの契約はルート直下にしか無い。
        XCTAssertFalse(AssetNamePolicy.requiresStableName("docs/robots.txt"))
        XCTAssertFalse(AssetNamePolicy.requiresStableName("js/sw.js"))
        XCTAssertFalse(AssetNamePolicy.requiresStableName("images/favicon.ico"))
    }

    func testOrdinaryAssetsDoNotRequireAStableName() {
        XCTAssertFalse(AssetNamePolicy.requiresStableName("css/style.css"))
        XCTAssertFalse(AssetNamePolicy.requiresStableName("logo.png"))
        XCTAssertFalse(AssetNamePolicy.requiresStableName("robots.txt.bak"))
    }

    func testMatchingIsCaseSensitive() {
        // ファイル名の契約は綴りどおり。`Robots.txt` は固定URLでは取得されない。
        XCTAssertFalse(AssetNamePolicy.requiresStableName("Robots.txt"))
    }
}

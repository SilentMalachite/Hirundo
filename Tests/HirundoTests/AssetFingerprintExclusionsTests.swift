import XCTest
@testable import HirundoCore

final class AssetFingerprintExclusionsTests: XCTestCase {

    // MARK: - 組み込みパターン

    func testEveryBuiltInNameIsExcludedAtRoot() {
        let exclusions = AssetFingerprintExclusions()
        XCTAssertTrue(exclusions.excludes("robots.txt"))
        XCTAssertTrue(exclusions.excludes("favicon.ico"))
        XCTAssertTrue(exclusions.excludes("CNAME"))
        XCTAssertTrue(exclusions.excludes("_headers"))
        XCTAssertTrue(exclusions.excludes("_redirects"))
        XCTAssertTrue(exclusions.excludes(".htaccess"))
    }

    func testWellKnownDirectoryIsExcludedAtAnyDepth() {
        let exclusions = AssetFingerprintExclusions()
        XCTAssertTrue(exclusions.excludes(".well-known/security.txt"))
        XCTAssertTrue(exclusions.excludes(".well-known/acme-challenge/token"))
    }

    func testOrdinaryAssetsAreNotExcluded() {
        let exclusions = AssetFingerprintExclusions()
        XCTAssertFalse(exclusions.excludes("css/style.css"))
        XCTAssertFalse(exclusions.excludes("images/logo.png"))
        XCTAssertFalse(exclusions.excludes("robots.txt.bak"), "robots.txt の接頭辞を持つだけの別名")
    }

    // MARK: - additional パターン

    func testAdditionalPatternExcludesLiteralName() {
        let exclusions = AssetFingerprintExclusions(additional: ["ads.txt"])
        XCTAssertTrue(exclusions.excludes("ads.txt"))
        XCTAssertTrue(exclusions.excludes("vendor/ads.txt"), "スラッシュを含まないパターンは最後の要素だけを見る")
    }

    func testAdditionalWildcardPatternMatchesAtRootAndNested() {
        let exclusions = AssetFingerprintExclusions(additional: ["apple-touch-icon*.png"])
        XCTAssertTrue(exclusions.excludes("apple-touch-icon-180.png"))
        XCTAssertTrue(exclusions.excludes("icons/apple-touch-icon-180.png"))
    }

    func testAdditionalIsAdditiveNotReplacing() {
        // additional を渡しても組み込みパターンは全部残る。
        let exclusions = AssetFingerprintExclusions(additional: ["ads.txt"])
        XCTAssertTrue(exclusions.excludes("robots.txt"))
        XCTAssertTrue(exclusions.excludes("favicon.ico"))
        XCTAssertTrue(exclusions.excludes("CNAME"))
        XCTAssertTrue(exclusions.excludes("_headers"))
        XCTAssertTrue(exclusions.excludes("_redirects"))
        XCTAssertTrue(exclusions.excludes(".htaccess"))
        XCTAssertTrue(exclusions.excludes(".well-known/security.txt"))
    }

    // MARK: - `*` は `/` を跨がない

    func testStarDoesNotCrossSlash() {
        let exclusions = AssetFingerprintExclusions(additional: ["images/*.png"])
        XCTAssertTrue(exclusions.excludes("images/logo.png"))
        XCTAssertFalse(exclusions.excludes("images/icons/logo.png"), "* は1階層しかまたがない")
    }

    // MARK: - `**` はゼロ個以上のセグメントに一致する

    func testDoubleStarMatchesZeroSegments() {
        let exclusions = AssetFingerprintExclusions(additional: ["a/**/b.txt"])
        XCTAssertTrue(exclusions.excludes("a/b.txt"), "** はゼロ個のセグメントにも一致する")
        XCTAssertTrue(exclusions.excludes("a/x/y/b.txt"))
    }

    // MARK: - `/` を含むパターンは全体パスに固定される

    func testSlashContainingPatternIsAnchoredToWholePath() {
        let exclusions = AssetFingerprintExclusions(additional: ["css/style.css"])
        XCTAssertTrue(exclusions.excludes("css/style.css"))
        XCTAssertFalse(exclusions.excludes("deep/css/style.css"), "/ を含むパターンは全体パス一致のみ")
    }

    // MARK: - 空パターン

    func testEmptyPatternNeverMatches() {
        XCTAssertFalse(AssetFingerprintExclusions.matches(pattern: "", path: ""))
        XCTAssertFalse(AssetFingerprintExclusions.matches(pattern: "", path: "anything"))

        // 空パターンを additional に渡しても、組み込みパターンの判定には影響しない
        // （additional は「追加」であって「置き換え」ではない）。
        let exclusions = AssetFingerprintExclusions(additional: [""])
        XCTAssertFalse(exclusions.excludes("not-a-builtin-name"))
        XCTAssertTrue(exclusions.excludes("robots.txt"), "空パターンがあっても組み込みは効き続ける")
    }

    // MARK: - 大文字小文字を区別する

    func testMatchingIsCaseSensitive() {
        let exclusions = AssetFingerprintExclusions()
        XCTAssertFalse(exclusions.excludes("ROBOTS.TXT"))
        XCTAssertFalse(exclusions.excludes("Robots.txt"))
    }

    // MARK: - builtIn の内容そのもの

    func testBuiltInListIsExactlyTheSpecifiedSet() {
        XCTAssertEqual(
            Set(AssetFingerprintExclusions.builtIn),
            Set([
                "robots.txt",
                "favicon.ico",
                "CNAME",
                "_headers",
                "_redirects",
                ".htaccess",
                ".well-known/**",
            ])
        )
    }

    // MARK: - 追加のエッジケース

    func testDoubleStarSegmentDoesNotMatchWithoutTrailingSeparatorStructure() {
        // a/**/b.txt は a 単体や a/b/c.txt(別名) には一致しない。
        let exclusions = AssetFingerprintExclusions(additional: ["a/**/b.txt"])
        XCTAssertFalse(exclusions.excludes("a/b/c.txt"))
        XCTAssertFalse(exclusions.excludes("a"))
    }

    func testLiteralPatternWithoutSlashMatchesFileNameOnlyNotDirectory() {
        // "ads.txt" はファイル名一致であって、ディレクトリ名 "ads.txt/inside" には一致しない。
        let exclusions = AssetFingerprintExclusions(additional: ["ads.txt"])
        XCTAssertFalse(exclusions.excludes("ads.txt/inside"))
    }

    func testNoSlashWildcardMatchesLastComponentAtAnyDepth() {
        let exclusions = AssetFingerprintExclusions(additional: ["*.png"])
        XCTAssertTrue(exclusions.excludes("logo.png"))
        XCTAssertTrue(exclusions.excludes("images/logo.png"))
        XCTAssertTrue(exclusions.excludes("images/icons/logo.png"))
        XCTAssertFalse(exclusions.excludes("logo.png.bak"))
    }

    // MARK: - マッチャーそのものの直接テスト（no-slash → 最後の要素、has-slash → パス全体）

    func testMatchesDirectlyOnNoSlashPattern() {
        XCTAssertTrue(AssetFingerprintExclusions.matches(pattern: "ads.txt", path: "vendor/ads.txt"))
        XCTAssertFalse(AssetFingerprintExclusions.matches(pattern: "ads.txt", path: "ads.txt/inside"))
    }

    func testMatchesDirectlyOnSlashPattern() {
        XCTAssertTrue(AssetFingerprintExclusions.matches(pattern: "a/**/b.txt", path: "a/x/b.txt"))
        XCTAssertFalse(AssetFingerprintExclusions.matches(pattern: "css/style.css", path: "deep/css/style.css"))
    }

    func testEquatable() {
        let a = AssetFingerprintExclusions(additional: ["ads.txt"])
        let b = AssetFingerprintExclusions(additional: ["ads.txt"])
        let c = AssetFingerprintExclusions(additional: ["other.txt"])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

import XCTest
@testable import HirundoCore

final class AssetReferenceRewriterTests: XCTestCase {

    private let manifest = AssetManifest([
        "css/style.css": "css/style-9f2a1c04b7e3d5a1.css",
        "images/logo.png": "images/logo-1b4d0f77c2ae8e93.png",
        "images/bg.png": "images/bg-5c3e9a21d0f4b678.png",
        "js/app.js": "js/app-77bb1e9c4a02d3f5.js"
    ])

    // MARK: - CSS

    func testRewritesUnquotedURL() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: url(/images/bg.png); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "body { background: url(/images/bg-5c3e9a21d0f4b678.png); }")
    }

    func testRewritesDoubleQuotedURL() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: url(\"/images/bg.png\"); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "body { background: url(\"/images/bg-5c3e9a21d0f4b678.png\"); }")
    }

    func testRewritesSingleQuotedURL() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: url('/images/bg.png'); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "body { background: url('/images/bg-5c3e9a21d0f4b678.png'); }")
    }

    func testRewritesRelativeURLFromNestedStylesheet() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: url(../images/bg.png); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "body { background: url(../images/bg-5c3e9a21d0f4b678.png); }")
    }

    func testIsCaseInsensitiveAboutTheURLToken() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: URL(/images/bg.png); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "body { background: URL(/images/bg-5c3e9a21d0f4b678.png); }")
    }

    func testLeavesExternalURLAlone() {
        let css = "body { background: url(https://cdn.example.com/bg.png); }"
        XCTAssertEqual(AssetReferenceRewriter.rewriteCSS(css, manifest: manifest, inDirectory: "css").content, css)
    }

    func testLeavesDataURIAlone() {
        let css = "body { background: url(data:image/gif;base64,R0lGOD); }"
        XCTAssertEqual(AssetReferenceRewriter.rewriteCSS(css, manifest: manifest, inDirectory: "css").content, css)
    }

    func testLeavesUnknownReferenceAlone() {
        let css = "body { background: url(/images/missing.png); }"
        XCTAssertEqual(AssetReferenceRewriter.rewriteCSS(css, manifest: manifest, inDirectory: "css").content, css)
    }

    func testRewritesEveryURLInTheFile() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "a{background:url(/images/bg.png)}b{background:url(/images/logo.png)}",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(
            result.content,
            "a{background:url(/images/bg-5c3e9a21d0f4b678.png)}"
                + "b{background:url(/images/logo-1b4d0f77c2ae8e93.png)}"
        )
    }

    func testHandlesUnterminatedURLWithoutLosingContent() {
        let css = "body { background: url(/images/bg.png"
        XCTAssertEqual(AssetReferenceRewriter.rewriteCSS(css, manifest: manifest, inDirectory: "css").content, css)
    }

    // MARK: - CSS から CSS への参照

    func testReportsStylesheetReferenceItCannotResolve() {
        // パス2の時点では他の CSS はまだマニフェストに載っていない。
        let passTwoManifest = AssetManifest(["images/bg.png": "images/bg-5c3e9a21d0f4b678.png"])
        let result = AssetReferenceRewriter.rewriteCSS(
            "@import url(\"other.css\");",
            manifest: passTwoManifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "@import url(\"other.css\");", "書き換えてはならない")
        XCTAssertEqual(result.unresolvedStylesheetReferences, ["other.css"])
    }

    func testDoesNotReportUnresolvedNonStylesheetReference() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: url(/images/missing.png); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertTrue(result.unresolvedStylesheetReferences.isEmpty)
    }
}

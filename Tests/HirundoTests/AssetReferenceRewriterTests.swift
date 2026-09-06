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

    func testPreservesWhitespaceInUnquotedURL() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: url( /images/bg.png ); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "body { background: url( /images/bg-5c3e9a21d0f4b678.png ); }")
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

    // MARK: - HTML

    func testRewritesLinkHref() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<link rel=\"stylesheet\" href=\"/css/style.css\">",
                manifest: manifest,
                inDirectory: ""
            ),
            "<link rel=\"stylesheet\" href=\"/css/style-9f2a1c04b7e3d5a1.css\">"
        )
    }

    func testRewritesScriptSrc() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<script src=\"/js/app.js\"></script>",
                manifest: manifest,
                inDirectory: ""
            ),
            "<script src=\"/js/app-77bb1e9c4a02d3f5.js\"></script>"
        )
    }

    func testRewritesUnquotedAttributeValue() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML("<img src=/images/logo.png>", manifest: manifest, inDirectory: ""),
            "<img src=/images/logo-1b4d0f77c2ae8e93.png>"
        )
    }

    func testRewritesRelativeReferenceFromNestedPage() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<link href=\"../../css/style.css\">",
                manifest: manifest,
                inDirectory: "posts/hello"
            ),
            "<link href=\"../../css/style-9f2a1c04b7e3d5a1.css\">"
        )
    }

    func testLeavesAnchorHrefToAPageAlone() {
        let html = "<a href=\"/about/\">About</a>"
        XCTAssertEqual(AssetReferenceRewriter.rewriteHTML(html, manifest: manifest, inDirectory: ""), html)
    }

    func testLeavesExternalHrefAlone() {
        let html = "<a href=\"https://example.com/css/style.css\">x</a>"
        XCTAssertEqual(AssetReferenceRewriter.rewriteHTML(html, manifest: manifest, inDirectory: ""), html)
    }

    func testRewritesEverySrcsetCandidateAndKeepsDescriptors() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<img srcset=\"/images/logo.png 1x, /images/bg.png 2x\">",
                manifest: manifest,
                inDirectory: ""
            ),
            "<img srcset=\"/images/logo-1b4d0f77c2ae8e93.png 1x, /images/bg-5c3e9a21d0f4b678.png 2x\">"
        )
    }

    func testPreservesSrcsetSpacingAroundDescriptorsAndCommas() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<img srcset=\"/images/logo.png 1x , /images/bg.png   2x\">",
                manifest: manifest,
                inDirectory: ""
            ),
            "<img srcset=\"/images/logo-1b4d0f77c2ae8e93.png 1x , /images/bg-5c3e9a21d0f4b678.png   2x\">"
        )
    }

    func testRewritesURLInStyleAttribute() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<div style=\"background: url(/images/bg.png)\"></div>",
                manifest: manifest,
                inDirectory: ""
            ),
            "<div style=\"background: url(/images/bg-5c3e9a21d0f4b678.png)\"></div>"
        )
    }

    func testRewritesURLInStyleElementBody() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<style>body{background:url(/images/bg.png)}</style>",
                manifest: manifest,
                inDirectory: ""
            ),
            "<style>body{background:url(/images/bg-5c3e9a21d0f4b678.png)}</style>"
        )
    }

    func testLeavesScriptBodyAlone() {
        let html = "<script>var a = \"/images/logo.png\"; if (a<b) {}</script>"
        XCTAssertEqual(AssetReferenceRewriter.rewriteHTML(html, manifest: manifest, inDirectory: ""), html)
    }

    func testLeavesCommentsAlone() {
        let html = "<!-- <link href=\"/css/style.css\"> -->"
        XCTAssertEqual(AssetReferenceRewriter.rewriteHTML(html, manifest: manifest, inDirectory: ""), html)
    }

    func testPreservesDoctypeAndSurroundingText() {
        let html = """
        <!DOCTYPE html>
        <html><head><link href="/css/style.css"></head><body>a < b and 3 > 2</body></html>
        """
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(html, manifest: manifest, inDirectory: ""),
            html.replacingOccurrences(of: "/css/style.css", with: "/css/style-9f2a1c04b7e3d5a1.css")
        )
    }

    func testKeepsQueryStringOnAnAttribute() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<link href=\"/css/style.css?v=2\">",
                manifest: manifest,
                inDirectory: ""
            ),
            "<link href=\"/css/style-9f2a1c04b7e3d5a1.css?v=2\">"
        )
    }

    func testDoesNotRewriteJavaScriptFilesAtAll() {
        // rewriteHTML / rewriteCSS しか公開していないので、JS は呼び出し側が対象から外す。
        // ここでは HTML として渡された JS ソースが壊れないことだけを確認する。
        let js = "fetch(\"/images/logo.png\");"
        XCTAssertEqual(AssetReferenceRewriter.rewriteHTML(js, manifest: manifest, inDirectory: ""), js)
    }
}

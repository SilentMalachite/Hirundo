import XCTest
@testable import HirundoCore

final class LiveReloadScriptInjectorTests: XCTestCase {

    func testInject_whenBodyClosingTagPresent_insertsScriptBeforeIt() {
        let injector = LiveReloadScriptInjector()
        let html = "<html><body>Hello</body></html>"

        let result = injector.inject(into: html)

        guard let scriptRange = result.range(of: "<script>"),
              let bodyRange = result.range(of: "</body>") else {
            return XCTFail("expected both a <script> tag and a </body> tag in the result")
        }
        XCTAssertTrue(scriptRange.lowerBound < bodyRange.lowerBound, "script must be inserted before </body>, not after it")
        XCTAssertTrue(result.hasSuffix("</html>"), "content after </body> must be preserved")
    }

    func testInject_whenNoBodyClosingTag_appendsScriptAtEnd() {
        let injector = LiveReloadScriptInjector()
        let html = "<html><p>No body tag here</p></html>"

        let result = injector.inject(into: html)

        XCTAssertTrue(result.hasPrefix(html), "original content must be preserved before the appended script")
        XCTAssertTrue(result.contains("<script>"))
    }

    func testInject_whenBodyTagUppercase_insertsBeforeIt() {
        let injector = LiveReloadScriptInjector()
        let html = "<html><body>Hello</BODY></html>"

        let result = injector.inject(into: html)

        guard let scriptRange = result.range(of: "<script>"),
              let bodyRange = result.range(of: "</BODY>") else {
            return XCTFail("expected both a <script> tag and a </BODY> tag in the result")
        }
        XCTAssertTrue(scriptRange.lowerBound < bodyRange.lowerBound)
    }

    func testInject_whenBodyClosingTagAppearsTwice_insertsBeforeLastOccurrence() {
        let injector = LiveReloadScriptInjector()
        let html = "<html><body>First</body><body>Second</body></html>"

        let result = injector.inject(into: html)

        // Exactly one <script> tag, and it must sit before the *last* </body>.
        let scriptOccurrences = result.components(separatedBy: "<script>").count - 1
        XCTAssertEqual(scriptOccurrences, 1)

        guard let scriptRange = result.range(of: "<script>"),
              let lastBodyRange = result.range(of: "</body>", options: .backwards) else {
            return XCTFail("expected a <script> tag and a </body> tag")
        }
        XCTAssertTrue(scriptRange.lowerBound < lastBodyRange.lowerBound)

        // The first </body> (from "First") must remain untouched before the script.
        XCTAssertTrue(result.hasPrefix("<html><body>First</body>"))
    }

    func testInject_whenHTMLIsEmpty_returnsOnlyScript() {
        let injector = LiveReloadScriptInjector()

        let result = injector.inject(into: "")

        XCTAssertTrue(result.contains("<script>"))
        XCTAssertTrue(result.contains("</script>"))
        XCTAssertFalse(result.contains("</body>"))
    }

    func testInject_whenDefaultEndpointPath_scriptContainsDefaultPath() {
        let injector = LiveReloadScriptInjector()

        let result = injector.inject(into: "")

        XCTAssertTrue(result.contains("/livereload"))
    }

    func testInject_whenCustomEndpointPathGiven_scriptContainsCustomPath() {
        let injector = LiveReloadScriptInjector(endpointPath: "/lr")

        let result = injector.inject(into: "")

        XCTAssertTrue(result.contains("/lr"))
    }

    func testInject_whenInjected_scriptContainsReloadLogicAndBackoffBounds() {
        let injector = LiveReloadScriptInjector()

        let result = injector.inject(into: "")

        XCTAssertTrue(result.contains("location.reload()"))
        XCTAssertTrue(result.contains("wss://"))
        XCTAssertTrue(result.contains("500"))
        XCTAssertTrue(result.contains("10000"))
    }

    func testInject_whenCalledOnce_leavesExactlyOneBodyClosingTag() {
        let injector = LiveReloadScriptInjector()
        let html = "<html><body>Hello</body></html>"

        let result = injector.inject(into: html)

        let bodyTagOccurrences = result.lowercased().components(separatedBy: "</body>").count - 1
        XCTAssertEqual(bodyTagOccurrences, 1)
    }

    func testInject_whenHTMLHasContent_producedFragmentStartsAndEndsWithNewline() {
        let injector = LiveReloadScriptInjector()

        let result = injector.inject(into: "")

        // The script fragment itself must be wrapped in leading/trailing newlines
        // so it never merges with an existing line of HTML.
        XCTAssertTrue(result.hasPrefix("\n"))
        XCTAssertTrue(result.hasSuffix("\n"))
    }
}

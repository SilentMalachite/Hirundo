import XCTest
@testable import HirundoCore

final class ConfigParseTests: XCTestCase {
    func testParseMinimalConfig() throws {
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertEqual(config.site.title, "My Site")
        XCTAssertEqual(config.site.url, "https://example.com")
        // Defaults should be present
        XCTAssertEqual(config.build.outputDirectory, "_site")
        XCTAssertEqual(config.build.contentDirectory, "content")
    }

    func testParseInvalidConfigMissingURL() {
        let yaml = """
        site:
          title: "No URL"
          url: ""
        """
        XCTAssertThrowsError(try HirundoConfig.parse(from: yaml)) { error in
            guard case ConfigError.missingRequiredField(let field) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(field, "url")
        }
    }
}

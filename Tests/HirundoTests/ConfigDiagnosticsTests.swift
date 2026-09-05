import XCTest
@testable import HirundoCore

final class ConfigDiagnosticsTests: XCTestCase {
    func testValidConfigProducesNoWarnings() throws {
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"

        server:
          port: 3000
        """

        let report = try ConfigDiagnostics.inspect(yaml: yaml)

        XCTAssertEqual(report.config.site.title, "My Site")
        XCTAssertEqual(report.warnings, [])
    }

    func testUnknownNestedKeyIsReported() throws {
        // A misspelling inside a recognized block is the same silent no-op as a misspelled
        // block, and is the more likely mistake of the two.
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"

        features:
          sitemp: true
        """

        let report = try ConfigDiagnostics.inspect(yaml: yaml)

        XCTAssertEqual(report.warnings.count, 1, "Got: \(report.warnings)")
        XCTAssertTrue(report.warnings.contains { $0.contains("features.sitemp") }, "Got: \(report.warnings)")
    }

    func testARemovedAssetKeyIsReportedAsUnknown() throws {
        // `build.enableAssetFingerprinting` and friends used to decode into `Build` and be read
        // by nothing. They were removed, so a config still carrying one now hears about it.
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"

        build:
          enableAssetFingerprinting: true
        """

        let report = try ConfigDiagnostics.inspect(yaml: yaml)

        XCTAssertEqual(report.warnings.count, 1, "Got: \(report.warnings)")
        XCTAssertTrue(
            report.warnings.contains { $0.contains("build.enableAssetFingerprinting") },
            "Got: \(report.warnings)"
        )
    }

    func testANearMissSuggestsTheKeyItWasProbablyMeantToBe() throws {
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"

        features:
          sitemp: true
        """

        let report = try ConfigDiagnostics.inspect(yaml: yaml)

        XCTAssertTrue(
            report.warnings.contains { $0.contains("Did you mean 'sitemap'?") },
            "Got: \(report.warnings)"
        )
    }

    func testAKeyWithNoNearMatchGetsNoSuggestion() throws {
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"

        timeouts:
          fileOperation: 30
        """

        let report = try ConfigDiagnostics.inspect(yaml: yaml)

        XCTAssertEqual(report.warnings.count, 1, "Got: \(report.warnings)")
        XCTAssertFalse(report.warnings[0].contains("Did you mean"), "Got: \(report.warnings[0])")
    }


    func testTheSameConfigAlwaysProducesTheSameSuggestion() throws {
        // Candidates come from a `Set`, whose iteration order varies per process. Picking the
        // closest match without a tie-break made the same command print different advice on
        // different runs; the comparator now orders by (distance, name).
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"

        build:
          contentDirectori: "content"
        """

        for _ in 0..<5 {
            let report = try ConfigDiagnostics.inspect(yaml: yaml)
            XCTAssertTrue(
                report.warnings.contains { $0.contains("Did you mean 'contentDirectory'?") },
                "Got: \(report.warnings)"
            )
        }
    }

    func testNoSuggestionNamesAKeyTheConfigAlreadyUses() throws {
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"

        features:
          sitemap: true
          sitemaps: true
        """

        let report = try ConfigDiagnostics.inspect(yaml: yaml)

        XCTAssertEqual(report.warnings.count, 1, "Got: \(report.warnings)")
        XCTAssertFalse(report.warnings[0].contains("Did you mean"), "Got: \(report.warnings[0])")
    }

    func testUnknownTopLevelKeyIsReported() throws {
        // The decoder ignores keys it does not know, so a typo or a block that was never wired
        // up (`timeouts`) silently does nothing. That silence is exactly what `validate` exists
        // to break.
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"

        feature:
          sitemap: true

        timeouts:
          fileOperation: 30
        """

        let report = try ConfigDiagnostics.inspect(yaml: yaml)

        XCTAssertEqual(report.warnings.count, 2, "Got: \(report.warnings)")
        XCTAssertTrue(report.warnings.contains { $0.contains("feature") })
        XCTAssertTrue(report.warnings.contains { $0.contains("timeouts") })
    }

    func testInvalidConfigThrowsRatherThanWarning() {
        let yaml = """
        site:
          title: "No URL"
          url: ""
        """

        XCTAssertThrowsError(try ConfigDiagnostics.inspect(yaml: yaml)) { error in
            guard case ConfigError.invalidValue(let details) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(details.contains("Site URL"), "Got: \(details)")
        }
    }
}

import Darwin
import XCTest
@testable import HirundoCore

final class ConfigDiagnosticsTests: XCTestCase {
    func testMergedTopLevelKeysKeepTheirWarningsAndExplicitOverrides() throws {
        let report = try ConfigDiagnostics.inspect(yaml: """
        <<:
          site: {title: Inherited, url: https://example.com, titel: ignored}
          features: {sitemp: true}
          timeouts: {fileOperation: 30}
        site: {title: Explicit, url: https://example.com}
        """)

        XCTAssertEqual(report.config.site.title, "Explicit")
        XCTAssertEqual(report.warnings, [
            "Unknown key 'features.sitemp' — it is ignored. Did you mean 'sitemap'?",
            "Unknown top-level key 'timeouts' — it is ignored."
        ])
    }

    func testMergedBlockKeysKeepTheirWarningsAndSequencePrecedence() throws {
        let report = try ConfigDiagnostics.inspect(yaml: """
        site:
          <<: [{title: First, url: https://example.com, titel: typo}, {title: Second}]
        """)

        XCTAssertEqual(report.config.site.title, "First")
        XCTAssertEqual(report.warnings, ["Unknown key 'site.titel' — it is ignored."])
    }

    func testQuotedMergeKeyRemainsAnUnknownKey() throws {
        let report = try ConfigDiagnostics.inspect(yaml: """
        site:
          title: OK
          url: https://example.com
          "<<": {titel: ignored}
        """)

        XCTAssertEqual(report.warnings, ["Unknown key 'site.<<' — it is ignored."])
    }

    func testMergedComplexKeySharingTheRootPositionKeepsItsWarnings() throws {
        let report = try ConfigDiagnostics.inspect(yaml: """
        &base {features: {sitemp: true}}: ignored
        <<: *base
        site: {title: OK, url: https://example.com}
        """)

        XCTAssertEqual(report.warnings, [
            "Non-scalar top-level keys are ignored.",
            "Unknown key 'features.sitemp' — it is ignored. Did you mean 'sitemap'?"
        ])
    }

    func testValidateWithAComplexTopLevelKeyExitsNormally() throws {
        let yaml = "site:\n  title: OK\n  url: https://example.com\n? [a, b]\n: value\n"
        XCTAssertEqual(yaml.utf8.count, 62)

        let result = try validate(yaml)

        XCTAssertEqual(result.reason, .exit)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Site: OK"))
    }

    func testComplexKeysDoNotHideOtherUnknownKeys() throws {
        let yaml = """
        site:
          title: OK
          url: https://example.com
          ? {a: b}
          : value
          titel: ignored
        ? [a, b]
        : value
        timeouts: ignored
        """
        let result = try validate(yaml)

        XCTAssertEqual(result.reason, .exit)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("Unknown key 'site.titel'"), result.stderr)
        XCTAssertTrue(result.stderr.contains("Unknown top-level key 'timeouts'"), result.stderr)
    }

    func testValidateDoesNotExpandLayeredAliasesInUnknownValues() throws {
        var yaml = "site:\n  title: OK\n  url: https://example.com\n"
        yaml += "unused0: &a0 [leaf, leaf, leaf, leaf]\n"
        for level in 1...16 {
            let aliases = Array(repeating: "*a\(level - 1)", count: 4).joined(separator: ", ")
            yaml += "unused\(level): &a\(level) [\(aliases)]\n"
        }
        yaml += "features:\n  sitemp: *a16\n"
        XCTAssertLessThan(yaml.utf8.count, 1_024)

        // Full expansion would visit over 4 billion leaves. The child process has a deadline
        // so a regression fails this test instead of hanging the whole suite.
        let result = try validate(yaml)

        XCTAssertEqual(result.reason, .exit)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("Unknown key 'features.sitemp'"), result.stderr)
        XCTAssertTrue(result.stdout.contains("18 key(s) are ignored"), result.stdout)
    }

    func testUnknownKeysRemainStderrWarningsWithSuccessfulExit() throws {
        let result = try validate("""
        site:
          title: OK
          url: https://example.com
        features:
          sitemp: true
        """)

        XCTAssertEqual(result.reason, .exit)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("Unknown key 'features.sitemp'"), result.stderr)
        XCTAssertTrue(result.stderr.contains("Did you mean 'sitemap'?"), result.stderr)
        XCTAssertFalse(result.stdout.contains("Unknown key"))
        XCTAssertTrue(result.stdout.contains("1 key(s) are ignored"), result.stdout)
    }

    private func validate(_ yaml: String) throws -> (
        status: Int32, reason: Process.TerminationReason, stdout: String, stderr: String
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-diagnostics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config.yaml")
        let stdout = directory.appendingPathComponent("stdout")
        let stderr = directory.appendingPathComponent("stderr")
        try yaml.write(to: config, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: stdout.path, contents: nil)
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        let output = try FileHandle(forWritingTo: stdout)
        let errors = try FileHandle(forWritingTo: stderr)
        defer {
            try? output.close()
            try? errors.close()
        }

        let process = Process()
        process.executableURL = Bundle(for: ConfigDiagnosticsTests.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("hirundo")
        process.arguments = ["validate", "--config", config.path]
        process.standardOutput = output
        process.standardError = errors
        let completed = expectation(description: "hirundo validate exits")
        process.terminationHandler = { _ in completed.fulfill() }
        try process.run()
        let result = XCTWaiter.wait(for: [completed], timeout: 5)
        if result != .completed {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        XCTAssertEqual(result, .completed, "Validation exceeded five seconds")
        return (
            process.terminationStatus, process.terminationReason,
            try String(contentsOf: stdout, encoding: .utf8),
            try String(contentsOf: stderr, encoding: .utf8)
        )
    }

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

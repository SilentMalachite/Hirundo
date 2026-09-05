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
            guard case ConfigError.invalidValue(let details) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(details.contains("Site URL"), "Got: \(details)")
        }
    }

    func testFeaturesBlockAcceptsASubsetOfKeys() throws {
        // Every other optional block defaults its missing keys; `features` must too, or a
        // user who only wants a sitemap has to spell out all four flags.
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"
        features:
          sitemap: true
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertTrue(config.features.sitemap)
        XCTAssertFalse(config.features.rss)
        XCTAssertFalse(config.features.searchIndex)
        XCTAssertFalse(config.features.minify)
    }

    func testEmptyFeaturesBlockLeavesEveryFlagOff() throws {
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"
        features: {}
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertEqual(config.features, Features())
    }

    func testLoadDoesNotWrapAnAlreadyWrappedParseError() throws {
        // `load` used to re-wrap the `ConfigError` that `parse` had already produced, so the
        // user saw "Failed to parse configuration: Failed to parse configuration: …".
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-config-load-\(UUID().uuidString).yaml")
        try "site:\n  title: \"No URL\"\n  url: \"\"\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try HirundoConfig.load(from: url)) { error in
            XCTAssertFalse(
                error.localizedDescription.contains("Failed to parse configuration"),
                "Re-wrapped: \(error.localizedDescription)"
            )
            XCTAssertTrue(
                error.localizedDescription.contains("Site URL"),
                "Got: \(error.localizedDescription)"
            )
        }
    }

    func testLimitsBlockAcceptsASubsetOfKeys() throws {
        // Same defect as `features` had: the synthesized decoder demanded all ten keys.
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"
        limits:
          maxTitleLength: 120
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertEqual(config.limits.maxTitleLength, 120)
        XCTAssertEqual(config.limits.maxUrlLength, Limits().maxUrlLength)
    }

    func testMissingRequiredKeyIsReportedWithItsPath() {
        let yaml = """
        site:
          title: "My Site"
        """
        XCTAssertThrowsError(try HirundoConfig.parse(from: yaml)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("site.url"),
                "Expected the key path in: \(error.localizedDescription)"
            )
        }
    }

    func testTypeMismatchIsReportedWithItsPath() {
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"
        blog:
          postsPerPage: "ten"
        """
        XCTAssertThrowsError(try HirundoConfig.parse(from: yaml)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("blog.postsPerPage"),
                "Expected the key path in: \(error.localizedDescription)"
            )
        }
    }

    func testAModelValidationErrorSurvivesTheDecoder() {
        // Yams re-wraps anything a model's `init(from:)` throws as `DecodingError.dataCorrupted`
        // with an empty coding path, so the real reason has to be dug back out of
        // `underlyingError` or the user is told the YAML is malformed when it is not.
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"
        blog:
          postsPerPage: 500
        """
        XCTAssertThrowsError(try HirundoConfig.parse(from: yaml)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("postsPerPage cannot exceed 100"),
                "Got: \(error.localizedDescription)"
            )
        }
    }

    func testATypeMismatchIsDescribedWithoutTheDecodersInternalTypeNames() {
        let yaml = """
        site: 3
        """
        XCTAssertThrowsError(try HirundoConfig.parse(from: yaml)) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("site"), "Got: \(message)")
            XCTAssertFalse(message.contains("Mapping"), "Decoder internals leaked: \(message)")
        }
    }

    // MARK: - Validation on the decode path
    //
    // `Site` and `Author` were the only config models without an `init(from:)`, so the
    // synthesized decoder assigned raw values and their throwing initializers — the ones that
    // hold every documented rule — never ran for a `config.yaml`.

    func testSiteURLIsValidatedWhenDecoded() {
        let yaml = """
        site:
          title: "My Site"
          url: "totally not a url"
        """
        XCTAssertThrowsError(try HirundoConfig.parse(from: yaml)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("Invalid URL format"),
                "Got: \(error.localizedDescription)"
            )
        }
    }

    func testSiteTitleLengthIsValidatedWhenDecoded() {
        let yaml = """
        site:
          title: "\(String(repeating: "a", count: 300))"
          url: "https://example.com"
        """
        XCTAssertThrowsError(try HirundoConfig.parse(from: yaml)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("cannot exceed 200"),
                "Got: \(error.localizedDescription)"
            )
        }
    }

    func testAuthorEmailIsValidatedWhenDecoded() {
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"
          author:
            name: "Someone"
            email: "not-an-email"
        """
        XCTAssertThrowsError(try HirundoConfig.parse(from: yaml)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("Invalid email format"),
                "Got: \(error.localizedDescription)"
            )
        }
    }

    func testSiteStillDecodesEveryValidField() throws {
        let yaml = """
        site:
          title: "My Site"
          description: "A site"
          url: "https://example.com"
          language: "ja-JP"
          author:
            name: "Someone"
            email: "someone@example.com"
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertEqual(config.site.title, "My Site")
        XCTAssertEqual(config.site.description, "A site")
        XCTAssertEqual(config.site.url, "https://example.com")
        XCTAssertEqual(config.site.language, "ja-JP")
        XCTAssertEqual(config.site.author?.name, "Someone")
        XCTAssertEqual(config.site.author?.email, "someone@example.com")
    }

    func testAnAbsentLanguageStaysAbsent() throws {
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertNil(config.site.language)
    }

    func testRealWorldLanguageTagsAreAccepted() throws {
        // Language codes are not all `xx` or `xx-YY`: script subtags and three-letter codes are
        // ordinary BCP 47. Rejecting them would break sites that built fine before the decode
        // path started validating at all.
        for tag in ["en", "en-US", "pt-BR", "zh-Hans", "sr-Cyrl-RS", "haw", "fil", "en-Latn-US"] {
            let yaml = """
            site:
              title: "My Site"
              url: "https://example.com"
              language: "\(tag)"
            """
            let config = try HirundoConfig.parse(from: yaml)
            XCTAssertEqual(config.site.language, tag)
        }
    }

    func testAMalformedLanguageTagIsRejected() {
        for tag in ["en_US", "english!", "-en", "en-"] {
            let yaml = """
            site:
              title: "My Site"
              url: "https://example.com"
              language: "\(tag)"
            """
            XCTAssertThrowsError(try HirundoConfig.parse(from: yaml), "Accepted '\(tag)'")
        }
    }

    func testLimitsRejectANonPositiveValue() {
        let yaml = """
        site:
          title: "My Site"
          url: "https://example.com"
        limits:
          maxTitleLength: -5
        """
        XCTAssertThrowsError(try HirundoConfig.parse(from: yaml)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("maxTitleLength"),
                "Got: \(error.localizedDescription)"
            )
        }
    }
}

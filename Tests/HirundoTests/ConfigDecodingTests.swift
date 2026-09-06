import XCTest
import Yams
@testable import HirundoCore

final class ConfigDecodingTests: XCTestCase {
    private enum Format: CaseIterable {
        case json, yaml

        func decode(_ document: [String: Any], limits: Limits? = nil) throws -> HirundoConfig {
            switch self {
            case .json:
                let decoder = JSONDecoder()
                if let limits { decoder.userInfo[.hirundoLimits] = limits }
                return try decoder.decode(HirundoConfig.self, from: JSONSerialization.data(withJSONObject: document))
            case .yaml:
                return try YAMLDecoder().decode(
                    HirundoConfig.self, from: Yams.dump(object: document),
                    userInfo: limits.map { [.hirundoLimits: $0] } ?? [:]
                )
            }
        }
    }

    func testDirectDecodingAcceptsARaisedTitleLimit() throws {
        let title = String(repeating: "a", count: 300)
        for format in Format.allCases {
            let config = try format.decode([
                "site": ["title": title, "url": "https://example.com"],
                "limits": ["maxTitleLength": 400]
            ])
            XCTAssertEqual(config.site.title, title, "\(format)")
            XCTAssertEqual(config.limits.maxTitleLength, 400)
        }
    }

    func testDirectDecodingAcceptsRaisedAuthorLimits() throws {
        let name = String(repeating: "a", count: 150)
        let email = String(repeating: "a", count: 260) + "@example.com"
        for format in Format.allCases {
            let config = try format.decode([
                "site": ["title": "OK", "url": "https://example.com", "author": ["name": name, "email": email]],
                "limits": ["maxAuthorNameLength": 200, "maxEmailLength": 300]
            ])
            XCTAssertEqual(config.site.author?.name, name, "\(format)")
            XCTAssertEqual(config.site.author?.email, email, "\(format)")
        }
    }

    func testDirectDecodingEnforcesEverySiteAndAuthorLengthLimit() {
        let site: [String: Any] = [
            "title": "Title", "description": "Description", "url": "https://example.com",
            "language": "en-US", "author": ["name": "Author", "email": "a@example.com"]
        ]
        let cases = [
            ("maxTitleLength", "Site title"), ("maxDescriptionLength", "Site description"),
            ("maxUrlLength", "Site URL"), ("maxLanguageCodeLength", "Language code"),
            ("maxAuthorNameLength", "Author name"), ("maxEmailLength", "Email")
        ]
        for format in Format.allCases {
            for (limit, field) in cases {
                XCTAssertThrowsError(try format.decode(["site": site, "limits": [limit: 1]]), "\(format): \(limit)") {
                    let underlying: Error
                    if case DecodingError.dataCorrupted(let context) = $0 {
                        underlying = context.underlyingError ?? $0
                    } else {
                        underlying = $0
                    }
                    guard case ConfigError.invalidValue(let message) = underlying else {
                        return XCTFail("Unexpected error: \(underlying)")
                    }
                    XCTAssertEqual(message, "\(field) cannot exceed 1 characters")
                }
            }
        }
    }

    func testDocumentLimitsOverrideDecoderUserInfo() throws {
        for format in Format.allCases {
            let config = try format.decode([
                "site": ["title": String(repeating: "a", count: 300), "url": "https://example.com"],
                "limits": ["maxTitleLength": 400]
            ], limits: Limits(maxTitleLength: 1))
            XCTAssertEqual(config.site.title.count, 300, "\(format)")
        }
    }

    func testAbsentNullAndEmptyLimitsUseDefaults() throws {
        for format in Format.allCases {
            for value in [nil, NSNull(), [:]] as [Any?] {
                var document: [String: Any] = ["site": ["title": "OK", "url": "https://example.com"]]
                document["limits"] = value
                let config = try format.decode(document, limits: Limits(maxTitleLength: 1))
                XCTAssertEqual(config.limits.maxTitleLength, Limits().maxTitleLength, "\(format)")
                XCTAssertNil(config.site.author)

                document["site"] = ["title": String(repeating: "a", count: 201), "url": "https://example.com"]
                XCTAssertThrowsError(try format.decode(document), "\(format)")
            }
        }
    }

    func testDirectDecodingPreservesOptionalAuthorAndRequiredSite() throws {
        for format in Format.allCases {
            let config = try format.decode([
                "site": ["title": "OK", "url": "https://example.com", "author": NSNull()]
            ])
            XCTAssertNil(config.site.author)
            XCTAssertThrowsError(try format.decode([:])) { error in
                guard case DecodingError.keyNotFound(let key, let context) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(key.stringValue, "site")
                XCTAssertTrue(context.codingPath.isEmpty)
            }
            XCTAssertThrowsError(try format.decode([
                "site": ["title": "OK", "url": "https://example.com", "author": [:]]
            ])) { error in
                guard case DecodingError.keyNotFound(let key, let context) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(key.stringValue, "name")
                XCTAssertEqual(context.codingPath.map(\.stringValue), ["site", "author"])
            }
        }
    }

    func testFingerprintDefaultsToOff() throws {
        let yaml = """
        site:
          title: "Test"
          url: "https://example.com"
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertFalse(config.features.fingerprint)
    }

    func testFingerprintCanBeEnabledOnItsOwn() throws {
        let yaml = """
        site:
          title: "Test"
          url: "https://example.com"

        features:
          fingerprint: true
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertTrue(config.features.fingerprint)
        XCTAssertFalse(config.features.sitemap, "他のフラグは既定の false のまま")
    }

    func testValidateDoesNotWarnAboutFingerprint() throws {
        let yaml = """
        site:
          title: "Test"
          url: "https://example.com"

        features:
          fingerprint: true
        """
        let report = try ConfigDiagnostics.inspect(yaml: yaml)
        XCTAssertFalse(
            report.warnings.contains { $0.contains("fingerprint") },
            "既知のキーなので警告してはならない: \(report.warnings)"
        )
    }

    func testAssetsDefaultsToNoExclusionsWhenBlockIsAbsent() throws {
        let yaml = """
        site:
          title: "Test"
          url: "https://example.com"
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertEqual(config.assets.fingerprintExclude, [])
    }

    func testAssetsFingerprintExcludeDecodesTheGivenPatterns() throws {
        let yaml = """
        site:
          title: "Test"
          url: "https://example.com"

        assets:
          fingerprintExclude:
            - "apple-touch-icon*.png"
            - "ads.txt"
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertEqual(config.assets.fingerprintExclude, ["apple-touch-icon*.png", "ads.txt"])
    }

    func testEmptyAssetsBlockDecodesToNoExclusions() throws {
        // The synthesized decoder would require `fingerprintExclude` to be present; an
        // `assets: {}` block with no keys at all must still decode, matching `features: {}`.
        let yaml = """
        site:
          title: "Test"
          url: "https://example.com"

        assets: {}
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertEqual(config.assets.fingerprintExclude, [])
    }

    func testValidateDoesNotWarnAboutAssets() throws {
        let yaml = """
        site:
          title: "Test"
          url: "https://example.com"

        assets:
          fingerprintExclude:
            - "ads.txt"
        """
        let report = try ConfigDiagnostics.inspect(yaml: yaml)
        XCTAssertTrue(report.warnings.isEmpty, "既知のブロックなので警告してはならない: \(report.warnings)")
    }

    func testValidateWarnsAboutAnUnknownKeyInsideAssets() throws {
        let yaml = """
        site:
          title: "Test"
          url: "https://example.com"

        assets:
          fingerprintExclud:
            - "ads.txt"
        """
        let report = try ConfigDiagnostics.inspect(yaml: yaml)
        XCTAssertTrue(
            report.warnings.contains { $0.contains("assets.fingerprintExclud") },
            "Got: \(report.warnings)"
        )
    }
}

import XCTest
@testable import HirundoCore

final class NewContentContextTests: XCTestCase {
    var projectRoot: URL!

    override func setUp() {
        super.setUp()
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-new-content-context-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: projectRoot)
        super.tearDown()
    }

    private func writeConfig(_ contents: String) throws {
        try contents.write(
            to: projectRoot.appendingPathComponent("config.yaml"),
            atomically: true,
            encoding: .utf8
        )
    }

    // The CLI warns about both fallbacks; `resolve` only reports which one happened.
    func testNoConfigFile_fallsBackToDefaultsAndSignalsMissing() {
        let context = NewContentContext.resolve(projectRoot: projectRoot)

        XCTAssertEqual(context.build.contentDirectory, Build.defaultBuild().contentDirectory)
        XCTAssertEqual(context.limits.maxTitleLength, Limits().maxTitleLength)
        XCTAssertEqual(context.fallback, .missing)
    }

    func testMalformedConfigFile_fallsBackToDefaultsAndSignalsUnreadable() throws {
        // A config.yaml that exists but fails to load: `site.url` is required and empty
        // here, so `HirundoConfig.load` throws `ConfigError.missingRequiredField`.
        try writeConfig("""
        site:
          title: "Malformed"
          url: ""
        """)

        let context = NewContentContext.resolve(projectRoot: projectRoot)

        XCTAssertEqual(context.build.contentDirectory, Build.defaultBuild().contentDirectory)
        XCTAssertEqual(context.limits.maxTitleLength, Limits().maxTitleLength)
        XCTAssertEqual(context.fallback, .unreadable)
    }

    func testValidConfigFile_usesItsBuildAndLimitsWithoutFallback() throws {
        try writeConfig("""
        site:
          title: "My Site"
          url: "https://example.com"
        build:
          contentDirectory: "my-content"
          outputDirectory: "_out"
          staticDirectory: "static"
          templatesDirectory: "templates"
        limits:
          maxMarkdownFileSize: 10485760
          maxConfigFileSize: 1048576
          maxFrontMatterSize: 100000
          maxFilenameLength: 255
          maxTitleLength: 42
          maxDescriptionLength: 500
          maxUrlLength: 2000
          maxAuthorNameLength: 100
          maxEmailLength: 254
          maxLanguageCodeLength: 10
        """)

        let context = NewContentContext.resolve(projectRoot: projectRoot)

        XCTAssertEqual(context.build.contentDirectory, "my-content")
        XCTAssertEqual(context.limits.maxTitleLength, 42)
        XCTAssertNil(context.fallback)
    }
}

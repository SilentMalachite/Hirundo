import XCTest
@testable import HirundoCore

/// Verifies how `hirundo init` interprets its path argument: where it scaffolds, and
/// whether it tells the user to `cd` afterwards. The "same directory" decision must
/// survive symlinked spellings of one directory (`/tmp` vs `/private/tmp`), and an empty
/// argument must be rejected instead of silently meaning "here".
final class InitDestinationResolverTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-init-dest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Current directory

    func testResolve_whenPathIsDot_targetsCurrentDirectoryWithoutCdStep() throws {
        let resolved = try InitDestinationResolver.resolve(path: ".", currentDirectory: tempDir)

        XCTAssertTrue(resolved.isCurrentDirectory)
        XCTAssertNil(resolved.changeDirectoryCommand)
        XCTAssertEqual(
            resolved.url.resolvingSymlinksInPath().path,
            tempDir.resolvingSymlinksInPath().path
        )
    }

    func testResolve_whenPathIsAbsoluteCurrentDirectory_omitsCdStep() throws {
        let resolved = try InitDestinationResolver.resolve(
            path: tempDir.path,
            currentDirectory: tempDir
        )

        XCTAssertTrue(resolved.isCurrentDirectory)
        XCTAssertNil(resolved.changeDirectoryCommand)
    }

    func testResolve_whenPathSpellsCurrentDirectoryThroughASymlink_omitsCdStep() throws {
        let real = tempDir.appendingPathComponent("real-site")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = tempDir.appendingPathComponent("linked-site")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let resolved = try InitDestinationResolver.resolve(path: link.path, currentDirectory: real)

        XCTAssertTrue(
            resolved.isCurrentDirectory,
            "A symlinked spelling of the current directory must not ask the user to cd"
        )
        XCTAssertNil(resolved.changeDirectoryCommand)
    }

    func testResolve_whenPathIsPrivateAliasOfCurrentDirectory_omitsCdStep() throws {
        let fm = FileManager.default
        guard (try? fm.destinationOfSymbolicLink(atPath: "/tmp")) != nil else {
            throw XCTSkip("/tmp is not a symlink on this platform")
        }

        let resolved = try InitDestinationResolver.resolve(
            path: "/tmp",
            currentDirectory: URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        )

        XCTAssertTrue(resolved.isCurrentDirectory)
        XCTAssertNil(resolved.changeDirectoryCommand)
    }

    func testResolve_whenPathIsCurrentDirectoryWithDotSegments_omitsCdStep() throws {
        let resolved = try InitDestinationResolver.resolve(
            path: "./sub/..",
            currentDirectory: tempDir
        )

        XCTAssertTrue(resolved.isCurrentDirectory)
        XCTAssertNil(resolved.changeDirectoryCommand)
    }

    // MARK: - Other destinations

    func testResolve_whenPathIsRelativeSubdirectory_resolvesUnderCurrentDirectory() throws {
        let resolved = try InitDestinationResolver.resolve(path: "blog", currentDirectory: tempDir)

        XCTAssertFalse(resolved.isCurrentDirectory)
        XCTAssertEqual(resolved.changeDirectoryCommand, "cd 'blog'")
        XCTAssertEqual(
            resolved.url.resolvingSymlinksInPath().path,
            tempDir.appendingPathComponent("blog").resolvingSymlinksInPath().path
        )
    }

    func testResolve_whenPathIsAbsoluteElsewhere_keepsAbsoluteDestination() throws {
        let other = tempDir.appendingPathComponent("elsewhere")

        let resolved = try InitDestinationResolver.resolve(path: other.path, currentDirectory: tempDir)

        XCTAssertFalse(resolved.isCurrentDirectory)
        XCTAssertEqual(resolved.changeDirectoryCommand, "cd \(other.path.posixShellQuoted)")
        XCTAssertEqual(
            resolved.url.resolvingSymlinksInPath().path,
            other.resolvingSymlinksInPath().path
        )
    }

    // MARK: - Shell safety

    func testResolve_whenPathContainsSpaces_quotesTheCdArgument() throws {
        let resolved = try InitDestinationResolver.resolve(path: "My Site", currentDirectory: tempDir)

        XCTAssertEqual(resolved.changeDirectoryCommand, "cd 'My Site'")
    }

    func testResolve_whenPathContainsApostrophe_escapesTheCdArgument() throws {
        let resolved = try InitDestinationResolver.resolve(path: "it's site", currentDirectory: tempDir)

        XCTAssertEqual(resolved.changeDirectoryCommand, "cd 'it'\\''s site'")
    }

    // MARK: - Empty path

    func testResolve_whenPathIsEmpty_throwsInsteadOfSilentlyUsingCurrentDirectory() {
        XCTAssertThrowsError(
            try InitDestinationResolver.resolve(path: "", currentDirectory: tempDir)
        ) { error in
            XCTAssertEqual(error as? ScaffoldError, .emptyDestinationPath)
        }
    }

    func testEmptyDestinationPath_reportsAsAUsageErrorWithAnActionableSuggestion() {
        let info = ScaffoldError.emptyDestinationPath.toHirundoError()

        XCTAssertEqual(info.code, "EMPTY_PATH")
        XCTAssertEqual(info.category, .configuration)
        XCTAssertNotNil(info.suggestion)
        XCTAssertNotEqual(info.suggestedAction, ErrorCategory.configuration.defaultSuggestedAction)
        XCTAssertFalse(ScaffoldError.emptyDestinationPath.localizedDescription.isEmpty)
    }
}

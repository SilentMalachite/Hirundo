import XCTest
@testable import HirundoCore

/// Verifies how `ContentScaffoldError` cases surface to the user. The category decides
/// the headline the CLI prints, so a bad `--slug` must not be reported as a disk failure.
final class ContentScaffoldErrorMappingTests: XCTestCase {

    // MARK: - Categories

    func testToHirundoError_whenInputInvalid_usesConfigurationCategory() {
        XCTAssertEqual(ContentScaffoldError.invalidTitle("empty").toHirundoError().category, .configuration)
        XCTAssertEqual(ContentScaffoldError.invalidSlug("bad").toHirundoError().category, .configuration)
        XCTAssertEqual(ContentScaffoldError.invalidPath("bad").toHirundoError().category, .configuration)
    }

    func testToHirundoError_whenIOFails_usesFilesystemCategory() {
        XCTAssertEqual(ContentScaffoldError.fileExists("/p").toHirundoError().category, .filesystem)
        XCTAssertEqual(ContentScaffoldError.cannotCreateDirectory("/p").toHirundoError().category, .filesystem)
        XCTAssertEqual(ContentScaffoldError.cannotWriteFile("/p").toHirundoError().category, .filesystem)
    }

    func testToHirundoError_whenTitleInvalid_isNotPresentedAsDiskProblem() {
        let info = ContentScaffoldError.invalidTitle("Title cannot be empty").toHirundoError()

        XCTAssertFalse(
            info.userMessage.contains("File System Error"),
            "A bad title must not be presented as a file system error"
        )
    }

    // MARK: - Per-error suggestions

    func testToHirundoError_whenFileExists_suggestsADifferentName() {
        let info = ContentScaffoldError.fileExists("/p/hello-world.md").toHirundoError()

        XCTAssertNotNil(info.suggestion)
        XCTAssertTrue(
            info.suggestedAction.contains("--slug"),
            "Expected the --slug hint, got: \(info.suggestedAction)"
        )
        XCTAssertNotEqual(info.suggestedAction, ErrorCategory.filesystem.defaultSuggestedAction)
        XCTAssertFalse(
            info.userMessage.contains("available disk space"),
            "A name collision is not a disk space problem"
        )
    }

    func testToHirundoError_whenSlugInvalid_describesWhatIsActuallyRejected() {
        let info = ContentScaffoldError.invalidSlug("contains a slash").toHirundoError()

        XCTAssertNotNil(info.suggestion)
        XCTAssertTrue(info.suggestedAction.contains("--slug"))
        // The slug is used verbatim as the file name, so the suggestion must not promise a
        // character-set rule that `ContentScaffolder.resolveSlug` does not enforce.
        XCTAssertFalse(
            info.suggestedAction.lowercased().contains("letters, digits"),
            "Got a suggestion promising an unenforced charset: \(info.suggestedAction)"
        )
    }

    func testToHirundoError_whenPathInvalid_mentionsTheContentDirectory() {
        let info = ContentScaffoldError.invalidPath("escapes the content directory").toHirundoError()

        XCTAssertNotNil(info.suggestion)
        XCTAssertTrue(info.suggestedAction.contains("--path"))
    }

    func testToHirundoError_whenIOFails_keepsTheGenericSuggestion() {
        XCTAssertNil(ContentScaffoldError.cannotWriteFile("/p").toHirundoError().suggestion)
        XCTAssertNil(ContentScaffoldError.cannotCreateDirectory("/p").toHirundoError().suggestion)
    }

    // MARK: - Messages

    func testErrorDescription_includesTheOffendingPath() {
        XCTAssertEqual(
            ContentScaffoldError.fileExists("/p/hello.md").errorDescription,
            "File already exists: /p/hello.md"
        )
    }

    func testEquatable_distinguishesCasesAndPayloads() {
        XCTAssertEqual(ContentScaffoldError.fileExists("/a"), ContentScaffoldError.fileExists("/a"))
        XCTAssertNotEqual(ContentScaffoldError.fileExists("/a"), ContentScaffoldError.fileExists("/b"))
        XCTAssertNotEqual(ContentScaffoldError.invalidSlug("x"), ContentScaffoldError.invalidPath("x"))
    }
}

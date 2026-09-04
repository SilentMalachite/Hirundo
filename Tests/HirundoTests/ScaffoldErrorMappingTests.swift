import XCTest
@testable import HirundoCore

/// Verifies how `ScaffoldError` cases surface to the user: the category decides the
/// headline the CLI prints, and the suggestion decides the action it recommends.
/// A bad `--title` must not be reported as a disk/permissions problem.
final class ScaffoldErrorMappingTests: XCTestCase {

    // MARK: - Categories

    func testToHirundoError_whenTitleInvalid_usesConfigurationCategory() {
        let info = ScaffoldError.invalidTitle("Site title cannot be empty").toHirundoError()

        XCTAssertEqual(info.category, .configuration)
        XCTAssertFalse(
            info.userMessage.contains("File System Error"),
            "A bad --title must not be presented as a file system error"
        )
    }

    func testToHirundoError_whenIOFails_staysFilesystemCategory() {
        XCTAssertEqual(ScaffoldError.cannotCreateDirectory("/p").toHirundoError().category, .filesystem)
        XCTAssertEqual(ScaffoldError.cannotWriteFile("/p").toHirundoError().category, .filesystem)
        XCTAssertEqual(ScaffoldError.cannotReadDirectory("/p").toHirundoError().category, .filesystem)
        XCTAssertEqual(ScaffoldError.cannotReadFile("/p").toHirundoError().category, .filesystem)
    }

    // MARK: - Per-error suggestions

    func testToHirundoError_whenDestinationNotEmpty_suggestsForceFlag() {
        let info = ScaffoldError.destinationNotEmpty("/p").toHirundoError()

        XCTAssertNotNil(info.suggestion)
        XCTAssertTrue(
            info.suggestedAction.contains("--force"),
            "Expected the --force hint, got: \(info.suggestedAction)"
        )
        XCTAssertNotEqual(info.suggestedAction, ErrorCategory.filesystem.defaultSuggestedAction)
        XCTAssertTrue(info.userMessage.contains("--force"))
        XCTAssertFalse(info.userMessage.contains("available disk space"))
    }

    func testToHirundoError_whenDestinationIsFile_suggestsChoosingADirectory() {
        let info = ScaffoldError.destinationIsFile("/p").toHirundoError()

        XCTAssertNotNil(info.suggestion)
        XCTAssertTrue(
            info.suggestedAction.lowercased().contains("directory"),
            "Expected a directory hint, got: \(info.suggestedAction)"
        )
        XCTAssertNotEqual(info.suggestedAction, ErrorCategory.filesystem.defaultSuggestedAction)
    }

    func testToHirundoError_whenTitleInvalid_suggestsFixingTheTitleOption() {
        let info = ScaffoldError.invalidTitle("Site title cannot be empty").toHirundoError()

        XCTAssertNotNil(info.suggestion)
        XCTAssertTrue(
            info.suggestedAction.contains("--title"),
            "Expected the --title hint, got: \(info.suggestedAction)"
        )
        XCTAssertTrue(info.userMessage.contains("--title"))
    }

    func testToHirundoError_whenIOFails_fallsBackToCategorySuggestion() {
        for error: ScaffoldError in [
            .cannotCreateDirectory("/p"),
            .cannotWriteFile("/p"),
            .cannotReadDirectory("/p"),
            .cannotReadFile("/p")
        ] {
            let info = error.toHirundoError()
            XCTAssertNil(info.suggestion, "\(error) should not override the category suggestion")
            XCTAssertEqual(info.suggestedAction, ErrorCategory.filesystem.defaultSuggestedAction)
        }
    }

    // MARK: - Stable codes

    func testToHirundoError_keepsStableCodes() {
        XCTAssertEqual(ScaffoldError.destinationNotEmpty("/p").toHirundoError().code, "DEST_NOT_EMPTY")
        XCTAssertEqual(ScaffoldError.destinationIsFile("/p").toHirundoError().code, "DEST_IS_FILE")
        XCTAssertEqual(ScaffoldError.invalidTitle("x").toHirundoError().code, "INVALID_TITLE")
        XCTAssertEqual(ScaffoldError.cannotCreateDirectory("/p").toHirundoError().code, "CREATE_DIR_FAILED")
        XCTAssertEqual(ScaffoldError.cannotWriteFile("/p").toHirundoError().code, "WRITE_FAILED")
        XCTAssertEqual(ScaffoldError.cannotReadDirectory("/p").toHirundoError().code, "READ_DIR_FAILED")
        XCTAssertEqual(ScaffoldError.cannotReadFile("/p").toHirundoError().code, "READ_FILE_FAILED")
    }

    func testToHirundoError_keepsUnderlyingErrorAndDetails() {
        let error = ScaffoldError.destinationNotEmpty("/p")
        let info = error.toHirundoError()

        XCTAssertEqual(info.details, error.localizedDescription)
        XCTAssertEqual(info.underlyingError as? ScaffoldError, error)
    }

    // MARK: - HirundoErrorInfo suggestion channel

    func testHirundoErrorInfo_whenNoSuggestionGiven_usesCategoryDefault() {
        let info = HirundoErrorInfo(category: .server, code: "X", details: "d")

        XCTAssertNil(info.suggestion)
        XCTAssertEqual(info.suggestedAction, ErrorCategory.server.defaultSuggestedAction)
        XCTAssertTrue(info.userMessage.contains(ErrorCategory.server.defaultSuggestedAction))
    }

    func testHirundoErrorInfo_whenSuggestionGiven_overridesCategoryDefault() {
        let info = HirundoErrorInfo(category: .server, code: "X", details: "d", suggestion: "Do the thing")

        XCTAssertEqual(info.suggestedAction, "Do the thing")
        XCTAssertTrue(info.userMessage.contains("💡 Suggestion: Do the thing"))
        XCTAssertFalse(info.userMessage.contains(ErrorCategory.server.defaultSuggestedAction))
    }

    func testEveryCategory_hasANonEmptyDefaultSuggestion() {
        for category in ErrorCategory.allCases {
            XCTAssertFalse(
                category.defaultSuggestedAction.isEmpty,
                "\(category) needs a default suggestion"
            )
        }
    }
}

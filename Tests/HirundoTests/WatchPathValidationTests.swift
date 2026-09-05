import XCTest
@testable import HirundoCore

/// Every case here is pure path arithmetic — no directory is created, because the rule is about
/// what the configuration says, not about what happens to exist when `serve` starts.
final class WatchPathValidationTests: XCTestCase {

    private let root = "/projects/my-site"

    // MARK: - Overlapping Layouts

    func testWatchPathsOverlappingOutput_whenOutputIsNestedUnderAWatchedPath_reportsThatPath() {
        // `outputDirectory: "static/out"` passes Build's name-uniqueness check, so this is the
        // configuration a user can actually write today.
        let overlapping = watchPathsOverlappingOutput(
            watchPaths: ["\(root)/content", "\(root)/templates", "\(root)/static"],
            outputPath: "\(root)/static/out"
        )

        XCTAssertEqual(overlapping, ["\(root)/static"])
    }

    func testWatchPathsOverlappingOutput_whenAWatchedPathIsNestedUnderTheOutput_reportsThatPath() {
        let overlapping = watchPathsOverlappingOutput(
            watchPaths: ["\(root)/_site/content", "\(root)/templates"],
            outputPath: "\(root)/_site"
        )

        XCTAssertEqual(overlapping, ["\(root)/_site/content"])
    }

    func testWatchPathsOverlappingOutput_whenAWatchedPathEqualsTheOutput_reportsThatPath() {
        let overlapping = watchPathsOverlappingOutput(
            watchPaths: ["\(root)/content", "\(root)/public"],
            outputPath: "\(root)/public"
        )

        XCTAssertEqual(overlapping, ["\(root)/public"])
    }

    func testWatchPathsOverlappingOutput_whenOutputIsTheProjectRoot_reportsEveryWatchedPath() {
        let watchPaths = ["\(root)/content", "\(root)/templates", "\(root)/static"]

        let overlapping = watchPathsOverlappingOutput(watchPaths: watchPaths, outputPath: root)

        XCTAssertEqual(overlapping, watchPaths)
    }

    // MARK: - Layouts That Must Be Accepted

    func testWatchPathsOverlappingOutput_whenOutputIsASibling_reportsNothing() {
        let overlapping = watchPathsOverlappingOutput(
            watchPaths: ["\(root)/content", "\(root)/templates", "\(root)/static"],
            outputPath: "\(root)/_site"
        )

        XCTAssertTrue(overlapping.isEmpty, "\(overlapping)")
    }

    func testWatchPathsOverlappingOutput_whenOutputSharesAPrefixButIsNotNested_reportsNothing() {
        // `/projects/my-site/stat` starts with the same characters as `/projects/my-site/static`
        // without being inside it — a plain `hasPrefix` would get this wrong in both directions.
        XCTAssertTrue(
            watchPathsOverlappingOutput(
                watchPaths: ["\(root)/static"],
                outputPath: "\(root)/stat"
            ).isEmpty
        )
        XCTAssertTrue(
            watchPathsOverlappingOutput(
                watchPaths: ["\(root)/stat"],
                outputPath: "\(root)/static"
            ).isEmpty
        )
        XCTAssertTrue(
            watchPathsOverlappingOutput(
                watchPaths: ["\(root)/static"],
                outputPath: "\(root)/static-out"
            ).isEmpty
        )
    }

    func testWatchPathsOverlappingOutput_whenNoPathsAreWatched_reportsNothing() {
        XCTAssertTrue(watchPathsOverlappingOutput(watchPaths: [], outputPath: root).isEmpty)
    }

    // MARK: - Path Normalization

    func testWatchPathsOverlappingOutput_whenPathsNeedStandardizing_comparesTheResolvedForm() {
        // A trailing separator and a `..` segment must not hide the overlap.
        let overlapping = watchPathsOverlappingOutput(
            watchPaths: ["\(root)/static/"],
            outputPath: "\(root)/templates/../static/out"
        )

        XCTAssertEqual(overlapping, ["\(root)/static/"], "the caller's spelling is echoed back")
    }

    // MARK: - Throwing Validator

    func testValidateWatchPaths_whenTheOutputIsNested_throwsNamingBothDirectories() {
        XCTAssertThrowsError(
            try validateWatchPaths(["\(root)/static"], outputPath: "\(root)/static/out")
        ) { error in
            XCTAssertEqual(
                error as? WatchPathError,
                .outputOverlapsWatchPaths(
                    watchPaths: ["\(root)/static"],
                    outputPath: "\(root)/static/out"
                )
            )
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("\(root)/static/out"), message)
            XCTAssertTrue(message.contains("build.outputDirectory"), message)
        }
    }

    func testValidateWatchPaths_whenNothingOverlaps_doesNotThrow() {
        XCTAssertNoThrow(
            try validateWatchPaths(
                ["\(root)/content", "\(root)/templates", "\(root)/static"],
                outputPath: "\(root)/_site"
            )
        )
    }
}

import XCTest
@testable import HirundoCore

/// Almost every case here is pure path arithmetic, because the rule is about what the
/// configuration says rather than about what happens to exist when `serve` starts. The one
/// exception creates directories on purpose: it pins down that the answer stays the same when
/// the output directory has not been built yet.
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

    func testWatchPathsOverlappingOutput_whenTheOutputDoesNotExistYet_stillReportsTheOverlap() throws {
        // Regression: the first implementation standardized with `URL.standardizedFileURL`,
        // which drops a leading `/private` only when the path exists. At startup the watched
        // directories exist and the output directory usually does not, so under `/private/tmp`
        // the watched path became `/tmp/…/static` while the output stayed
        // `/private/tmp/…/static/out` — the overlap went unnoticed and `serve` rebuilt forever.
        // `/private/tmp` is used deliberately: it is the aliased root that exposed the bug.
        let base = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("hirundo-watch-path-\(UUID().uuidString)")
        let watched = base.appendingPathComponent("static")
        try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let output = watched.appendingPathComponent("out").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: output))

        let overlapping = watchPathsOverlappingOutput(
            watchPaths: [watched.path],
            outputPath: output
        )

        XCTAssertEqual(overlapping, [watched.path])
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

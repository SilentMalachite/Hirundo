import XCTest
@testable import HirundoCore

/// Covers what `hirundo new` does on a filesystem without hard links.
///
/// The write finishes with `link`, which is exclusive and atomic at once. exFAT and FAT32
/// volumes, and some VM shared folders, have no hard links and answer `EPERM` or `ENOTSUP` —
/// and those users worked before the write became exclusive, so failing there outright would
/// be a regression.
///
/// A test run has no such volume, so the honest way to reach the fallbacks is to make the
/// finishing syscalls report what those filesystems report. Everything below the injection —
/// the temporary file, the write, the `O_EXCL` create, the cleanup — is the real thing on a
/// real filesystem.
final class ContentScaffolderNoHardLinkTests: XCTestCase {

    private var projectRoot: URL!

    private var contentDirectory: URL { projectRoot.appendingPathComponent("content") }

    override func setUp() {
        super.setUp()
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-nolink-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: projectRoot)
        projectRoot = nil
        super.tearDown()
    }

    // MARK: - The regression the fallback exists to prevent

    /// The whole point: `link` reporting `EPERM` used to fail the command outright.
    func testAFilesystemWithoutHardLinksStillCreatesTheFile() throws {
        let result = try scaffold(hardLink: { _, _ in EPERM })

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        XCTAssertTrue(try contents(of: result.url).contains("title: \"Fallback\""))
    }

    func testENOTSUPIsTreatedTheSameWay() throws {
        let result = try scaffold(hardLink: { _, _ in ENOTSUP })

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    /// The whole file has to arrive, not just its first block: the fallbacks write the bytes
    /// again rather than re-using the finished temporary file.
    func testTheFallbackWritesTheCompleteFile() throws {
        let viaLink = try scaffold(title: "Reference")
        let viaFallback = try scaffold(title: "Fallback", hardLink: { _, _ in ENOTSUP })
        let viaLastResort = try scaffold(
            title: "Last Resort",
            hardLink: { _, _ in ENOTSUP },
            exclusiveRename: { _, _ in ENOTSUP }
        )

        // Same document, only the title differs, so the lengths must line up.
        let reference = try contents(of: viaLink.url).replacingOccurrences(of: "Reference", with: "X")
        XCTAssertEqual(
            try contents(of: viaFallback.url).replacingOccurrences(of: "Fallback", with: "X"),
            reference
        )
        XCTAssertEqual(
            try contents(of: viaLastResort.url).replacingOccurrences(of: "Last Resort", with: "X"),
            reference
        )
    }

    /// The last resort — a direct `O_CREAT | O_EXCL` create — is reached only when neither
    /// atomic primitive is available, and it still has to produce the file.
    func testTheLastResortCreateIsReachedWhenNeitherPrimitiveWorks() throws {
        let result = try scaffold(
            hardLink: { _, _ in ENOTSUP },
            exclusiveRename: { _, _ in ENOTSUP }
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    // MARK: - The fallbacks still refuse to overwrite

    /// The race the exclusivity exists for, on a filesystem without hard links: another
    /// process finishes the same file between our existence check and our finalisation. The
    /// fallback must lose, not overwrite.
    func testTheRenameFallbackRefusesToReplaceAFileThatAppearedMeanwhile() throws {
        let existing = contentDirectory.appendingPathComponent("fallback.md")

        assertFileExistsThrown {
            try scaffold(hardLink: { _, _ in
                Self.plant("someone else got there first", at: existing)
                return ENOTSUP
            })
        }
        XCTAssertEqual(try contents(of: existing), "someone else got there first")
    }

    func testTheLastResortCreateRefusesToReplaceAFileThatAppearedMeanwhile() throws {
        let existing = contentDirectory.appendingPathComponent("fallback.md")

        assertFileExistsThrown {
            try scaffold(
                hardLink: { _, _ in ENOTSUP },
                exclusiveRename: { _, _ in
                    Self.plant("someone else got there first", at: existing)
                    return ENOTSUP
                }
            )
        }
        XCTAssertEqual(try contents(of: existing), "someone else got there first")
    }

    /// `EEXIST` from `link` itself keeps meaning exactly what it meant: the name is taken.
    func testEEXISTFromTheLinkStillMeansTheFileExists() {
        assertFileExistsThrown {
            try scaffold(hardLink: { _, _ in EEXIST })
        }
    }

    // MARK: - Failures that are not "no hard links"

    /// An I/O error is a failed write, not a filesystem without hard links: it must not be
    /// retried through a fallback that would report a different problem.
    func testAnUnrelatedLinkFailureIsStillAWriteFailure() {
        do {
            _ = try scaffold(hardLink: { _, _ in EIO })
            XCTFail("Expected the write to fail")
        } catch let error as ContentScaffoldError {
            guard case .cannotWriteFile = error else {
                return XCTFail("Expected cannotWriteFile, got \(error)")
            }
        } catch {
            XCTFail("Expected ContentScaffoldError, got \(error)")
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: contentDirectory.appendingPathComponent("fallback.md").path),
            "a failed write must not leave the destination behind"
        )
    }

    // MARK: - Cleanup

    /// Every route unlinks the temporary file, including the one where `renameatx_np` has
    /// already consumed it and the one that never gets that far.
    func testNoTemporaryFileIsLeftBehindOnAnyRoute() throws {
        _ = try scaffold(title: "Renamed", hardLink: { _, _ in ENOTSUP })
        _ = try scaffold(
            title: "Created",
            hardLink: { _, _ in ENOTSUP },
            exclusiveRename: { _, _ in ENOTSUP }
        )
        _ = try? scaffold(title: "Broken", hardLink: { _, _ in EIO })

        let leftovers = try FileManager.default
            .contentsOfDirectory(atPath: contentDirectory.path)
            .filter { $0.hasPrefix(".hirundo-new-") }
        XCTAssertEqual(leftovers, [], "the temporary file must not survive any route")
    }

    // MARK: - Helpers

    @discardableResult
    private func scaffold(
        title: String = "Fallback",
        hardLink: ((UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32)? = nil,
        exclusiveRename: ((UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32)? = nil
    ) throws -> ContentScaffoldResult {
        var finalisers = ContentScaffolder.ExclusiveFinalisers()
        if let hardLink { finalisers.hardLink = hardLink }
        if let exclusiveRename { finalisers.exclusiveRename = exclusiveRename }

        return try ContentScaffolder(finalisers: finalisers).scaffold(
            in: projectRoot,
            build: Build.defaultBuild(),
            limits: Limits(),
            kind: .page,
            options: ContentScaffoldOptions(title: title),
            date: Date(timeIntervalSince1970: 1_772_000_000)
        )
    }

    private func contents(of url: URL) throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Writes a file the way a competing process would, from inside the finalisation.
    private static func plant(_ contents: String, at url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func assertFileExistsThrown(
        _ body: () throws -> ContentScaffoldResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try body()
            XCTFail("Expected fileExists, but the call succeeded", file: file, line: line)
        } catch let error as ContentScaffoldError {
            guard case .fileExists = error else {
                return XCTFail("Expected fileExists, got \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("Expected ContentScaffoldError, got \(error)", file: file, line: line)
        }
    }
}

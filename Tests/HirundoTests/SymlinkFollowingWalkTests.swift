import XCTest
@testable import HirundoCore

/// Covers the traversal the build and the file watcher share.
///
/// The build learned to follow directory symlinks; the watcher had not, so `hirundo serve`
/// would have built the content behind a link once and then never noticed it changing — the
/// user edits a file, nothing happens, and the served page stays stale. The two walks are one
/// type now, and these tests pin both the walk itself and the watcher's use of it.
///
/// Nothing here waits for a file-system event: the watcher is checked by what it *registers*,
/// which is deterministic, rather than by what FSEvents happens to deliver.
final class SymlinkFollowingWalkTests: XCTestCase {

    private var tempDir: URL!
    private var outsideDir: URL!
    private var manager: HotReloadManager!

    private var contentDirectory: URL { tempDir.appendingPathComponent("content") }

    override func setUp() {
        super.setUp()
        let id = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-walk-test-\(id)")
        outsideDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-walk-outside-\(id)")
        try? FileManager.default.createDirectory(at: contentDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        await manager?.stop()
        manager = nil
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.removeItem(at: outsideDir)
        tempDir = nil
        outsideDir = nil
        try await super.tearDown()
    }

    // MARK: - The walk itself

    func testFilesBehindADirectorySymlinkAreFoundAtTheirLogicalPath() throws {
        try makeDirectory("shared-pages/nested", under: tempDir)
        try write("a", to: tempDir.appendingPathComponent("shared-pages/guide.md"))
        try write("b", to: tempDir.appendingPathComponent("shared-pages/nested/deep.md"))
        try write("c", to: contentDirectory.appendingPathComponent("index.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("shared"), to: "../shared-pages")

        let found = try entries(of: projectWalk())

        XCTAssertEqual(
            Set(found.map(relativeToContent)),
            ["index.md", "shared/guide.md", "shared/nested/deep.md"]
        )
    }

    /// What the watcher registers with FSEvents: the resolved directory, because FSEvents
    /// watches an inode and never sees the link that led there.
    func testAFollowedSymlinkReportsItsResolvedTarget() throws {
        try makeDirectory("shared-pages", under: tempDir)
        try write("a", to: tempDir.appendingPathComponent("shared-pages/guide.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("shared"), to: "../shared-pages")

        var followed: [URL] = []
        try projectWalk().walk(contentDirectory, onEntry: { _ in }, onFollowedDirectory: { followed.append($0) })

        XCTAssertEqual(
            followed.map { $0.resolvingSymlinksInPath().path },
            [tempDir.appendingPathComponent("shared-pages").resolvingSymlinksInPath().path]
        )
    }

    /// The default boundary needs nothing configured and can therefore not know the project,
    /// so it keeps to the tree it was pointed at.
    func testTheDefaultBoundaryRefusesALinkThatLeavesTheWalkedTree() throws {
        try makeDirectory("shared-pages", under: tempDir)
        try write("a", to: tempDir.appendingPathComponent("shared-pages/guide.md"))
        try write("b", to: contentDirectory.appendingPathComponent("index.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("shared"), to: "../shared-pages")

        let walk = SymlinkFollowingWalk(boundary: .walkedDirectory, announcesDecisions: false)

        // A refused link is skipped whole: it is not descended into and not reported.
        XCTAssertEqual(Set(try entries(of: walk).map(relativeToContent)), ["index.md"])
    }

    func testALinkOutsideTheProjectIsRefused() throws {
        try write("a", to: outsideDir.appendingPathComponent("secret.md"))
        try write("b", to: contentDirectory.appendingPathComponent("index.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("leak"), to: outsideDir.path)

        XCTAssertEqual(Set(try entries(of: projectWalk()).map(relativeToContent)), ["index.md"])
    }

    func testALinkIntoAnExcludedBuildDirectoryIsRefused() throws {
        try write("a", to: tempDir.appendingPathComponent("_site/index.html"))
        try write("b", to: contentDirectory.appendingPathComponent("index.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("built"), to: "../_site")

        XCTAssertEqual(Set(try entries(of: projectWalk()).map(relativeToContent)), ["index.md"])
    }

    /// A walk that does not terminate would hang the whole suite, so the deadline is the
    /// assertion.
    func testACycleOfLinksTerminates() throws {
        try makeDirectory("dir-a", under: tempDir)
        try makeDirectory("dir-b", under: tempDir)
        try write("a", to: tempDir.appendingPathComponent("dir-a/a.md"))
        try write("b", to: tempDir.appendingPathComponent("dir-b/b.md"))
        try makeSymbolicLink(at: tempDir.appendingPathComponent("dir-a/to-b"), to: "../dir-b")
        try makeSymbolicLink(at: tempDir.appendingPathComponent("dir-b/to-a"), to: "../dir-a")
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("shared"), to: "../dir-a")

        XCTAssertEqual(
            Set(try entries(of: projectWalk()).map(relativeToContent)),
            ["shared/a.md", "shared/to-b/b.md"]
        )
    }

    // MARK: - The watcher's use of it

    /// The fix, stated as the watcher sees it: a directory that only exists under `content/`
    /// through a symlink has to be registered with the watcher in its own right, because
    /// FSEvents watches directories by identity and never follows the link.
    func testTheWatcherRegistersADirectoryReachedThroughASymlink() async throws {
        try makeDirectory("shared-pages", under: tempDir)
        try write("a", to: tempDir.appendingPathComponent("shared-pages/guide.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("shared"), to: "../shared-pages")

        manager = HotReloadManager(
            watchPaths: [contentDirectory.path],
            debounceInterval: 0.1,
            symlinkBoundary: .project(root: tempDir.path, excludingDirectoriesNamed: ["_site"])
        ) { _ in }
        try await manager.start()

        XCTAssertTrue(
            resolved(manager.activeWatchPaths)
                .contains(tempDir.appendingPathComponent("shared-pages").resolvingSymlinksInPath().path),
            "the linked directory must be watched, or its edits are never noticed: \(manager.activeWatchPaths)"
        )
        XCTAssertTrue(resolved(manager.activeWatchPaths).contains(contentDirectory.resolvingSymlinksInPath().path))
    }

    /// The watcher must not widen what the build refused: a link the build will not publish
    /// through is not a link the watcher should be waking up for.
    func testTheWatcherLeavesALinkTheBuildRefusesAlone() async throws {
        try write("a", to: outsideDir.appendingPathComponent("secret.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("leak"), to: outsideDir.path)

        manager = HotReloadManager(
            watchPaths: [contentDirectory.path],
            debounceInterval: 0.1,
            symlinkBoundary: .project(root: tempDir.path, excludingDirectoriesNamed: ["_site"])
        ) { _ in }
        try await manager.start()

        XCTAssertEqual(
            resolved(manager.activeWatchPaths),
            [contentDirectory.resolvingSymlinksInPath().path],
            "only the content directory itself should be watched"
        )
    }

    /// A tree with no symlinks must be watched exactly as it was before any of this.
    func testATreeWithoutSymlinksIsWatchedExactlyAsBefore() async throws {
        try write("a", to: contentDirectory.appendingPathComponent("index.md"))

        manager = HotReloadManager(watchPaths: [contentDirectory.path], debounceInterval: 0.1) { _ in }
        try await manager.start()

        XCTAssertEqual(manager.activeWatchPaths, [contentDirectory.path])
    }

    // MARK: - Helpers

    private func projectWalk() -> SymlinkFollowingWalk {
        return SymlinkFollowingWalk(
            boundary: .project(root: tempDir.path, excludingDirectoriesNamed: ["_site", "static", "templates"]),
            announcesDecisions: false
        )
    }

    /// Runs the walk on a background thread with a deadline, so a traversal that fails to
    /// terminate fails this test instead of hanging the whole suite.
    private func entries(
        of walk: SymlinkFollowingWalk,
        timeout: TimeInterval = 30,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [URL] {
        let directory = contentDirectory
        let outcome = ThreadSafeBox<Result<[URL], Error>?>(nil)
        let finished = expectation(description: "walk finished")

        DispatchQueue.global().async {
            outcome.set(Result {
                var found: [URL] = []
                try walk.walk(directory) { found.append($0) }
                return found
            })
            finished.fulfill()
        }
        wait(for: [finished], timeout: timeout)

        switch outcome.get() {
        case .success(let urls):
            return urls
        case .failure(let error):
            XCTFail("Walk failed: \(error)", file: file, line: line)
            return []
        case nil:
            XCTFail("Walk did not finish within \(timeout)s", file: file, line: line)
            return []
        }
    }

    private func resolved(_ paths: [String]) -> [String] {
        return paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
    }

    /// Path of `url` relative to the content directory, folding away the `/private` prefix
    /// macOS puts in front of a temporary directory.
    private func relativeToContent(_ url: URL) -> String {
        let path = url.path
        let normalized = path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
        let base = contentDirectory.path
        guard normalized.hasPrefix(base + "/") else { return normalized }
        return String(normalized.dropFirst(base.count + 1))
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeDirectory(_ relativePath: String, under parent: URL) throws {
        try FileManager.default.createDirectory(
            at: parent.appendingPathComponent(relativePath),
            withIntermediateDirectories: true
        )
    }

    private func makeSymbolicLink(at url: URL, to destination: String) throws {
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }
}

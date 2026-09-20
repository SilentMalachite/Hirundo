import XCTest
@testable import HirundoCore

/// Pure path arithmetic. Nothing here touches the filesystem on purpose: `PathBoundary`'s whole
/// contract is that it answers from the two strings it is given, leaving symlink resolution to
/// whichever caller has a reason to want it.
final class PathBoundaryTests: XCTestCase {

    // MARK: - The root itself

    func testTreatsTheRootItselfAsContained() {
        XCTAssertTrue(PathBoundary.contains("/projects/site", in: "/projects/site"))
    }

    func testRelativePathIsEmptyAtTheRoot() {
        XCTAssertEqual(PathBoundary.relativePath(of: "/projects/site", under: "/projects/site"), "")
    }

    func testDescendantRelativePathIsNilAtTheRoot() {
        XCTAssertNil(
            PathBoundary.descendantRelativePath(of: "/projects/site", under: "/projects/site")
        )
    }

    // MARK: - Component boundaries

    func testReturnsThePathBelowTheRoot() {
        XCTAssertEqual(
            PathBoundary.relativePath(of: "/projects/site/content/posts/a.md", under: "/projects/site"),
            "content/posts/a.md"
        )
    }

    func testRejectsASiblingThatMerelySharesAPrefix() {
        // The names a prefix match would swallow: all of these start with the root's last
        // component without being anywhere inside it.
        for sibling in ["content2", "contents", "content-extra", "content-posts"] {
            XCTAssertNil(
                PathBoundary.relativePath(of: "/projects/\(sibling)/a.md", under: "/projects/content"),
                "\(sibling) is a sibling of content, not a child of it"
            )
        }
        XCTAssertFalse(PathBoundary.contains("/a/stat", in: "/a/static"))
    }

    func testRejectsAPathAboveTheRoot() {
        XCTAssertNil(PathBoundary.relativePath(of: "/projects", under: "/projects/site"))
        XCTAssertNil(PathBoundary.relativePath(of: "/elsewhere/site", under: "/projects/site"))
    }

    // MARK: - Separator handling

    func testIgnoresATrailingSeparatorOnTheRoot() {
        XCTAssertEqual(
            PathBoundary.relativePath(of: "/projects/site/a.md", under: "/projects/site/"),
            "a.md"
        )
        XCTAssertEqual(PathBoundary.relativePath(of: "/projects/site", under: "/projects/site///"), "")
    }

    func testHandlesTheFilesystemRootAsARoot() {
        XCTAssertEqual(PathBoundary.relativePath(of: "/etc/passwd", under: "/"), "etc/passwd")
        XCTAssertEqual(PathBoundary.relativePath(of: "/", under: "/"), "")
    }

    // MARK: - The resolution contract

    func testDoesNotResolveSymlinks() {
        // `/var` is a symlink to `/private/var` on macOS. Folding those together here would
        // quietly change the answer for every caller that deliberately compares unresolved
        // paths, so the contract is that this type never looks at the filesystem.
        XCTAssertFalse(PathBoundary.contains("/var/folders/x", in: "/private/var/folders"))
        XCTAssertFalse(PathBoundary.contains("/private/var/folders/x", in: "/var/folders"))
    }
}

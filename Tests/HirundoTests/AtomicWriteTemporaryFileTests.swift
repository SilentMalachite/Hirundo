import XCTest
@testable import HirundoCore

/// Pins the shape of the scratch file Foundation writes during an atomic save.
///
/// Recognising it too loosely would silently stop reporting real files, which is the one failure
/// mode a file watcher must not have.
final class AtomicWriteTemporaryFileTests: XCTestCase {
    func testTheScratchFileFoundationWritesIsRecognised() {
        for name in [
            "index.md.sb-56e0572d-GAYA6W",
            "test.md.sb-56e0572d-XH6BX0",
            "style.css.sb-56e0572d-M3yZfs",
            "a.sb-56e0572d-0cPkxk"
        ] {
            XCTAssertTrue(HotReloadManager.isAtomicWriteTemporaryFile(name), "Missed \(name)")
        }
    }

    func testOrdinaryFilesAreNotMistakenForIt() {
        for name in [
            "index.md",
            "notes.sb-file.md",
            "report.sb-abc-def",
            "x.sb--y",
            "post.sb-56e0572d",
            ".sb-56e0572d-GAYA6W-extra",
            "weird.sb-56e0572z-GAYA6W"
        ] {
            XCTAssertFalse(HotReloadManager.isAtomicWriteTemporaryFile(name), "Matched \(name)")
        }
    }
}

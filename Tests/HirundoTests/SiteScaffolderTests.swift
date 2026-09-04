import XCTest
@testable import HirundoCore

final class SiteScaffolderTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-scaffold-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testScaffold_whenDestinationEmpty_createsEssentialFiles() throws {
        let dest = tempDir.appendingPathComponent("my-site")
        let result = try SiteScaffolder().scaffold(
            at: dest,
            options: SiteScaffoldOptions(title: "My Hirundo Site", includeBlog: false)
        )

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("config.yaml").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("content/index.md").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("content/about.md").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("templates/base.html").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("templates/default.html").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("static/css/style.css").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent(".gitignore").path))
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("templates/post.html").path))
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("content/posts").path))
        XCTAssertTrue(result.createdRelativePaths.contains("config.yaml"))
    }
}

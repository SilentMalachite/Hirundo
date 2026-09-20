import XCTest
@testable import HirundoCore

/// These all touch the filesystem on purpose: the whole point of the confinement is what happens
/// when a symbolic link is sitting where a file is about to be written, and that cannot be
/// expressed in path arithmetic alone.
final class SiteFileManagerTests: XCTestCase {

    private var tempDir: URL!
    private var projectDir: URL!
    private var outputDir: URL!
    private var manager: SiteFileManager!

    private static let yaml = """
    site:
      title: "Test Site"
      url: "https://example.com"
    """

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("site-file-manager-test-\(UUID())")
        projectDir = tempDir.appendingPathComponent("project")
        outputDir = projectDir.appendingPathComponent("_site")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        manager = try makeManager(projectPath: projectDir.path)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeManager(projectPath: String) throws -> SiteFileManager {
        SiteFileManager(config: try HirundoConfig.parse(from: Self.yaml), projectPath: projectPath)
    }

    private func isSymlink(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return false
        }
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
    }

    // MARK: - writeFile

    func testWriteFileCreatesTheFileAndItsParentDirectories() throws {
        let target = outputDir.appendingPathComponent("posts/hello/index.html")
        try manager.writeFile(content: "<p>hi</p>", to: target)

        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "<p>hi</p>")
    }

    func testWriteReplacesAnOutputLeftAsASymlinkWithARegularFile() throws {
        // What an older version of Hirundo left behind, and what an attacker with write access to
        // `_site` would plant.
        let victim = tempDir.appendingPathComponent("victim.txt")
        try "do not touch".write(to: victim, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let target = outputDir.appendingPathComponent("index.html")
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: victim)

        try manager.writeFile(content: "<p>new</p>", to: target)

        XCTAssertFalse(isSymlink(target), "the link should have been taken out, not followed")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "<p>new</p>")
        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "do not touch")
    }

    func testWriteThroughASymlinkedOutputSubdirectoryIsRefused() throws {
        let outside = tempDir.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let posts = outputDir.appendingPathComponent("posts")
        try FileManager.default.createSymbolicLink(at: posts, withDestinationURL: outside)

        XCTAssertThrowsError(
            try manager.writeFile(content: "leak", to: posts.appendingPathComponent("a.html"))
        ) { error in
            guard case FileManagerError.outputPathEscapes = error else {
                return XCTFail("expected outputPathEscapes, got \(error)")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outside.appendingPathComponent("a.html").path)
        )
    }

    func testWriteOutsideTheOutputDirectoryIsRefused() throws {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let escaping = outputDir.appendingPathComponent("../secret.txt")

        XCTAssertThrowsError(try manager.writeFile(content: "leak", to: escaping)) { error in
            guard case FileManagerError.outputPathEscapes = error else {
                return XCTFail("expected outputPathEscapes, got \(error)")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: projectDir.appendingPathComponent("secret.txt").path)
        )
    }

    func testWriteToAPathWhoseLastComponentIsDotDotIsRefused() throws {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let target = URL(fileURLWithPath: outputDir.appendingPathComponent("posts").path + "/..")

        XCTAssertThrowsError(try manager.writeFile(content: "x", to: target)) { error in
            guard case FileManagerError.outputPathEscapes = error else {
                return XCTFail("expected outputPathEscapes, got \(error)")
            }
        }
    }

    func testWriteLeavesNoTemporaryFileInTheOutputDirectory() throws {
        try manager.writeFile(content: "x", to: outputDir.appendingPathComponent("a.html"))

        let contents = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
        XCTAssertEqual(contents.sorted(), ["a.html"])
    }

    func testWriteSucceedsWhenTheProjectPathGoesThroughASymlink() throws {
        // `/var` is a link to `/private/var`, so the configured path and the resolved parent
        // disagree unless the root is resolved at the time of the write. Caching the resolved
        // root at init, before the output directory exists, brings that disagreement back.
        let alias = tempDir.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: projectDir)
        let aliased = try makeManager(projectPath: alias.path)

        let target = alias.appendingPathComponent("_site/deep/page/index.html")
        try aliased.writeFile(content: "<p>ok</p>", to: target)

        XCTAssertEqual(
            try String(contentsOf: outputDir.appendingPathComponent("deep/page/index.html"), encoding: .utf8),
            "<p>ok</p>"
        )
    }

    func testWriteSucceedsWhenTheOutputRootItselfIsASymlinkToADirectory() throws {
        // `_site -> /Volumes/build/site` is a layout the asset pipeline already supports.
        let real = tempDir.appendingPathComponent("build-target")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: outputDir, withDestinationURL: real)

        try manager.writeFile(content: "<p>ok</p>", to: outputDir.appendingPathComponent("a.html"))

        XCTAssertEqual(
            try String(contentsOf: real.appendingPathComponent("a.html"), encoding: .utf8),
            "<p>ok</p>"
        )
    }

    // MARK: - createDirectory

    func testCreateDirectoryRefusesAPathOutsideTheOutputDirectory() throws {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try manager.createDirectory(at: projectDir.appendingPathComponent("elsewhere"))
        ) { error in
            guard case FileManagerError.outputPathEscapes = error else {
                return XCTFail("expected outputPathEscapes, got \(error)")
            }
        }
    }

    func testCreateDirectoryReplacesADirectorySymlinkPointingOutsideTheOutput() throws {
        let outside = tempDir.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let archive = outputDir.appendingPathComponent("archive")
        try FileManager.default.createSymbolicLink(at: archive, withDestinationURL: outside)

        try manager.createDirectory(at: archive)

        XCTAssertFalse(isSymlink(archive))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCreateDirectoryKeepsASymlinkThatStaysInsideTheOutput() throws {
        try FileManager.default.createDirectory(
            at: outputDir.appendingPathComponent("real"),
            withIntermediateDirectories: true
        )
        let alias = outputDir.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(
            at: alias,
            withDestinationURL: outputDir.appendingPathComponent("real")
        )

        try manager.createDirectory(at: alias)

        XCTAssertTrue(isSymlink(alias), "a link that stays inside the output tree is left alone")
    }

    func testCreateDirectoryRefusesAnEscapingIntermediateThatDoesNotExistYet() throws {
        // Symlink resolution is a no-op on a path that does not exist, so a single resolution of
        // `_site/a/b/c` would never see that `a` points outside. Walking the chain does.
        let outside = tempDir.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: outputDir.appendingPathComponent("a"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(
            try manager.createDirectory(at: outputDir.appendingPathComponent("a/b/c"))
        ) { error in
            guard case FileManagerError.outputPathEscapes = error else {
                return XCTFail("expected outputPathEscapes, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("b").path))
    }

    // MARK: - prepareOutputDirectory

    func testCreateDirectoryRefusesADanglingIntermediateLink() throws {
        // `resolvingSymlinksInPath()` cannot resolve a link whose target is missing, so it hands
        // the path back unchanged — inside the output root by construction, whatever the link
        // actually points at. Without a separate existence check the containment test passes and
        // the failure surfaces from Foundation as `Input/output error`, naming neither the link
        // nor the reason.
        try manager.prepareOutputDirectory(clean: true)
        try FileManager.default.createSymbolicLink(
            at: outputDir.appendingPathComponent("a"),
            withDestinationURL: tempDir.appendingPathComponent("does-not-exist")
        )

        XCTAssertThrowsError(
            try manager.createDirectory(at: outputDir.appendingPathComponent("a/b"))
        ) { error in
            guard case FileManagerError.outputPathEscapes = error else {
                return XCTFail("expected a containment error, got \(error)")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDir.appendingPathComponent("does-not-exist").path
            )
        )
    }

    func testPrepareCreatesTheConfiguredOutputDirectory() throws {
        try manager.prepareOutputDirectory(clean: false)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testPrepareWithoutCleanKeepsExistingFiles() throws {
        try manager.writeFile(content: "keep", to: outputDir.appendingPathComponent("a.html"))

        try manager.prepareOutputDirectory(clean: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.appendingPathComponent("a.html").path))
    }

    func testCleanEmptiesTheOutputDirectoryIncludingHiddenFiles() throws {
        try manager.writeFile(content: "old", to: outputDir.appendingPathComponent("a.html"))
        try manager.writeFile(content: "", to: outputDir.appendingPathComponent(".nojekyll"))

        try manager.prepareOutputDirectory(clean: true)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputDir.path), [])
    }

    func testCleanKeepsASymlinkedOutputRootAndEmptiesItsTarget() throws {
        // Removing the root would resolve the link and delete whatever it points at — for
        // `_site -> $HOME` that is the home directory.
        let real = tempDir.appendingPathComponent("build-target")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try "old".write(to: real.appendingPathComponent("a.html"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: outputDir, withDestinationURL: real)

        try manager.prepareOutputDirectory(clean: true)

        XCTAssertTrue(isSymlink(outputDir), "the link is the layout, not stale output")
        XCTAssertTrue(FileManager.default.fileExists(atPath: real.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: real.path), [])
    }

    func testPrepareThrowsWhenTheOutputPathIsAnExistingFile() throws {
        try "not a directory".write(to: outputDir, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try manager.prepareOutputDirectory(clean: false)) { error in
            guard case FileManagerError.outputRootIsNotADirectory = error else {
                return XCTFail("expected outputRootIsNotADirectory, got \(error)")
            }
        }
    }

    // MARK: - emptyOutputDirectory (shared by `build --clean` and `clean --force`)

    func testEmptyOutputDirectoryLeavesTheDirectoryItself() throws {
        try manager.writeFile(content: "old", to: outputDir.appendingPathComponent("a.html"))
        try manager.writeFile(content: "", to: outputDir.appendingPathComponent(".nojekyll"))

        try SiteFileManager.emptyOutputDirectory(at: outputDir)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputDir.path, isDirectory: &isDirectory),
            "the directory itself is not what `clean` names"
        )
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputDir.path), [])
    }

    func testEmptyOutputDirectoryKeepsALinkedRootAndEmptiesItsTarget() throws {
        // `hirundo clean --force` used to `removeItem` the root, so on this layout it took the
        // link out and the next build wrote to a fresh directory beside the volume.
        let real = tempDir.appendingPathComponent("build-target")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try "old".write(to: real.appendingPathComponent("a.html"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: outputDir, withDestinationURL: real)

        try SiteFileManager.emptyOutputDirectory(at: outputDir)

        XCTAssertTrue(isSymlink(outputDir), "the link is the layout, not stale output")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: real.path), [])
    }

    func testEmptyOutputDirectoryDoesNothingWhenThereIsNothingThere() throws {
        XCTAssertNoThrow(try SiteFileManager.emptyOutputDirectory(at: outputDir))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDir.path),
                       "emptying must not create what it did not find")
    }

    func testEmptyOutputDirectoryRefusesARootThatIsAFile() throws {
        try "not a directory".write(to: outputDir, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try SiteFileManager.emptyOutputDirectory(at: outputDir)) { error in
            guard case FileManagerError.outputRootIsNotADirectory = error else {
                return XCTFail("expected outputRootIsNotADirectory, got \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: outputDir, encoding: .utf8), "not a directory")
    }

    // MARK: - fileExists

    func testFileExistsAnswersForPathsOutsideTheOutputDirectory() throws {
        // `SiteGenerator` asks it whether `static/` is there at all, so it must not be confined.
        let staticDir = projectDir.appendingPathComponent("static")
        XCTAssertFalse(manager.fileExists(at: staticDir.path))

        try FileManager.default.createDirectory(at: staticDir, withIntermediateDirectories: true)
        XCTAssertTrue(manager.fileExists(at: staticDir.path))
    }
}

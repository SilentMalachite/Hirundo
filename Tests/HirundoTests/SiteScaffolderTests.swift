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

    func testScaffold_whenDefaultOptions_writesParseableConfig() throws {
        let dest = tempDir.appendingPathComponent("site")
        _ = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())
        let config = try HirundoConfig.load(from: dest.appendingPathComponent("config.yaml"))
        XCTAssertEqual(config.site.title, "My Hirundo Site")
        XCTAssertEqual(config.site.url, "https://example.com")
        XCTAssertEqual(config.site.language, "en-US")
        XCTAssertEqual(config.build.contentDirectory, "content")
        XCTAssertEqual(config.server.port, 8080)
        XCTAssertTrue(config.features.sitemap)
        XCTAssertFalse(config.features.rss)
        XCTAssertFalse(config.features.minify)
        XCTAssertFalse(config.blog.generateArchive)
        XCTAssertFalse(config.blog.generateCategories)
        XCTAssertFalse(config.blog.generateTags)
    }

    func testScaffold_whenBlogEnabled_createsPostTemplateAndSamplePost() throws {
        let dest = tempDir.appendingPathComponent("blog")
        _ = try SiteScaffolder().scaffold(
            at: dest,
            options: SiteScaffoldOptions(includeBlog: true)
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("templates/post.html").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("content/posts/hello-world.md").path))
        let config = try HirundoConfig.load(from: dest.appendingPathComponent("config.yaml"))
        XCTAssertTrue(config.features.rss)
        XCTAssertTrue(config.blog.generateArchive)
        XCTAssertTrue(config.blog.generateCategories)
        XCTAssertTrue(config.blog.generateTags)
        let base = try String(contentsOf: dest.appendingPathComponent("templates/base.html"), encoding: .utf8)
        XCTAssertTrue(base.contains("/archive/"))
    }

    func testScaffold_whenDestinationHasOnlyGit_succeedsWithoutForce() throws {
        let dest = tempDir.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: dest.appendingPathComponent(".git"), withIntermediateDirectories: true)
        _ = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("config.yaml").path))
    }

    func testScaffold_whenDestinationNotEmpty_throwsWithoutForce() throws {
        let dest = tempDir.appendingPathComponent("full")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try "keep".write(to: dest.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(
            try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())
        ) { error in
            guard case ScaffoldError.destinationNotEmpty = error else {
                return XCTFail("expected destinationNotEmpty, got \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("notes.txt").path))
    }

    func testScaffold_whenForce_overwritesOwnedFilesAndKeepsOthers() throws {
        let dest = tempDir.appendingPathComponent("full")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try "keep".write(to: dest.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "old".write(to: dest.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        _ = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions(title: "Forced", force: true))
        let yaml = try String(contentsOf: dest.appendingPathComponent("config.yaml"), encoding: .utf8)
        XCTAssertTrue(yaml.contains("Forced"))
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("notes.txt"), encoding: .utf8), "keep")
    }

    func testScaffold_whenTitleEmpty_throwsInvalidTitle() {
        let dest = tempDir.appendingPathComponent("t")
        XCTAssertThrowsError(
            try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions(title: "   "))
        ) { error in
            guard case ScaffoldError.invalidTitle = error else {
                return XCTFail("expected invalidTitle, got \(error)")
            }
        }
    }

    func testScaffold_whenTitleContainsQuotes_writesValidYAML() throws {
        let dest = tempDir.appendingPathComponent("q")
        _ = try SiteScaffolder().scaffold(
            at: dest,
            options: SiteScaffoldOptions(title: #"Alice's "Blog""#)
        )
        let config = try HirundoConfig.load(from: dest.appendingPathComponent("config.yaml"))
        XCTAssertEqual(config.site.title, #"Alice's "Blog""#)
    }

    func testScaffold_whenBlogEnabled_siteGeneratorBuildSucceeds() async throws {
        let dest = tempDir.appendingPathComponent("built")
        _ = try SiteScaffolder().scaffold(
            at: dest,
            options: SiteScaffoldOptions(title: "Built Site", includeBlog: true)
        )
        let generator = try SiteGenerator(projectPath: dest.path)
        try await generator.build(clean: true)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("_site/index.html").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("_site/about/index.html").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("_site/posts/hello-world/index.html").path))
    }

    func testScaffold_whenExistingGitignoreWithoutForce_preservesContentAndAddsSiteIgnore() throws {
        let dest = tempDir.appendingPathComponent("repo")
        let fm = FileManager.default
        try fm.createDirectory(at: dest.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let gitignore = dest.appendingPathComponent(".gitignore")
        try "*.log\n".write(to: gitignore, atomically: true, encoding: .utf8)

        _ = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())

        let contents = try String(contentsOf: gitignore, encoding: .utf8)
        XCTAssertTrue(contents.contains("*.log"))
        XCTAssertTrue(contents.contains("_site/"))
    }

    func testScaffold_whenForceAndExistingGitignore_preservesUserRules() throws {
        let dest = tempDir.appendingPathComponent("forced-repo")
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let gitignore = dest.appendingPathComponent(".gitignore")
        try "node_modules/\n*.log\nsecrets.env\n".write(to: gitignore, atomically: true, encoding: .utf8)

        _ = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions(force: true))

        let contents = try String(contentsOf: gitignore, encoding: .utf8)
        XCTAssertTrue(contents.contains("node_modules/"))
        XCTAssertTrue(contents.contains("*.log"))
        XCTAssertTrue(contents.contains("secrets.env"))
        XCTAssertTrue(contents.contains("_site/"))
    }

    func testScaffold_whenGitignoreMerged_reportsItAsModifiedNotCreated() throws {
        let dest = tempDir.appendingPathComponent("merged-report")
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try "*.log\n".write(to: dest.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        let result = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())

        XCTAssertTrue(result.modifiedRelativePaths.contains(".gitignore"))
        XCTAssertFalse(result.createdRelativePaths.contains(".gitignore"))
    }

    func testScaffold_whenGitignoreCreated_isReportedAsCreatedAndNotModified() throws {
        let dest = tempDir.appendingPathComponent("fresh-report")
        let result = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())

        XCTAssertTrue(result.createdRelativePaths.contains(".gitignore"))
        XCTAssertTrue(result.modifiedRelativePaths.isEmpty)
    }

    func testScaffold_whenGitignoreAlreadyIgnoresSite_reportsNoModification() throws {
        let dest = tempDir.appendingPathComponent("already-ignored")
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try "_site/\n".write(to: dest.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        let result = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())

        XCTAssertTrue(result.modifiedRelativePaths.isEmpty)
        XCTAssertFalse(result.createdRelativePaths.contains(".gitignore"))
    }

    func testScaffoldResult_memberwiseInitRemainsSourceCompatible() {
        let result = SiteScaffoldResult(
            destination: URL(fileURLWithPath: "/tmp/x"),
            createdRelativePaths: ["config.yaml"]
        )
        XCTAssertEqual(result.modifiedRelativePaths, [])
    }

    /// Scaffolds into a directory whose `.gitignore` already holds `existing`, and returns
    /// the resulting file contents together with whether the scaffolder reported a change.
    private func scaffoldOntoGitignore(
        _ existing: String,
        name: String
    ) throws -> (contents: String, reportedModified: Bool) {
        let dest = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let gitignore = dest.appendingPathComponent(".gitignore")
        try existing.write(to: gitignore, atomically: true, encoding: .utf8)

        let result = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())

        return (
            try String(contentsOf: gitignore, encoding: .utf8),
            result.modifiedRelativePaths.contains(".gitignore")
        )
    }

    private func assertGitignoreUnchanged(
        _ existing: String,
        name: String,
        line: UInt = #line
    ) throws {
        let (contents, modified) = try scaffoldOntoGitignore(existing, name: name)
        XCTAssertEqual(contents, existing, "\(name) should not have been rewritten", line: line)
        XCTAssertFalse(modified, "\(name) should not be reported as modified", line: line)
    }

    func testScaffold_whenGitignoreAnchorsSiteWithLeadingSlash_isRecognizedAsAlreadyIgnored() throws {
        try assertGitignoreUnchanged("*.log\n/_site/\n", name: "gi-anchored")
    }

    func testScaffold_whenGitignoreUsesSiteWildcard_isRecognizedAsAlreadyIgnored() throws {
        try assertGitignoreUnchanged("*.log\n_site/*\n", name: "gi-wildcard")
    }

    func testScaffold_whenGitignoreUsesAnchoredSiteWildcard_isRecognizedAsAlreadyIgnored() throws {
        try assertGitignoreUnchanged("*.log\n/_site/*\n", name: "gi-anchored-wildcard")
    }

    func testScaffold_whenGitignoreHasBareSite_isRecognizedAsAlreadyIgnored() throws {
        try assertGitignoreUnchanged("*.log\n_site\n", name: "gi-bare")
    }

    func testScaffold_whenGitignoreHasSiteWithTrailingSlash_isRecognizedAsAlreadyIgnored() throws {
        try assertGitignoreUnchanged("*.log\n_site/\n", name: "gi-slash")
    }

    func testScaffold_whenGitignoreOnlyMentionsSiteInComment_appendsRule() throws {
        let existing = "*.log\n# _site/\n"
        let (contents, modified) = try scaffoldOntoGitignore(existing, name: "gi-comment")
        XCTAssertEqual(contents, existing + "_site/\n")
        XCTAssertTrue(modified)
    }

    func testScaffold_whenGitignoreNegatesSite_appendsRule() throws {
        let existing = "*.log\n!_site/\n"
        let (contents, modified) = try scaffoldOntoGitignore(existing, name: "gi-negation")
        XCTAssertEqual(contents, existing + "_site/\n")
        XCTAssertTrue(modified)
    }

    func testScaffold_whenRunTwice_isIdempotentForGitignore() throws {
        let dest = tempDir.appendingPathComponent("idempotent")
        _ = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())
        let afterFirst = try String(contentsOf: dest.appendingPathComponent(".gitignore"), encoding: .utf8)

        let second = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions(force: true))
        let afterSecond = try String(contentsOf: dest.appendingPathComponent(".gitignore"), encoding: .utf8)

        XCTAssertEqual(afterFirst, afterSecond)
        XCTAssertTrue(second.modifiedRelativePaths.isEmpty)
    }

    func testScaffold_createsEachNeededDirectoryExactlyOnce() throws {
        let dest = tempDir.appendingPathComponent("counted")
        let fm = CountingFileManager()

        _ = try SiteScaffolder(fileManager: fm).scaffold(at: dest, options: SiteScaffoldOptions())

        // Exactly the destination root, content/, templates/ and static/css/ — no repeats.
        XCTAssertEqual(fm.createDirectoryPaths.count, 4, "created: \(fm.createDirectoryPaths)")
        XCTAssertEqual(Set(fm.createDirectoryPaths).count, fm.createDirectoryPaths.count,
                       "duplicate createDirectory calls: \(fm.createDirectoryPaths)")
    }

    func testScaffold_whenBlogEnabled_createsEachNeededDirectoryExactlyOnce() throws {
        let dest = tempDir.appendingPathComponent("counted-blog")
        let fm = CountingFileManager()

        _ = try SiteScaffolder(fileManager: fm).scaffold(
            at: dest,
            options: SiteScaffoldOptions(includeBlog: true)
        )

        // The four above plus content/posts/.
        XCTAssertEqual(fm.createDirectoryPaths.count, 5, "created: \(fm.createDirectoryPaths)")
        XCTAssertEqual(Set(fm.createDirectoryPaths).count, fm.createDirectoryPaths.count,
                       "duplicate createDirectory calls: \(fm.createDirectoryPaths)")
    }

    func testScaffold_whenSubdirectoryCannotBeCreated_throwsCannotCreateDirectory() {
        let dest = tempDir.appendingPathComponent("nosubdir")
        // Call 1 creates the destination root; call 2 is the first subdirectory a file needs.
        let fm = FailingFileManager(failOnCreateDirectoryCall: 2)

        XCTAssertThrowsError(
            try SiteScaffolder(fileManager: fm).scaffold(at: dest, options: SiteScaffoldOptions())
        ) { error in
            guard case ScaffoldError.cannotCreateDirectory = error else {
                return XCTFail("expected cannotCreateDirectory, got \(error)")
            }
        }
    }

    func testScaffold_whenWriteFailsMidway_removesNewlyCreatedDestination() {
        let dest = tempDir.appendingPathComponent("partial")
        let fm = FailingFileManager(failOnCreateDirectoryCall: 4)

        XCTAssertThrowsError(
            try SiteScaffolder(fileManager: fm).scaffold(at: dest, options: SiteScaffoldOptions())
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    }

    func testScaffold_whenWriteFailsMidway_removesIntermediateDirectoriesItCreated() {
        let outer = tempDir.appendingPathComponent("outer")
        let dest = outer.appendingPathComponent("inner")
        let fm = FailingFileManager(failOnCreateDirectoryCall: 4)

        XCTAssertThrowsError(
            try SiteScaffolder(fileManager: fm).scaffold(at: dest, options: SiteScaffoldOptions())
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: outer.path))
    }

    func testScaffold_whenWriteFailsAndDestinationPreexisted_keepsDestinationDirectory() throws {
        let dest = tempDir.appendingPathComponent("existing")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let fm = FailingFileManager(failOnCreateDirectoryCall: 4)

        XCTAssertThrowsError(
            try SiteScaffolder(fileManager: fm).scaffold(at: dest, options: SiteScaffoldOptions())
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        // Pins what `failOnCreateDirectoryCall: 4` is for: the scaffold must be interrupted
        // partway, after at least one file has been written and before it completes.
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: dest.appendingPathComponent("config.yaml").path),
            "expected the failure to interrupt the scaffold after some files were written"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dest.appendingPathComponent("static/css/style.css").path),
            "expected the failure to interrupt the scaffold before it completed"
        )
    }

    func testScaffold_whenDestinationIsFile_throwsDestinationIsFile() throws {
        let dest = tempDir.appendingPathComponent("not-a-dir")
        try "I am a file".write(to: dest, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())
        ) { error in
            guard case ScaffoldError.destinationIsFile(let path) = error else {
                return XCTFail("expected destinationIsFile, got \(error)")
            }
            XCTAssertEqual(path, dest.path)
        }
        // The existing file must be left exactly as it was.
        XCTAssertEqual(try? String(contentsOf: dest, encoding: .utf8), "I am a file")
    }

    func testScaffold_whenDestinationIsFileAndForced_stillThrowsDestinationIsFile() throws {
        let dest = tempDir.appendingPathComponent("forced-file")
        try "I am a file".write(to: dest, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions(force: true))
        ) { error in
            guard case ScaffoldError.destinationIsFile = error else {
                return XCTFail("expected destinationIsFile, got \(error)")
            }
        }
        XCTAssertEqual(try? String(contentsOf: dest, encoding: .utf8), "I am a file")
    }

    func testScaffold_whenDestinationCannotBeListed_throwsCannotReadDirectory() throws {
        let dest = tempDir.appendingPathComponent("unlistable")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let fm = UnlistableDirectoryFileManager()

        XCTAssertThrowsError(
            try SiteScaffolder(fileManager: fm).scaffold(at: dest, options: SiteScaffoldOptions())
        ) { error in
            guard case ScaffoldError.cannotReadDirectory(let path) = error else {
                return XCTFail("expected cannotReadDirectory, got \(error)")
            }
            XCTAssertEqual(path, dest.path)
        }
    }

    func testScaffold_whenExistingGitignoreIsNotUTF8_throwsCannotReadFile() throws {
        let dest = tempDir.appendingPathComponent("latin1-repo")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let gitignore = dest.appendingPathComponent(".gitignore")
        // "*.log\nrésumé\n" encoded as Latin-1: 0xE9 is not valid UTF-8.
        try Data([0x2A, 0x2E, 0x6C, 0x6F, 0x67, 0x0A, 0x72, 0xE9, 0x0A])
            .write(to: gitignore)

        XCTAssertThrowsError(
            try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())
        ) { error in
            guard case ScaffoldError.cannotReadFile(let path) = error else {
                return XCTFail("expected cannotReadFile, got \(error)")
            }
            XCTAssertEqual(path, gitignore.path)
        }
    }

    func testScaffoldError_readCases_haveDistinctDescriptionsAndCodes() {
        XCTAssertEqual(
            ScaffoldError.cannotReadDirectory("/p").errorDescription,
            "Could not read directory: /p"
        )
        XCTAssertEqual(
            ScaffoldError.cannotReadFile("/p").errorDescription,
            "Could not read file: /p"
        )
        XCTAssertEqual(ScaffoldError.cannotReadDirectory("/p").toHirundoError().code, "READ_DIR_FAILED")
        XCTAssertEqual(ScaffoldError.cannotReadFile("/p").toHirundoError().code, "READ_FILE_FAILED")
    }

    func testScaffold_whenTitleContainsNewline_throwsInvalidTitle() {
        let dest = tempDir.appendingPathComponent("nl")
        XCTAssertThrowsError(
            try SiteScaffolder().scaffold(
                at: dest,
                options: SiteScaffoldOptions(title: "Foo\nBar")
            )
        ) { error in
            guard case ScaffoldError.invalidTitle = error else {
                return XCTFail("expected invalidTitle, got \(error)")
            }
        }
    }

    func testScaffold_whenTitleContainsLineSeparator_throwsInvalidTitle() {
        let dest = tempDir.appendingPathComponent("u2028")
        XCTAssertThrowsError(
            try SiteScaffolder().scaffold(
                at: dest,
                options: SiteScaffoldOptions(title: "Foo\u{2028}Bar")
            )
        ) { error in
            guard case ScaffoldError.invalidTitle = error else {
                return XCTFail("expected invalidTitle, got \(error)")
            }
        }
    }

    func testScaffold_whenTitleContainsParagraphSeparator_throwsInvalidTitle() {
        let dest = tempDir.appendingPathComponent("u2029")
        XCTAssertThrowsError(
            try SiteScaffolder().scaffold(
                at: dest,
                options: SiteScaffoldOptions(title: "Foo\u{2029}Bar")
            )
        ) { error in
            guard case ScaffoldError.invalidTitle = error else {
                return XCTFail("expected invalidTitle, got \(error)")
            }
        }
    }

    func testScaffold_whenTitleContainsCarriageReturn_throwsInvalidTitle() {
        let dest = tempDir.appendingPathComponent("ucr")
        XCTAssertThrowsError(
            try SiteScaffolder().scaffold(
                at: dest,
                options: SiteScaffoldOptions(title: "Foo\r\nBar")
            )
        ) { error in
            guard case ScaffoldError.invalidTitle = error else {
                return XCTFail("expected invalidTitle, got \(error)")
            }
        }
    }

    func testScaffold_whenTitleContainsNonASCIILetters_isAccepted() throws {
        let dest = tempDir.appendingPathComponent("intl")
        _ = try SiteScaffolder().scaffold(
            at: dest,
            options: SiteScaffoldOptions(title: "日本語のサイト — Café")
        )
        let config = try HirundoConfig.load(from: dest.appendingPathComponent("config.yaml"))
        XCTAssertEqual(config.site.title, "日本語のサイト — Café")
    }

    /// `configYAML` derives `features.rss` and the three `blog.generate*` flags from the same
    /// `includeBlog` input, so they must never disagree. Pins them as one group at the template
    /// level, where the existing scaffold tests only reach them through `SiteScaffolder`.
    func testConfigYAML_keepsRSSAndBlogGenerationFlagsInLockstep() throws {
        for includeBlog in [false, true] {
            let yaml = ScaffoldTemplates.configYAML(title: "Flag Site", includeBlog: includeBlog)
            let file = tempDir.appendingPathComponent("flags-\(includeBlog).yaml")
            try yaml.write(to: file, atomically: true, encoding: .utf8)

            let config = try HirundoConfig.load(from: file)
            XCTAssertEqual(config.features.rss, includeBlog,
                           "features.rss with includeBlog=\(includeBlog)")
            XCTAssertEqual(config.blog.generateArchive, includeBlog,
                           "blog.generateArchive with includeBlog=\(includeBlog)")
            XCTAssertEqual(config.blog.generateCategories, includeBlog,
                           "blog.generateCategories with includeBlog=\(includeBlog)")
            XCTAssertEqual(config.blog.generateTags, includeBlog,
                           "blog.generateTags with includeBlog=\(includeBlog)")
        }
    }

    func testHelloWorldPost_whenGivenDate_writesThatInstantAsISO8601UTC() {
        // 1_700_000_000 seconds after the epoch is 2023-11-14T22:13:20Z.
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)

        let post = ScaffoldTemplates.helloWorldPost(date: fixed)

        XCTAssertTrue(post.contains("date: 2023-11-14T22:13:20Z"),
                      "expected the injected instant in the front matter, got:\n\(post)")
    }

    func testHelloWorldPost_whenDateDefaulted_isDatedNowNotAFrozenConstant() throws {
        let before = Date()
        let post = ScaffoldTemplates.helloWorldPost()
        let after = Date()

        XCTAssertFalse(post.contains("2026-01-01T00:00:00Z"),
                       "the sample post must not carry a hardcoded date")
        let emitted = try XCTUnwrap(Self.frontMatterDate(in: post),
                                    "no parseable ISO 8601 date in:\n\(post)")
        // ISO 8601 output is whole-second, so allow a second of slack on either side.
        XCTAssertGreaterThanOrEqual(emitted, before.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(emitted, after.addingTimeInterval(1))
    }

    /// Parses the `date:` line out of a scaffolded post's front matter, using the same
    /// format `ContentProcessor` accepts.
    private static func frontMatterDate(in post: String) -> Date? {
        let prefix = "date: "
        guard let line = post.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: String(line.dropFirst(prefix.count)))
    }

    func testScaffold_whenBlogDisabled_buildDoesNotWriteArchive() async throws {
        let dest = tempDir.appendingPathComponent("noblog")
        _ = try SiteScaffolder().scaffold(at: dest, options: SiteScaffoldOptions())
        let generator = try SiteGenerator(projectPath: dest.path)
        try await generator.build(clean: true)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("_site/archive").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("_site/categories").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("_site/tags").path))
    }

    // MARK: - Escaping in the scaffolded templates

    /// Stencil escapes nothing on its own, so a scaffolded template that interpolates a value
    /// without `|escape` publishes whatever an author wrote in `config.yaml` or in front matter
    /// as markup. The rule is "every interpolation except `{{ content }}`", which is checkable.
    func testEveryInterpolationInTheScaffoldedTemplatesIsEscapedExceptTheRenderedContent() throws {
        let templates = [
            "base.html": ScaffoldTemplates.baseHTML(includeBlog: true),
            "default.html": ScaffoldTemplates.defaultHTML,
            "post.html": ScaffoldTemplates.postHTML,
        ]
        let interpolation = try NSRegularExpression(pattern: "\\{\\{(.+?)\\}\\}")

        for (name, body) in templates {
            let range = NSRange(body.startIndex..., in: body)
            for match in interpolation.matches(in: body, range: range) {
                guard let r = Range(match.range(at: 1), in: body) else { continue }
                let expression = body[r].trimmingCharacters(in: .whitespaces)
                if expression == "content" { continue }
                XCTAssertTrue(
                    expression.hasSuffix("|escape"),
                    "\(name): {{ \(expression) }} is interpolated without |escape"
                )
            }
        }
    }

    func testTheScaffoldedTemplatesDoNotEscapeTheRenderedContent() throws {
        XCTAssertTrue(ScaffoldTemplates.defaultHTML.contains("{{ content }}"))
        XCTAssertTrue(ScaffoldTemplates.postHTML.contains("{{ content }}"))
    }

    func testTheScaffoldedTemplatesEscapeEveryValueTheyRender() throws {
        let dest = tempDir.appendingPathComponent("render-check")
        _ = try SiteScaffolder().scaffold(
            at: dest, options: SiteScaffoldOptions(title: "My Site", includeBlog: true)
        )

        let engine = TemplateEngine(
            templatesDirectory: dest.appendingPathComponent("templates").path
        )
        // The scaffolded templates link through `relative_url`, which is a dynamic filter — it
        // exists only once the engine has a site config, which is what `SiteTemplateRenderer`
        // does for a real build.
        engine.configure(with: try Site(
            title: "My Site", description: nil, url: "https://example.com",
            language: nil, author: nil
        ))
        let context: [String: Any] = [
            "site": [
                "title": "Tom & Jerry",
                "language": "en-US",
                "author": ["name": "<b>Author</b>"],
            ],
            "page": [
                "title": "A \"quoted\" title",
                "date": Date(timeIntervalSince1970: 0),
                "categories": ["a <b>bold</b> category"],
                "tags": ["a <b>bold</b> tag"],
            ],
            "content": "<p>body</p>",
        ]

        let rendered = try engine.render(template: "post.html", context: context)
        XCTAssertTrue(rendered.contains("Tom &amp; Jerry"))
        XCTAssertTrue(rendered.contains("A &quot;quoted&quot; title"))
        XCTAssertTrue(rendered.contains("&lt;b&gt;Author&lt;/b&gt;"))
        XCTAssertFalse(rendered.contains("<b>bold</b>"))
        XCTAssertTrue(rendered.contains("<p>body</p>"), "the rendered body must not be escaped")
    }
}

/// A `FileManager` that fails the nth `createDirectory` call, so scaffolding can be
/// interrupted partway through without touching the real filesystem's permissions.
private final class FailingFileManager: FileManager {
    private let failOnCreateDirectoryCall: Int
    private var createDirectoryCallCount = 0

    init(failOnCreateDirectoryCall: Int) {
        self.failOnCreateDirectoryCall = failOnCreateDirectoryCall
        super.init()
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        createDirectoryCallCount += 1
        if createDirectoryCallCount == failOnCreateDirectoryCall {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }
}

/// A `FileManager` that records every `createDirectory` call so tests can assert that a
/// scaffold creates each directory it needs exactly once.
private final class CountingFileManager: FileManager {
    private(set) var createDirectoryPaths: [String] = []

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        createDirectoryPaths.append(url.standardizedFileURL.path)
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }
}

/// A `FileManager` whose directory listing always fails, standing in for an existing
/// destination the process may enter but not read (e.g. mode 0300).
private final class UnlistableDirectoryFileManager: FileManager {
    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        throw CocoaError(.fileReadNoPermission)
    }
}

final class POSIXShellQuotingTests: XCTestCase {
    func testPosixShellQuoted_whenPathContainsSpacesAndQuotes_escapesForSingleQuotes() {
        XCTAssertEqual("my-site".posixShellQuoted, "'my-site'")
        XCTAssertEqual("My Site".posixShellQuoted, "'My Site'")
        XCTAssertEqual("it's".posixShellQuoted, "'it'\\''s'")
    }
}

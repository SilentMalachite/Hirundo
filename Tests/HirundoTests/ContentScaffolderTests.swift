import XCTest
@testable import HirundoCore

final class ContentScaffolderTests: XCTestCase {
    var projectRoot: URL!

    override func setUp() {
        super.setUp()
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-content-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: projectRoot)
        super.tearDown()
    }

    // MARK: - Helpers

    private func scaffold(
        kind: ContentKind,
        _ options: ContentScaffoldOptions,
        build: Build = Build.defaultBuild(),
        limits: Limits = Limits(),
        date: Date = Date(timeIntervalSince1970: 1_772_000_000)
    ) throws -> ContentScaffoldResult {
        try ContentScaffolder().scaffold(
            in: projectRoot,
            build: build,
            limits: limits,
            kind: kind,
            options: options,
            date: date
        )
    }

    private func frontMatter(at url: URL) throws -> [String: Any] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = try MarkdownParser().parse(text)
        return try XCTUnwrap(parsed.frontMatter)
    }

    private func assertThrows(
        _ expected: ContentScaffoldError,
        _ body: () throws -> ContentScaffoldResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try body()
            XCTFail("Expected \(expected), but the call succeeded", file: file, line: line)
        } catch let error as ContentScaffoldError {
            switch (error, expected) {
            case (.invalidTitle, .invalidTitle),
                 (.invalidSlug, .invalidSlug),
                 (.invalidPath, .invalidPath),
                 (.invalidMetadata, .invalidMetadata),
                 (.fileExists, .fileExists),
                 (.cannotCreateDirectory, .cannotCreateDirectory),
                 (.cannotWriteFile, .cannotWriteFile):
                break
            default:
                XCTFail("Expected \(expected), got \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("Expected \(expected), got \(error)", file: file, line: line)
        }
    }

    /// Asserts that a rejected call wrote nothing: input is validated before the content
    /// directory is touched, so not even an empty `content/` may be left behind.
    private func assertNothingWasCreated(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: projectRoot.appendingPathComponent("content").path
            ),
            "Rejected input must not create anything",
            file: file,
            line: line
        )
    }

    // MARK: - Post: location

    func testPost_landsUnderContentPosts() throws {
        let result = try scaffold(kind: .post, ContentScaffoldOptions(title: "Hello World"))

        XCTAssertEqual(result.relativePath, "content/posts/hello-world.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testPost_honoursAnExplicitSlug() throws {
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(title: "Hello World", slug: "custom-name")
        )

        XCTAssertEqual(result.relativePath, "content/posts/custom-name.md")
    }

    func testPost_slugifiesNonASCIITitles() throws {
        let result = try scaffold(kind: .post, ContentScaffoldOptions(title: "こんにちは"))

        // slugify percent-encodes non-ASCII, so the name stays URL-safe.
        XCTAssertTrue(result.relativePath.hasPrefix("content/posts/"))
        XCTAssertTrue(result.relativePath.hasSuffix(".md"))
        XCTAssertFalse(result.relativePath.contains("こんにちは"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testPost_truncatesNamesToTheFilenameLimit() throws {
        let longTitle = String(repeating: "a", count: 300)
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(title: longTitle),
            limits: Limits(maxFilenameLength: 40, maxTitleLength: 500)
        )

        let name = URL(fileURLWithPath: result.relativePath).lastPathComponent
        XCTAssertLessThanOrEqual(name.count, 40, "Got a \(name.count)-character name: \(name)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    /// A derived slug that truncates back to nothing must not become a hidden `.md` file.
    func testPost_fallsBackToUntitledWhenTheDerivedSlugTruncatesToNothing() throws {
        // slugify cuts this to 37 hyphens, then trims hyphens off both ends, leaving "".
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(title: String(repeating: "-", count: 60)),
            limits: Limits(maxFilenameLength: 40)
        )

        XCTAssertEqual(result.relativePath, "content/posts/untitled.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    /// An explicit `--slug` is used verbatim: it is not slugified, so whatever the user
    /// types becomes the file name and therefore the URL segment. Deliberate — a strict
    /// charset would refuse legitimate names like `Café-2026`.
    func testPost_usesAnExplicitSlugVerbatimIncludingSpaces() throws {
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(title: "T", slug: "My Post!")
        )

        XCTAssertEqual(result.relativePath, "content/posts/My Post!.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testPost_usesAnExplicitSlugVerbatimIncludingNonASCII() throws {
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(title: "T", slug: "café-2026")
        )

        XCTAssertEqual(result.relativePath, "content/posts/café-2026.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testPost_respectsACustomContentDirectory() throws {
        let build = try Build(contentDirectory: "docs")
        let result = try scaffold(kind: .post, ContentScaffoldOptions(title: "Hello"), build: build)

        XCTAssertEqual(result.relativePath, "docs/posts/hello.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    // MARK: - Post: content

    func testPost_writesParseableFrontMatter() throws {
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(
                title: "Hello World",
                categories: ["swift"],
                tags: ["ssg", "web"],
                draft: true
            )
        )
        let fm = try frontMatter(at: result.url)

        XCTAssertEqual(fm["title"] as? String, "Hello World")
        XCTAssertEqual(fm["template"] as? String, "post.html")
        XCTAssertEqual(fm["categories"] as? [String], ["swift"])
        XCTAssertEqual(fm["tags"] as? [String], ["ssg", "web"])
        XCTAssertEqual(fm["draft"] as? Bool, true)
        XCTAssertNotNil(fm["date"])
        XCTAssertNil(fm["slug"], "The file name is the only source of the slug")
    }

    func testPost_honoursAnExplicitTemplate() throws {
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(title: "Hello", template: "custom.html")
        )

        XCTAssertEqual(try frontMatter(at: result.url)["template"] as? String, "custom.html")
    }

    // MARK: - Page

    func testPage_landsDirectlyUnderContent() throws {
        let result = try scaffold(kind: .page, ContentScaffoldOptions(title: "About Us"))

        XCTAssertEqual(result.relativePath, "content/about-us.md")
        XCTAssertEqual(try frontMatter(at: result.url)["template"] as? String, "default.html")
        XCTAssertNil(try frontMatter(at: result.url)["date"])
    }

    func testPage_honoursANestedPathAndCreatesDirectories() throws {
        let result = try scaffold(
            kind: .page,
            ContentScaffoldOptions(title: "Team", path: "about/team")
        )

        XCTAssertEqual(result.relativePath, "content/about/team.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    func testPage_doesNotDoubleTheMarkdownExtension() throws {
        let result = try scaffold(
            kind: .page,
            ContentScaffoldOptions(title: "Team", path: "about/team.md")
        )

        XCTAssertEqual(result.relativePath, "content/about/team.md")
    }

    func testPage_prefersPathOverSlug() throws {
        let result = try scaffold(
            kind: .page,
            ContentScaffoldOptions(title: "Team", slug: "ignored", path: "about/team")
        )

        XCTAssertEqual(result.relativePath, "content/about/team.md")
    }

    // MARK: - Rejections

    func testRejectsAnEmptyTitle() {
        assertThrows(.invalidTitle("")) {
            try scaffold(kind: .page, ContentScaffoldOptions(title: "   "))
        }
    }

    func testRejectsATitleOverTheLimit() {
        assertThrows(.invalidTitle("")) {
            try scaffold(
                kind: .page,
                ContentScaffoldOptions(title: String(repeating: "a", count: 201)),
                limits: Limits(maxTitleLength: 200)
            )
        }
    }

    func testRejectsTitlesWithLineSeparators() {
        // U+2028 survives CharacterSet.controlCharacters but a YAML parser folds it to a
        // space, so the title would not round-trip.
        assertThrows(.invalidTitle("")) {
            try scaffold(kind: .page, ContentScaffoldOptions(title: "Hello\u{2028}World"))
        }
    }

    func testRejectsTitlesWithControlCharacters() {
        assertThrows(.invalidTitle("")) {
            try scaffold(kind: .page, ContentScaffoldOptions(title: "Hello\u{0007}World"))
        }
    }

    func testRejectsASlugContainingAPathSeparator() {
        assertThrows(.invalidSlug("")) {
            try scaffold(kind: .post, ContentScaffoldOptions(title: "T", slug: "a/b"))
        }
    }

    func testRejectsASlugTraversingUpwards() {
        assertThrows(.invalidSlug("")) {
            try scaffold(kind: .post, ContentScaffoldOptions(title: "T", slug: ".."))
        }
    }

    func testRejectsAPathTraversingUpwards() {
        assertThrows(.invalidPath("")) {
            try scaffold(kind: .page, ContentScaffoldOptions(title: "T", path: "../outside"))
        }
    }

    func testRejectsAnAbsolutePath() {
        assertThrows(.invalidPath("")) {
            try scaffold(kind: .page, ContentScaffoldOptions(title: "T", path: "/etc/passwd"))
        }
    }

    func testRejectsAPathThatSanitizesToNothing() {
        assertThrows(.invalidPath("")) {
            try scaffold(kind: .page, ContentScaffoldOptions(title: "T", path: "   "))
        }
    }

    /// `--path` enforces the same file name limit `--slug` does, so an over-long name is
    /// rejected as bad input rather than surfacing as an ENAMETOOLONG write failure.
    func testRejectsAPathComponentOverTheFilenameLimit() {
        assertThrows(.invalidPath("")) {
            try scaffold(
                kind: .page,
                ContentScaffoldOptions(title: "T", path: "a/" + String(repeating: "b", count: 300))
            )
        }
    }

    /// The limit is per component: many short directory names are legitimate however deep.
    func testAcceptsADeepPathOfShortComponents() throws {
        let result = try scaffold(
            kind: .page,
            ContentScaffoldOptions(title: "T", path: "a/b/c/d/e/f/g/h/deep"),
            limits: Limits(maxFilenameLength: 20)
        )

        XCTAssertEqual(result.relativePath, "content/a/b/c/d/e/f/g/h/deep.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
    }

    // MARK: - Front-matter values other than the title

    /// `yamlQuoted` escapes only `\` and `"`, so a control character would be written raw
    /// into the scalar and the generated file would fail to parse at build time — long
    /// after `hirundo new` said it succeeded.
    func testRejectsATagWithAControlCharacter() {
        assertThrows(.invalidMetadata(.tags, "")) {
            try scaffold(
                kind: .post,
                ContentScaffoldOptions(title: "T", tags: ["swift\u{0007}web"])
            )
        }
        assertNothingWasCreated()
    }

    func testRejectsACategoryWithAControlCharacter() {
        assertThrows(.invalidMetadata(.categories, "")) {
            try scaffold(
                kind: .post,
                ContentScaffoldOptions(title: "T", categories: ["news\u{0001}"])
            )
        }
        assertNothingWasCreated()
    }

    /// A line break would end the double-quoted scalar and break the front matter outright.
    func testRejectsATemplateWithANewline() {
        assertThrows(.invalidMetadata(.template, "")) {
            try scaffold(
                kind: .page,
                ContentScaffoldOptions(title: "T", template: "post.html\nevil: true")
            )
        }
        assertNothingWasCreated()
    }

    /// The same line separators the title rule adds on top of `controlCharacters`.
    func testRejectsATagWithALineSeparator() {
        assertThrows(.invalidMetadata(.tags, "")) {
            try scaffold(kind: .post, ContentScaffoldOptions(title: "T", tags: ["a\u{2028}b"]))
        }
        assertNothingWasCreated()
    }

    // MARK: - "index" is reserved for posts

    /// `content/posts/index.md` publishes at `/posts/` while its RSS link is built from the
    /// slug, giving `/posts/index/` — the divergence this scaffolder exists to prevent.
    func testPost_rejectsAnExplicitIndexSlug() {
        assertThrows(.invalidSlug("")) {
            try scaffold(kind: .post, ContentScaffoldOptions(title: "Some Post", slug: "index"))
        }
        assertNothingWasCreated()
    }

    /// The same file is reachable without `--slug` at all: `hirundo new post "Index"`.
    func testPost_rejectsATitleThatSlugifiesToIndex() {
        assertThrows(.invalidSlug("")) {
            try scaffold(kind: .post, ContentScaffoldOptions(title: "Index"))
        }
        assertNothingWasCreated()
    }

    func testPost_rejectingIndexExplainsWhy() {
        do {
            _ = try scaffold(kind: .post, ContentScaffoldOptions(title: "Index"))
            XCTFail("Expected the reserved slug to be rejected")
        } catch let error as ContentScaffoldError {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("/posts/"), "Got: \(message)")
            XCTAssertTrue(message.contains("RSS"), "Got: \(message)")
        } catch {
            XCTFail("Expected a ContentScaffoldError, got \(error)")
        }
    }

    /// `ContentScaffoldOptions.path` is public and bypasses `resolveSlug` (and therefore
    /// `validatePostSlug`) entirely, so the reserved-name guard must be reapplied to the
    /// resolved path's final component too. Unreachable from the CLI today — `NewPostCommand`
    /// has no `--path` — but `path` is public API, so a direct library caller must still
    /// be refused.
    func testPost_rejectsAPathEndingInIndex() {
        assertThrows(.invalidPath("")) {
            try scaffold(kind: .post, ContentScaffoldOptions(title: "T", path: "posts/index"))
        }
        assertNothingWasCreated()
    }

    /// `SiteGenerator` derives the RSS item slug from the file's last path component
    /// regardless of how deeply the file sits, so a nested `index` breaks the same way a
    /// top-level one does.
    func testPost_rejectsANestedPathEndingInIndex() {
        assertThrows(.invalidPath("")) {
            try scaffold(kind: .post, ContentScaffoldOptions(title: "T", path: "posts/sub/index"))
        }
        assertNothingWasCreated()
    }

    /// `sanitizedPath` appends `.md` when the caller's path omits it, so the reserved-name
    /// check must see the same stem whether or not the caller already typed the extension.
    func testPost_rejectsAPathEndingInIndexWithExplicitExtension() {
        assertThrows(.invalidPath("")) {
            try scaffold(kind: .post, ContentScaffoldOptions(title: "T", path: "posts/index.md"))
        }
        assertNothingWasCreated()
    }

    /// Pages must keep working: `content/index.md` is the home page `hirundo init` writes,
    /// and pages are not in the feed, so nothing can disagree.
    func testPage_stillAcceptsIndex() throws {
        let home = try scaffold(kind: .page, ContentScaffoldOptions(title: "Index"))
        XCTAssertEqual(home.relativePath, "content/index.md")

        let section = try scaffold(kind: .page, ContentScaffoldOptions(title: "T", path: "about/index"))
        XCTAssertEqual(section.relativePath, "content/about/index.md")
    }

    // MARK: - Rollback

    /// A write that fails after directories were created must leave none of them behind.
    ///
    /// Reaching the write needs a name this scaffolder accepts but the filesystem does not:
    /// `maxFilenameLength` is raised past what APFS allows (255 characters per component),
    /// so the 300-character name clears `sanitizedPath` and then fails with ENAMETOOLONG.
    func testFailedWriteRemovesOnlyTheDirectoriesItCreated() throws {
        let contentDirectory = projectRoot.appendingPathComponent("content")
        try FileManager.default.createDirectory(at: contentDirectory, withIntermediateDirectories: true)

        assertThrows(.cannotWriteFile("")) {
            try scaffold(
                kind: .page,
                ContentScaffoldOptions(title: "T", path: "a/" + String(repeating: "b", count: 300)),
                limits: Limits(maxFilenameLength: 1000)
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: contentDirectory.appendingPathComponent("a").path),
            "The directory this call created must be rolled back"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: contentDirectory.path),
            "A pre-existing directory must survive the rollback"
        )
    }

    /// A rollback must not take a file another writer has finished in a directory this call
    /// created — the interleaving that made a recursive `removeItem` destructive: process A
    /// creates `content/notes/` on its way to `a.md`, process B writes `content/notes/b.md`,
    /// A's write fails, and A's rollback deletes the directory with B's post inside it.
    ///
    /// The injected `FileManager` plays process B at exactly the moment that matters — after
    /// the directory exists, before the write fails — so the interleaving is reproduced
    /// deterministically instead of being waited for.
    func testRollbackKeepsAFileAnotherWriterPutInADirectoryThisCallCreated() throws {
        let contentDirectory = projectRoot.appendingPathComponent("content")
        try FileManager.default.createDirectory(at: contentDirectory, withIntermediateDirectories: true)
        let fileManager = SiblingWritingFileManager()

        do {
            _ = try ContentScaffolder(fileManager: fileManager).scaffold(
                in: projectRoot,
                build: Build.defaultBuild(),
                limits: Limits(maxFilenameLength: 1000),
                kind: .page,
                options: ContentScaffoldOptions(
                    title: "T",
                    path: "a/b/" + String(repeating: "c", count: 300)
                ),
                date: Date(timeIntervalSince1970: 1_772_000_000)
            )
            XCTFail("Expected the over-long file name to fail the write")
        } catch ContentScaffoldError.cannotWriteFile {
            // The failure this test needs: reached after the directories were created.
        }

        XCTAssertEqual(fileManager.siblings.count, 1, "Precondition: one directory was created")
        let sibling = try XCTUnwrap(fileManager.siblings.first)
        XCTAssertEqual(
            try? String(contentsOf: sibling, encoding: .utf8),
            SiblingWritingFileManager.siblingContents,
            "A rollback must not delete a file it did not create"
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: sibling.deletingLastPathComponent().path),
            [sibling.lastPathComponent],
            "The failed write must still have taken its own temporary file with it"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: contentDirectory.appendingPathComponent("a").path),
            "The unwind must stop at the directory it cannot remove, not skip past it"
        )
    }

    // MARK: - Comma-separated option parsing

    func testParseList_returnsEmptyForNil() {
        XCTAssertEqual(ContentScaffoldOptions.parseList(nil), [])
    }

    func testParseList_trimsEntries() {
        XCTAssertEqual(ContentScaffoldOptions.parseList(" swift , web "), ["swift", "web"])
    }

    func testParseList_dropsBlanksAndDuplicatesKeepingOrder() {
        XCTAssertEqual(
            ContentScaffoldOptions.parseList("swift, , swift ,web"),
            ["swift", "web"]
        )
    }

    func testParseList_returnsEmptyForACommaOnlyValue() {
        XCTAssertEqual(ContentScaffoldOptions.parseList(",,,"), [])
    }

    // MARK: - Collisions

    func testRefusesToOverwriteAndLeavesTheExistingFileIntact() throws {
        let first = try scaffold(kind: .post, ContentScaffoldOptions(title: "Hello World"))
        let original = try String(contentsOf: first.url, encoding: .utf8)

        assertThrows(.fileExists("")) {
            try scaffold(
                kind: .post,
                ContentScaffoldOptions(title: "Hello World", tags: ["different"])
            )
        }

        XCTAssertEqual(
            try String(contentsOf: first.url, encoding: .utf8),
            original,
            "A collision must not touch the file that is already there"
        )
    }

    /// The no-overwrite guarantee has to hold on the filesystem, not merely on the early
    /// existence check: that check is a fast path for the friendly error, and between it and
    /// the write anything can happen.
    ///
    /// A dangling symbolic link is the one destination that reaches the write with the check
    /// satisfied, and so tests the guarantee without a race: `fileExists(atPath:)` follows
    /// the link to a target that is not there and reports the name free, while the name
    /// itself is very much taken. The exclusive create must refuse it, report the very same
    /// error the check would have, and leave the link exactly as it found it.
    func testRefusesADestinationTheExistenceCheckCannotSee() throws {
        let posts = projectRoot.appendingPathComponent("content/posts")
        try FileManager.default.createDirectory(at: posts, withIntermediateDirectories: true)
        let destination = posts.appendingPathComponent("hello-world.md")
        let danglingTarget = posts.appendingPathComponent("not-there.md")
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: danglingTarget)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destination.path),
            "Precondition: the early existence check has to consider this destination free"
        )

        assertThrows(.fileExists("")) {
            try scaffold(kind: .post, ContentScaffoldOptions(title: "Hello World"))
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual(
            attributes[.type] as? FileAttributeType,
            FileAttributeType.typeSymbolicLink,
            "The destination must be left as it was found"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: danglingTarget.path),
            "Nothing may have been written through the link"
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: posts.path).sorted(),
            ["hello-world.md"],
            "A refused write must take its temporary file with it"
        )
    }

    /// The race itself: many writers aiming at one destination at once.
    ///
    /// Exactly one may create the file, and what is on disk afterwards must be that writer's
    /// complete output — not a blend of two, not a truncation. Whether a given run really
    /// interleaves inside the window between the existence check and the write is the
    /// scheduler's business, but the assertions do not depend on it: every interleaving an
    /// exclusive create allows satisfies them, and a replacing rename satisfies them only by
    /// luck.
    func testConcurrentScaffoldsAtOneDestinationLeaveExactlyOneCompleteFile() throws {
        // Pre-created so the writers race on the file alone; a directory race is the
        // rollback tests' subject, not this one's.
        let posts = projectRoot.appendingPathComponent("content/posts")
        try FileManager.default.createDirectory(at: posts, withIntermediateDirectories: true)
        // Every writer passes identical options, so the expected bytes are known exactly
        // without knowing who won: the content depends on the title, date, and front matter,
        // and never on the slug, which names only the file.
        let reference = try scaffold(kind: .post, ContentScaffoldOptions(title: "Race", slug: "reference"))
        let expected = try String(contentsOf: reference.url, encoding: .utf8)

        let outcomes = ScaffoldOutcomes()
        let root = projectRoot!
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            do {
                let result = try ContentScaffolder().scaffold(
                    in: root,
                    build: Build.defaultBuild(),
                    limits: Limits(),
                    kind: .post,
                    options: ContentScaffoldOptions(title: "Race", slug: "raced"),
                    date: Date(timeIntervalSince1970: 1_772_000_000)
                )
                outcomes.recordSuccess(result.url)
            } catch {
                outcomes.recordFailure(error)
            }
        }

        XCTAssertEqual(
            outcomes.unexpectedFailures,
            [],
            "A writer that loses the race may fail only with fileExists"
        )
        XCTAssertEqual(
            outcomes.successes.count,
            1,
            "Exactly one concurrent writer may create the destination"
        )
        let winner = try XCTUnwrap(outcomes.successes.first)
        XCTAssertEqual(
            try String(contentsOf: winner, encoding: .utf8),
            expected,
            "The surviving file must be one writer's complete output"
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: posts.path).sorted(),
            ["raced.md", "reference.md"],
            "No writer may leave a temporary file behind"
        )
    }

    // MARK: - Integration

    func testGeneratedPostIsExcludedFromABuildWithoutDrafts() async throws {
        _ = try SiteScaffolder().scaffold(
            at: projectRoot,
            options: SiteScaffoldOptions(title: "Test Site", includeBlog: true, force: true)
        )
        let result = try scaffold(
            kind: .post,
            ContentScaffoldOptions(title: "Secret Post", draft: true)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        // A companion that is *not* a draft, so the absence below means "excluded" rather
        // than "the build produced nothing" or "the slug was something else".
        _ = try scaffold(kind: .post, ContentScaffoldOptions(title: "Public Post"))

        let generator = try SiteGenerator(projectPath: projectRoot.path)
        try await generator.build(clean: true, includeDrafts: false)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: projectRoot.appendingPathComponent("_site/posts/public-post/index.html").path
            ),
            "A non-draft post must reach the output directory"
        )
        let output = projectRoot.appendingPathComponent("_site/posts/secret-post/index.html")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: output.path),
            "A draft must not reach the output directory"
        )
    }

    func testGeneratedPostBuildsToItsSlugURL() async throws {
        _ = try SiteScaffolder().scaffold(
            at: projectRoot,
            options: SiteScaffoldOptions(title: "Test Site", includeBlog: true, force: true)
        )
        _ = try scaffold(kind: .post, ContentScaffoldOptions(title: "Second Post"))

        let generator = try SiteGenerator(projectPath: projectRoot.path)
        try await generator.build(clean: true, includeDrafts: false)

        let output = projectRoot.appendingPathComponent("_site/posts/second-post/index.html")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: output.path),
            "Expected /posts/second-post/ from content/posts/second-post.md"
        )
    }
}

/// Stands in for a second `hirundo new` process: drops a finished file into every directory
/// the scaffolder creates, so a rollback runs against a directory somebody else is already
/// using. `FileManager` is the scaffolder's own injection point, so this needs no seam.
private final class SiblingWritingFileManager: FileManager {
    static let siblingContents = "written by another writer"

    /// The files planted, in creation order.
    private(set) var siblings: [URL] = []

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        try super.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
        let sibling = url.appendingPathComponent("sibling.md")
        FileManager.default.createFile(
            atPath: sibling.path,
            contents: Data(Self.siblingContents.utf8)
        )
        siblings.append(sibling)
    }
}

/// Thread-safe tally for the concurrent collision test.
private final class ScaffoldOutcomes: @unchecked Sendable {
    private let lock = NSLock()
    private var created: [URL] = []
    private var unexpected: [String] = []

    /// URLs of the calls that reported creating the file.
    var successes: [URL] {
        lock.withLock { created }
    }

    /// Descriptions of the failures that were not a collision — losing the race is the only
    /// acceptable way for a concurrent writer to fail.
    var unexpectedFailures: [String] {
        lock.withLock { unexpected }
    }

    func recordSuccess(_ url: URL) {
        lock.withLock { created.append(url) }
    }

    func recordFailure(_ error: Error) {
        lock.withLock {
            if let error = error as? ContentScaffoldError, case .fileExists = error { return }
            unexpected.append("\(error)")
        }
    }
}

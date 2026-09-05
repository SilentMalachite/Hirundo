import XCTest
@testable import HirundoCore

/// Covers the content walk where it meets a symlinked directory.
///
/// `ContentScaffolder` writes to the literal path the user names, symlinks included, so a
/// build that stops at a symlinked directory turns `hirundo new` into a command that reports
/// success and produces a file no page is ever generated from.
final class ContentProcessorSymlinkTests: XCTestCase {

    private var tempDir: URL!

    private var contentDirectory: URL {
        return tempDir.appendingPathComponent("content")
    }

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-symlink-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: contentDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - The behaviour being worked around

    /// The premise of the fix: `FileManager`'s enumerator will not walk into a symlinked
    /// directory, so the file behind one is never offered to the build.
    ///
    /// Kept as a test rather than a comment so the workaround stops being justified the day
    /// Foundation starts descending on its own.
    func testFileManagerEnumeratorDoesNotDescendIntoDirectorySymlinks() throws {
        try makeDirectory("shared-pages", under: tempDir)
        try write(markdown(title: "Guide"), to: tempDir.appendingPathComponent("shared-pages/guide.md"))
        try write(markdown(title: "Home"), to: contentDirectory.appendingPathComponent("index.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("shared"), to: "../shared-pages")

        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: contentDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ))
        var enumerated: [String] = []
        while let url = enumerator.nextObject() as? URL {
            enumerated.append(relativeToContent(url))
        }

        XCTAssertTrue(enumerated.contains("index.md"), "the real file is enumerated: \(enumerated)")
        XCTAssertTrue(enumerated.contains("shared"), "the link itself is enumerated: \(enumerated)")
        XCTAssertFalse(
            enumerated.contains("shared/guide.md"),
            "FileManager is expected NOT to descend into a directory symlink, but did: \(enumerated)"
        )
    }

    // MARK: - Following directory symlinks

    func testWalkFindsMarkdownThroughADirectorySymlink() throws {
        try makeDirectory("shared-pages/nested", under: tempDir)
        try write(markdown(title: "Guide"), to: tempDir.appendingPathComponent("shared-pages/guide.md"))
        try write(markdown(title: "Deep"), to: tempDir.appendingPathComponent("shared-pages/nested/deep.markdown"))
        try write(markdown(title: "Home"), to: contentDirectory.appendingPathComponent("index.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("shared"), to: "../shared-pages")

        let found = Set(collectRelativePaths())

        XCTAssertEqual(found, ["index.md", "shared/guide.md", "shared/nested/deep.markdown"])
    }

    /// The file has to come back at the path it was *found* at, not the path it lives at:
    /// `SiteGenerator` derives the output URL from the path relative to the content directory,
    /// so reporting the resolved location would silently move the page.
    func testFilesFoundThroughASymlinkKeepTheirLogicalPath() throws {
        try makeDirectory("shared-pages", under: tempDir)
        try write(markdown(title: "Guide"), to: tempDir.appendingPathComponent("shared-pages/guide.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("shared"), to: "../shared-pages")

        let found = collectRelativePaths()

        XCTAssertEqual(found, ["shared/guide.md"])
        XCTAssertFalse(
            collect().contains { $0.path.contains("/shared-pages/") },
            "the resolved path must not leak into the reported URL"
        )
    }

    /// A content directory that is itself a symlink enumerates as completely empty, which is
    /// the same silent failure one level up.
    func testContentDirectoryThatIsItselfASymlinkIsWalked() throws {
        try FileManager.default.removeItem(at: contentDirectory)
        try makeDirectory("real-content/posts", under: tempDir)
        try write(markdown(title: "Home"), to: tempDir.appendingPathComponent("real-content/index.md"))
        try write(markdown(title: "Post"), to: tempDir.appendingPathComponent("real-content/posts/hello.md"))
        try makeSymbolicLink(at: contentDirectory, to: "real-content")

        let found = Set(collectRelativePaths())

        XCTAssertEqual(found, ["index.md", "posts/hello.md"])
    }

    /// A symlink to a file already worked, because reading one follows the link. It has to
    /// keep working.
    func testSymlinkToAMarkdownFileIsStillCollected() throws {
        try makeDirectory("shared-pages", under: tempDir)
        try write(markdown(title: "Guide"), to: tempDir.appendingPathComponent("shared-pages/guide.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("linked.md"), to: "../shared-pages/guide.md")

        XCTAssertEqual(collectRelativePaths(), ["linked.md"])
    }

    func testBrokenSymlinkDoesNotStopTheWalk() throws {
        try write(markdown(title: "Home"), to: contentDirectory.appendingPathComponent("index.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("gone"), to: "../nowhere")

        XCTAssertEqual(collectRelativePaths(), ["index.md"])
    }

    // MARK: - Cycles

    /// `content/loop -> .` resolves to the content directory itself, which the walk has
    /// already entered.
    func testSelfReferencingSymlinkTerminates() throws {
        try write(markdown(title: "Home"), to: contentDirectory.appendingPathComponent("index.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("loop"), to: ".")

        XCTAssertEqual(collectRelativePaths(), ["index.md"])
    }

    /// `content/up -> ..` reaches the project root, and the project root contains the content
    /// directory again.
    func testSymlinkToAnAncestorTerminates() throws {
        try write(markdown(title: "Home"), to: contentDirectory.appendingPathComponent("index.md"))
        try write(markdown(title: "Outside"), to: tempDir.appendingPathComponent("notes.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("up"), to: "..")

        // `up/notes.md` is what the link literally points at; `up/content/index.md` is not
        // reported again, because the content directory has already been walked.
        XCTAssertEqual(Set(collectRelativePaths()), ["index.md", "up/notes.md"])
    }

    /// Two links pointing back at each other's directories: neither is a self-link, and the
    /// loop only closes on the second hop.
    func testTwoLinkCycleTerminates() throws {
        try makeDirectory("dir-a", under: tempDir)
        try makeDirectory("dir-b", under: tempDir)
        try write(markdown(title: "A"), to: tempDir.appendingPathComponent("dir-a/a.md"))
        try write(markdown(title: "B"), to: tempDir.appendingPathComponent("dir-b/b.md"))
        try makeSymbolicLink(at: tempDir.appendingPathComponent("dir-a/to-b"), to: "../dir-b")
        try makeSymbolicLink(at: tempDir.appendingPathComponent("dir-b/to-a"), to: "../dir-a")
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("shared"), to: "../dir-a")

        XCTAssertEqual(
            Set(collectRelativePaths()),
            ["shared/a.md", "shared/to-b/b.md"],
            "each directory in the cycle is walked exactly once"
        )
    }

    // MARK: - Sites without symlinks

    /// The change is site-wide, so a content tree with no symlinks has to walk exactly as it
    /// did before: same files, same order.
    ///
    /// The expectation is built with the enumerator call the walk replaced, filtered the way
    /// it was filtered.
    func testDirectoryWithoutSymlinksEnumeratesExactlyAsBefore() throws {
        try makeDirectory("content/posts/2024", under: tempDir)
        try makeDirectory("content/.drafts", under: tempDir)
        try makeDirectory("content/assets", under: tempDir)
        try write(markdown(title: "Home"), to: contentDirectory.appendingPathComponent("index.md"))
        try write(markdown(title: "About"), to: contentDirectory.appendingPathComponent("about.markdown"))
        try write(markdown(title: "Post"), to: contentDirectory.appendingPathComponent("posts/hello.md"))
        try write(markdown(title: "Old"), to: contentDirectory.appendingPathComponent("posts/2024/old.md"))
        try write(markdown(title: "Hidden"), to: contentDirectory.appendingPathComponent(".drafts/secret.md"))
        try write("body { color: red }", to: contentDirectory.appendingPathComponent("assets/style.css"))
        try write("not markdown", to: contentDirectory.appendingPathComponent("posts/notes.txt"))
        try write(markdown(title: "Upper"), to: contentDirectory.appendingPathComponent("posts/CASE.MD"))

        var expected: [String] = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: contentDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ))
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "md" || url.pathExtension == "markdown" else { continue }
            expected.append(url.path)
        }

        XCTAssertEqual(collect().map(\.path), expected)
        XCTAssertFalse(expected.isEmpty)
        // Guards the expectation itself: the hidden directory, the non-Markdown files and the
        // upper-cased extension all stay out.
        XCTAssertEqual(
            Set(expected.map(relativeToContent)),
            ["index.md", "about.markdown", "posts/hello.md", "posts/2024/old.md"]
        )
    }

    // MARK: - Per-file rules the walk feeds

    /// The size rules live outside the walk and have to survive it: a file over the limit is
    /// warned about and kept, one over twice the limit is dropped.
    func testFileSizeLimitStillAppliesToFilesFoundThroughASymlink() async throws {
        try makeDirectory("shared-pages", under: tempDir)
        try write(markdown(title: "Small"), to: tempDir.appendingPathComponent("shared-pages/small.md"))
        try write(
            markdown(title: "Large", body: String(repeating: "x", count: 1_500)),
            to: tempDir.appendingPathComponent("shared-pages/large.md")
        )
        try write(
            markdown(title: "Huge", body: String(repeating: "x", count: 5_000)),
            to: tempDir.appendingPathComponent("shared-pages/huge.md")
        )
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("shared"), to: "../shared-pages")

        let config = HirundoConfig(
            site: try Site(title: "Test", url: "https://example.com"),
            limits: Limits(maxMarkdownFileSize: 1_000)
        )
        let processor = ContentProcessor(config: config, projectPath: tempDir.path)
        let contents = try await processor.processDirectory(at: contentDirectory, includeDrafts: true)

        XCTAssertEqual(
            Set(contents.map { relativeToContent($0.url) }),
            ["shared/small.md", "shared/large.md"],
            "over the limit is kept with a warning, over twice the limit is skipped"
        )
    }

    /// The whole point of the fix, end to end: a page created under a symlinked directory has
    /// to appear in the output at the URL its logical path implies.
    func testBuildWritesSymlinkedContentAtItsLogicalURL() async throws {
        try makeSite()
        try makeDirectory("shared-pages", under: tempDir)
        try write(markdown(title: "Guide"), to: tempDir.appendingPathComponent("shared-pages/guide.md"))
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("shared"), to: "../shared-pages")

        let generator = try SiteGenerator(projectPath: tempDir.path)
        try await generator.build()

        let output = tempDir.appendingPathComponent("_site")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("shared/guide/index.html").path),
            "the page belongs at the logical path, /shared/guide/: \(outputTree(output))"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("shared-pages").path),
            "the resolved path must not become the output URL: \(outputTree(output))"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("private").path),
            "the enumerator's /private prefix must not become the output URL: \(outputTree(output))"
        )
        // The page the site already had is untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("index.html").path))
    }

    /// A symlinked `posts` directory has to be classified by the path it was found at, since
    /// that is what decides whether the file becomes a post.
    func testPostsDirectoryReachedThroughASymlinkStillBuildsPosts() async throws {
        try makeSite()
        try makeDirectory("shared-posts", under: tempDir)
        try write(
            markdown(title: "Hello", extraFrontMatter: "date: 2024-01-01T00:00:00Z"),
            to: tempDir.appendingPathComponent("shared-posts/hello.md")
        )
        try makeSymbolicLink(at: contentDirectory.appendingPathComponent("posts"), to: "../shared-posts")

        let generator = try SiteGenerator(projectPath: tempDir.path)
        try await generator.build()

        let output = tempDir.appendingPathComponent("_site")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("posts/hello/index.html").path),
            "expected /posts/hello/: \(outputTree(output))"
        )
    }

    // MARK: - Helpers

    /// Runs the walk on a background thread with a deadline, so a traversal that fails to
    /// terminate fails this test instead of hanging the whole suite.
    private func collect(
        timeout: TimeInterval = 30,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [URL] {
        let processor = ContentProcessor(config: HirundoConfig.createDefault(), projectPath: tempDir.path)
        let directory = contentDirectory
        let outcome = ThreadSafeBox<Result<[URL], Error>?>(nil)
        let finished = expectation(description: "content walk finished")

        DispatchQueue.global().async {
            outcome.set(Result { try processor.collectMarkdownFiles(in: directory) })
            finished.fulfill()
        }
        wait(for: [finished], timeout: timeout)

        switch outcome.get() {
        case .success(let urls):
            return urls
        case .failure(let error):
            XCTFail("Content walk failed: \(error)", file: file, line: line)
            return []
        case nil:
            XCTFail("Content walk did not finish within \(timeout)s", file: file, line: line)
            return []
        }
    }

    private func collectRelativePaths(
        timeout: TimeInterval = 30,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [String] {
        return collect(timeout: timeout, file: file, line: line).map(relativeToContent)
    }

    /// Path of `url` relative to the content directory.
    ///
    /// Enumerated URLs arrive with the `/private` prefix macOS puts in front of a temporary
    /// directory, so both spellings are folded together before comparing.
    private func relativeToContent(_ url: URL) -> String {
        return relativeToContent(url.path)
    }

    private func relativeToContent(_ path: String) -> String {
        let normalized = path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
        let base = contentDirectory.path
        guard normalized.hasPrefix(base + "/") else { return normalized }
        return String(normalized.dropFirst(base.count + 1))
    }

    private func markdown(title: String, extraFrontMatter: String? = nil, body: String = "Body.") -> String {
        var frontMatter = "title: \"\(title)\""
        if let extraFrontMatter {
            frontMatter += "\n" + extraFrontMatter
        }
        return """
        ---
        \(frontMatter)
        ---

        # \(title)

        \(body)
        """
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

    /// Writes the minimum a `SiteGenerator` build needs: a config, two templates and a page.
    private func makeSite() throws {
        let config = """
        site:
          title: "Symlink Test Site"
          url: "https://example.com"

        build:
          contentDirectory: "content"
          outputDirectory: "_site"
          staticDirectory: "static"
          templatesDirectory: "templates"
        """
        try write(config, to: tempDir.appendingPathComponent("config.yaml"))

        let template = """
        <!DOCTYPE html>
        <html><head><title>{{ page.title }}</title></head>
        <body>{{ content }}</body></html>
        """
        try write(template, to: tempDir.appendingPathComponent("templates/default.html"))
        try write(template, to: tempDir.appendingPathComponent("templates/post.html"))
        try write(markdown(title: "Home"), to: contentDirectory.appendingPathComponent("index.md"))
    }

    /// Renders the output tree, so a failing path assertion says what was written instead.
    private func outputTree(_ url: URL) -> String {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return "<no output directory>"
        }
        let paths = enumerator.compactMap { ($0 as? URL)?.path.replacingOccurrences(of: url.path, with: "") }
        return paths.sorted().joined(separator: ", ")
    }
}

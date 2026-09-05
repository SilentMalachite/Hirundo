import Foundation

/// Input for creating one Markdown content file.
public struct ContentScaffoldOptions: Sendable {
    /// Title written into the front matter and used as the body heading.
    public var title: String
    /// File name (without extension) for the new file. Derived from `title` when nil.
    public var slug: String?
    /// Path relative to the content directory. Takes precedence over `slug` **and over the
    /// kind's own directory** when given; only `hirundo new page` passes it.
    ///
    /// That precedence matters for `.post`: a path is used exactly as written, so
    /// `path: "notes/x"` writes `content/notes/x.md` with post front matter, while
    /// `ContentProcessor` classifies content as a post by looking for `/posts/` (or
    /// `/blog/`) in the path — the build would treat that file as a page. Callers passing
    /// `path` with `.post` must include the posts directory themselves (`"posts/notes/x"`).
    public var path: String?
    public var categories: [String]
    public var tags: [String]
    public var draft: Bool
    /// Value for the `template:` key. Uses the kind's default when nil.
    public var template: String?

    /// Creates scaffold options.
    public init(
        title: String,
        slug: String? = nil,
        path: String? = nil,
        categories: [String] = [],
        tags: [String] = [],
        draft: Bool = false,
        template: String? = nil
    ) {
        self.title = title
        self.slug = slug
        self.path = path
        self.categories = categories
        self.tags = tags
        self.draft = draft
        self.template = template
    }

    /// Splits a comma-separated option value into a clean list.
    ///
    /// Trims each entry, drops empties, and removes duplicates while keeping the order the
    /// user typed, so `"swift, , swift ,web"` becomes `["swift", "web"]`.
    /// - Parameter value: Raw option value, or `nil` when the option was not passed.
    /// - Returns: The parsed list, empty when there is nothing usable.
    public static func parseList(_ value: String?) -> [String] {
        guard let value else { return [] }
        var seen = Set<String>()
        return value
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// A successfully created content file.
public struct ContentScaffoldResult: Sendable {
    /// Absolute URL of the created file.
    public let url: URL
    /// Path relative to the project root, e.g. `"content/posts/hello-world.md"`.
    public let relativePath: String

    /// Creates a result.
    public init(url: URL, relativePath: String) {
        self.url = url
        self.relativePath = relativePath
    }
}

/// Creates a single Markdown content file inside an existing Hirundo site.
///
/// Deliberately separate from `SiteScaffolder`: that type requires an empty destination
/// and rolls the whole tree back on failure, which is right for creating a site once and
/// exactly wrong for adding one file to a site that already has content.
///
/// Not marked `Sendable` because it stores `FileManager`, which is not `Sendable`.
public struct ContentScaffolder {
    private let fileManager: FileManager

    /// Creates a scaffolder.
    /// - Parameter fileManager: File manager used for filesystem operations.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Scalars rejected in a title, and in every other value written into the front matter.
    ///
    /// `controlCharacters` covers only Cc and Cf, so it misses U+2028 LINE SEPARATOR and
    /// U+2029 PARAGRAPH SEPARATOR. Those would be written verbatim into the double-quoted
    /// YAML scalar and then folded to a plain space by the parser, so the title would not
    /// round-trip. `newlines` adds exactly those line-breaking scalars.
    /// Same rule as `SiteScaffolder.forbiddenTitleScalars`.
    private static let forbiddenTitleScalars: CharacterSet =
        CharacterSet.controlCharacters.union(.newlines)

    /// Creates one content file.
    /// - Parameters:
    ///   - projectRoot: Directory holding `config.yaml` and the content directory.
    ///   - build: Build settings; only `contentDirectory` is consulted.
    ///   - limits: Length limits for the title and the file name.
    ///   - kind: Whether to create a post or a page.
    ///   - options: Title, slug/path, taxonomy, draft flag, and template.
    ///   - date: Value for the post's `date:` key. Injectable so tests are deterministic.
    /// - Returns: The created file's absolute URL and project-relative path.
    /// - Throws: `ContentScaffoldError` when the input is unusable, the destination is
    ///   taken, or the write fails.
    public func scaffold(
        in projectRoot: URL,
        build: Build,
        limits: Limits,
        kind: ContentKind,
        options: ContentScaffoldOptions,
        date: Date = Date()
    ) throws -> ContentScaffoldResult {
        let title = try validateTitle(options.title, maxLength: limits.maxTitleLength)
        try validateMetadata(options)
        let contentDirectory = projectRoot
            .appendingPathComponent(build.contentDirectory)
            .standardizedFileURL

        let relativeToContent = try resolveRelativePath(
            kind: kind,
            options: options,
            title: title,
            limits: limits
        )
        let destination = contentDirectory
            .appendingPathComponent(relativeToContent)
            .standardizedFileURL
        try validateWithinContentDirectory(destination, contentDirectory: contentDirectory)

        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ContentScaffoldError.fileExists(destination.path)
        }

        let contents = ContentTemplates.markdown(
            kind: kind,
            title: title,
            date: date,
            categories: options.categories,
            tags: options.tags,
            draft: options.draft,
            template: options.template ?? kind.defaultTemplate
        )

        try write(contents, to: destination)

        return ContentScaffoldResult(
            url: destination,
            relativePath: build.contentDirectory + "/" + relativeToContent
        )
    }

    // MARK: - Validation

    private func validateTitle(_ title: String, maxLength: Int) throws -> String {
        let trimmed: String
        do {
            trimmed = try ConfigValidation.validateNonEmptyAndLength(
                title,
                maxLength: maxLength,
                fieldName: "Title"
            )
        } catch let ConfigError.invalidValue(details) {
            throw ContentScaffoldError.invalidTitle(details)
        } catch let error as ConfigError {
            throw ContentScaffoldError.invalidTitle(error.localizedDescription)
        }

        if Self.containsForbiddenScalar(trimmed) {
            throw ContentScaffoldError.invalidTitle("Title cannot contain control characters")
        }
        return trimmed
    }

    /// Rejects the front-matter values the title rule does not cover.
    ///
    /// Categories, tags, and the template are written into double-quoted YAML scalars by
    /// `ScaffoldTemplates.yamlQuoted`, which escapes only `\` and `"`. Anything else lands
    /// in the file verbatim, so the same scalars barred from a title have to be barred
    /// here: a BEL makes the generated file fail to parse at build time — long after
    /// `hirundo new` reported success — and a line break ends the scalar outright.
    ///
    /// Checked before the destination is resolved, so a bad value never leaves a file or a
    /// directory behind.
    private func validateMetadata(_ options: ContentScaffoldOptions) throws {
        if options.categories.contains(where: Self.containsForbiddenScalar) {
            throw ContentScaffoldError.invalidMetadata(
                .categories,
                "--categories entries cannot contain control characters or line breaks"
            )
        }
        if options.tags.contains(where: Self.containsForbiddenScalar) {
            throw ContentScaffoldError.invalidMetadata(
                .tags,
                "--tags entries cannot contain control characters or line breaks"
            )
        }
        if let template = options.template, Self.containsForbiddenScalar(template) {
            throw ContentScaffoldError.invalidMetadata(
                .template,
                "--template cannot contain control characters or line breaks"
            )
        }
    }

    private static func containsForbiddenScalar(_ value: String) -> Bool {
        value.unicodeScalars.contains { forbiddenTitleScalars.contains($0) }
    }

    /// Resolves the destination path relative to the content directory, extension included.
    ///
    /// `.path` is checked for the reserved post name here too: it bypasses `resolveSlug`
    /// (and the `slug`-derived branch below) entirely, so without this a direct
    /// `ContentScaffoldOptions(path:)` caller — unreachable from the CLI today, since
    /// `NewPostCommand` has no `--path` option, but public API nonetheless — could still
    /// reproduce the divergence ``validatePostSlug(_:)`` exists to prevent.
    private func resolveRelativePath(
        kind: ContentKind,
        options: ContentScaffoldOptions,
        title: String,
        limits: Limits
    ) throws -> String {
        if let path = options.path {
            let resolved = try sanitizedPath(path, limits: limits)
            switch kind {
            case .post:
                try validatePostPathStem(finalPathComponentStem(of: resolved))
            case .page:
                break
            }
            return resolved
        }

        let slug = try resolveSlug(options.slug, title: title, limits: limits)
        switch kind {
        case .post:
            try validatePostSlug(slug)
            return "posts/\(slug).md"
        case .page:
            return "\(slug).md"
        }
    }

    /// The last path component of an already-`.md`-suffixed relative path, extension
    /// stripped — e.g. `"posts/sub/index.md"` -> `"index"`. `sanitizedPath` guarantees the
    /// `.md` suffix regardless of whether the caller's `path` already had one, so this sees
    /// the same stem either way.
    private func finalPathComponentStem(of relativePath: String) -> String {
        let lastComponent = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        return lastComponent.hasSuffix(".md") ? String(lastComponent.dropLast(3)) : lastComponent
    }

    /// Rejects the one slug a post cannot have.
    ///
    /// `SiteGenerator` publishes an `index.md` as `index.html` in its own directory, so
    /// `content/posts/index.md` would be served at `/posts/`. The RSS item link, though, is
    /// built from `Post.slug` — the file's base name when the front matter carries none —
    /// giving `/posts/index/`. That is exactly the output-URL-versus-RSS divergence this
    /// scaffolder avoids by never writing a `slug:` key, and it is reachable from an
    /// ordinary title, so it is refused up front.
    ///
    /// Pages are deliberately unaffected: `content/index.md` is the home page `hirundo
    /// init` itself writes, `content/about/index.md` legitimately publishes at `/about/`,
    /// and pages are not in the feed, so nothing can disagree.
    private func validatePostSlug(_ slug: String) throws {
        try rejectReservedPostName(slug, optionName: "--slug", makeError: ContentScaffoldError.invalidSlug)
    }

    /// Applies the same rule as ``validatePostSlug(_:)`` to a `--path`'s final component,
    /// reached only through ``ContentScaffoldOptions/path``. RSS always derives the item
    /// slug from the file's last path component (see `SiteGenerator.swift`), regardless of
    /// how deep the file sits — so `posts/sub/index.md` divides the same way a bare
    /// `posts/index.md` does, and is refused too.
    private func validatePostPathStem(_ stem: String) throws {
        try rejectReservedPostName(stem, optionName: "--path", makeError: ContentScaffoldError.invalidPath)
    }

    /// Shared rule behind ``validatePostSlug(_:)`` and ``validatePostPathStem(_:)``: a post
    /// may not resolve to the reserved base name, whichever option produced it.
    private func rejectReservedPostName(
        _ value: String,
        optionName: String,
        makeError: (String) -> ContentScaffoldError
    ) throws {
        guard value == Self.reservedPostSlug else { return }
        throw makeError(
            "\"\(Self.reservedPostSlug)\" is reserved for posts: posts/index.md publishes "
                + "at /posts/, but its RSS link would point at /posts/index/. Pass a "
                + "different \(optionName)."
        )
    }

    /// The base name a post may not use. See ``validatePostSlug(_:)``.
    private static let reservedPostSlug = "index"

    private func resolveSlug(_ explicit: String?, title: String, limits: Limits) throws -> String {
        guard let explicit else {
            // Leave room for the ".md" the caller appends.
            let derived = title.slugify(maxLength: max(1, limits.maxFilenameLength - 3))
            // `slugify` trims the truncated form back to nothing when the cut lands in a
            // run of hyphens, and its own "untitled" fallback sits after the truncation
            // branch, so it can hand back "". Containing that here — rather than in
            // `slugify`, which has other callers — keeps `posts/.md`, a hidden file, from
            // ever being the destination.
            return derived.isEmpty ? "untitled" : derived
        }

        let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ContentScaffoldError.invalidSlug("Slug cannot be empty")
        }
        // A slug names one file, not a path.
        guard !trimmed.contains("/"), !trimmed.contains("\\"), trimmed != ".", trimmed != ".." else {
            throw ContentScaffoldError.invalidSlug(
                "Slug must name a single file, not a path: \(trimmed)"
            )
        }
        guard !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ContentScaffoldError.invalidSlug("Slug cannot contain control characters")
        }
        guard trimmed.count + 3 <= limits.maxFilenameLength else {
            throw ContentScaffoldError.invalidSlug(
                "Slug exceeds the \(limits.maxFilenameLength)-character file name limit"
            )
        }
        return trimmed
    }

    /// Sanitizes a caller-supplied relative path and gives it a `.md` extension.
    ///
    /// `PathSanitizer.sanitize` returns an empty string for anything it refuses — `..`,
    /// `./`, a leading `/`, NUL bytes, a scheme — so an empty result is the rejection.
    private func sanitizedPath(_ path: String, limits: Limits) throws -> String {
        let sanitized = PathSanitizer.sanitize(path.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !sanitized.isEmpty else {
            throw ContentScaffoldError.invalidPath(
                "Path must be relative to the content directory: \(path)"
            )
        }
        let withExtension = sanitized.hasSuffix(".md") ? sanitized : sanitized + ".md"

        // The same file name limit `resolveSlug` applies, but per component: a deep chain
        // of short directory names is legitimate, while any single over-long name would
        // otherwise fail inside the write as a bare ENAMETOOLONG rather than as a clear
        // rejection of the input.
        for component in withExtension.split(separator: "/")
        where component.count > limits.maxFilenameLength {
            throw ContentScaffoldError.invalidPath(
                "Path component exceeds the \(limits.maxFilenameLength)-character "
                    + "file name limit: \(component)"
            )
        }
        return withExtension
    }

    /// Belt-and-braces check that the resolved destination really sits inside the content
    /// directory, after `standardizedFileURL` has collapsed any remaining `.` components.
    private func validateWithinContentDirectory(_ destination: URL, contentDirectory: URL) throws {
        let root = contentDirectory.path.hasSuffix("/")
            ? contentDirectory.path
            : contentDirectory.path + "/"
        guard destination.path.hasPrefix(root) else {
            throw ContentScaffoldError.invalidPath(
                "Path escapes the content directory: \(destination.path)"
            )
        }
    }

    // MARK: - Writing

    /// Writes the file, creating missing parent directories and rolling those back if the
    /// write itself fails.
    ///
    /// Deliberately not `SiteFileManager.writeFile(content:to:)`: this write is atomic and
    /// exclusive (see ``createExclusively(_:at:in:)``) and must land on the literal path the
    /// user named, whereas `SiteFileManager` resolves symlinks — right for generated output
    /// under `_site`, wrong for content the user asked to create here.
    ///
    /// A consequence, and a deliberate one: `standardizedFileURL` does not resolve
    /// symlinks, so a symlinked directory the user has already placed under `content/` will
    /// take the write outside the content directory. That is not an escalation — planting
    /// that symlink already needs write access to the content directory — and following the
    /// user's own symlink is what they asked for. Do not "fix" this by switching to
    /// `SiteFileManager`.
    private func write(_ contents: String, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let createdDirectories = missingDirectories(leadingTo: parent)
        if !createdDirectories.isEmpty {
            do {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                throw ContentScaffoldError.cannotCreateDirectory(parent.path)
            }
        }

        do {
            try createExclusively(Data(contents.utf8), at: destination, in: parent)
        } catch {
            // Give back only the directories this call created, and only while they are
            // still empty. See `removeCreatedDirectories(_:)`.
            removeCreatedDirectories(createdDirectories)
            throw error
        }
    }

    /// Creates `destination` atomically **and** exclusively, with the content in `data`.
    ///
    /// The bytes go to a uniquely named temporary file in `parent` — the same directory,
    /// hence the same filesystem — which is then given its final name with `link`. Splitting
    /// it that way is what buys both properties at once:
    ///
    /// - **Atomic**: the destination name appears only once every byte is written, so a
    ///   failure can never leave a half-written file behind.
    /// - **Exclusive**: `link` fails with `EEXIST` instead of replacing an existing name, so
    ///   the filesystem itself — not the caller's earlier `fileExists` check — is what
    ///   guarantees no overwrite.
    ///
    /// `Data.write(options: .atomic)` gives only the first: it finishes with `rename`, which
    /// silently replaces the destination. Two `hirundo new` processes racing on one path
    /// would both pass the existence check and the second one's rename would destroy the
    /// first one's finished file. `EEXIST` is reported as ``ContentScaffoldError/fileExists``
    /// so the losing process is indistinguishable from one that lost the check itself.
    ///
    /// The temporary file is unlinked on every path out of this method, taken or not, so a
    /// failure never leaves one behind in the user's content directory.
    private func createExclusively(_ data: Data, at destination: URL, in parent: URL) throws {
        let temporary = parent.appendingPathComponent(".hirundo-new-\(UUID().uuidString).tmp")
        guard
            let temporaryPath = Self.fileSystemPath(of: temporary),
            let destinationPath = Self.fileSystemPath(of: destination)
        else {
            throw ContentScaffoldError.cannotWriteFile(destination.path)
        }

        // `O_EXCL` here too: the name carries a UUID, but it is a name in a directory the
        // user can write to, so it is never assumed to be free.
        let descriptor = open(temporaryPath, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard descriptor >= 0 else {
            throw ContentScaffoldError.cannotWriteFile(destination.path)
        }
        defer { unlink(temporaryPath) }

        let wrote = Self.writeAll(data, to: descriptor)
        // Closed before the result is judged, so the descriptor leaks on no path; a failure
        // reported only at close (a full disk, say) has to count as a failed write.
        let closed = close(descriptor) == 0
        guard wrote, closed else {
            throw ContentScaffoldError.cannotWriteFile(destination.path)
        }

        guard link(temporaryPath, destinationPath) == 0 else {
            let failure = errno
            throw failure == EEXIST
                ? ContentScaffoldError.fileExists(destination.path)
                : ContentScaffoldError.cannotWriteFile(destination.path)
        }
    }

    /// Writes every byte of `data` to `descriptor`, resuming a short write and retrying an
    /// interrupted one.
    /// - Returns: `false` as soon as a write fails for any other reason.
    private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            guard let base = buffer.baseAddress else { return true }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, base + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += written
            }
            return true
        }
    }

    /// The null-terminated path bytes the kernel expects, taken from Foundation's own file
    /// system representation so a non-ASCII name is spelled here exactly the way the
    /// `FileManager` calls around this one spell it.
    /// - Returns: `nil` only when the URL has no file system representation at all.
    private static func fileSystemPath(of url: URL) -> [CChar]? {
        url.withUnsafeFileSystemRepresentation { pointer -> [CChar]? in
            guard let pointer else { return nil }
            return Array(UnsafeBufferPointer(start: pointer, count: strlen(pointer) + 1))
        }
    }

    /// The directories `createDirectory(at:withIntermediateDirectories:)` would have to
    /// create for `url` to exist: `url` itself first, then each missing ancestor above it,
    /// so the list reads deepest first.
    ///
    /// The whole chain is recorded rather than just its topmost entry, because a rollback
    /// has to unwind it one directory at a time — see ``removeCreatedDirectories(_:)``.
    /// - Returns: An empty list when `url` already exists, so a rollback leaves it alone.
    private func missingDirectories(leadingTo url: URL) -> [URL] {
        var current = url.standardizedFileURL
        var missing: [URL] = []
        while !fileManager.fileExists(atPath: current.path) {
            missing.append(current)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }
            current = parent
        }
        return missing
    }

    /// Undoes a failed write's directory creation, deepest first.
    ///
    /// `rmdir` rather than `FileManager.removeItem`, which is recursive: between this call
    /// creating `content/notes/` and its write failing, another `hirundo new` may have
    /// finished a file in there, and a recursive delete would take that file with it.
    /// `rmdir` refuses a non-empty directory with `ENOTEMPTY`, which is exactly the test for
    /// "somebody else is using this now". The unwind stops at the first directory that will
    /// not go, since every directory above it still holds that one.
    ///
    /// Failures are deliberately silent: the caller is about to throw the write error, and
    /// that is the one the user needs to hear.
    private func removeCreatedDirectories(_ directories: [URL]) {
        for directory in directories {
            guard let path = Self.fileSystemPath(of: directory), rmdir(path) == 0 else { return }
        }
    }
}

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
    /// Deliberately not `SiteFileManager.writeFile(content:to:)`: this write is atomic (a
    /// failure must not leave a truncated file behind) and must land on the literal path
    /// the user named, whereas `SiteFileManager` resolves symlinks — right for generated
    /// output under `_site`, wrong for content the user asked to create here.
    ///
    /// A consequence, and a deliberate one: `standardizedFileURL` does not resolve
    /// symlinks, so a symlinked directory the user has already placed under `content/` will
    /// take the write outside the content directory. That is not an escalation — planting
    /// that symlink already needs write access to the content directory — and following the
    /// user's own symlink is what they asked for. Do not "fix" this by switching to
    /// `SiteFileManager`.
    private func write(_ contents: String, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let createdRoot = topmostMissingAncestor(of: parent)
        if createdRoot != nil {
            do {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                throw ContentScaffoldError.cannotCreateDirectory(parent.path)
            }
        }

        do {
            try Data(contents.utf8).write(to: destination, options: .atomic)
        } catch {
            // Only remove directories this call created; never touch pre-existing ones.
            if let createdRoot {
                try? fileManager.removeItem(at: createdRoot)
            }
            throw ContentScaffoldError.cannotWriteFile(destination.path)
        }
    }

    /// Returns the highest ancestor of `url` (possibly `url` itself) that does not exist —
    /// the topmost directory `createDirectory(withIntermediateDirectories:)` would create,
    /// and therefore the only one safe to remove when rolling back.
    /// - Returns: `nil` when `url` already exists, so rollback leaves it alone.
    private func topmostMissingAncestor(of url: URL) -> URL? {
        var current = url.standardizedFileURL
        var missing: URL?
        while !fileManager.fileExists(atPath: current.path) {
            missing = current
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }
            current = parent
        }
        return missing
    }
}

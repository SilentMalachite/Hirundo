import Foundation

/// Options that control how a new Hirundo site is scaffolded.
public struct SiteScaffoldOptions: Sendable {
    /// Site title written into `config.yaml` and starter content.
    public var title: String
    /// When `true`, also create blog post templates and a `content/posts` directory.
    public var includeBlog: Bool
    /// When `true`, allow scaffolding into a non-empty destination directory.
    public var force: Bool

    /// Creates scaffold options.
    /// - Parameters:
    ///   - title: Site title. Defaults to `"My Hirundo Site"`.
    ///   - includeBlog: Whether to include blog scaffolding. Defaults to `false`.
    ///   - force: Whether to overwrite/allow a non-empty destination. Defaults to `false`.
    public init(
        title: String = "My Hirundo Site",
        includeBlog: Bool = false,
        force: Bool = false
    ) {
        self.title = title
        self.includeBlog = includeBlog
        self.force = force
    }
}

/// Result of a successful site scaffold operation.
public struct SiteScaffoldResult: Sendable {
    /// Absolute URL of the created site root.
    public let destination: URL
    /// Relative paths of files and directories created under `destination`.
    public let createdRelativePaths: [String]
    /// Relative paths of pre-existing files under `destination` that were modified in
    /// place rather than created — currently only a merged `.gitignore`.
    public let modifiedRelativePaths: [String]

    /// Creates a scaffold result.
    /// - Parameters:
    ///   - destination: Absolute URL of the created site root.
    ///   - createdRelativePaths: Relative paths created under `destination`.
    ///   - modifiedRelativePaths: Relative paths of pre-existing files modified in place.
    ///     Defaults to an empty array.
    public init(
        destination: URL,
        createdRelativePaths: [String],
        modifiedRelativePaths: [String] = []
    ) {
        self.destination = destination
        self.createdRelativePaths = createdRelativePaths
        self.modifiedRelativePaths = modifiedRelativePaths
    }
}

/// Creates the initial directory layout and starter files for a Hirundo site.
///
/// Not marked `Sendable` because it stores `FileManager`, which is not `Sendable`.
public struct SiteScaffolder {
    private let fileManager: FileManager

    /// Creates a scaffolder.
    /// - Parameter fileManager: File manager used for filesystem operations. Defaults to `.default`.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Scaffolds a new site at the given destination.
    /// - Parameters:
    ///   - destination: Directory where the site should be created.
    ///   - options: Scaffold options such as title, blog inclusion, and force.
    /// - Returns: A result listing the destination and created relative paths.
    /// - Throws: `ScaffoldError` when the destination is invalid or files cannot be written.
    public func scaffold(at destination: URL, options: SiteScaffoldOptions) throws -> SiteScaffoldResult {
        let title = try validateTitle(options.title)
        try validateDestination(destination, force: options.force)

        // Remember the topmost directory we are about to create so a failure partway
        // through can be rolled back instead of leaving a half-scaffolded site behind.
        let createdRoot = topmostMissingAncestor(of: destination)
        try createDirectory(at: destination)

        do {
            // Seeded with the destination root: it exists as of the call above, so no
            // file written directly into it needs to ask for it again.
            var ledger = ScaffoldLedger(existingDirectories: [Self.directoryKey(destination)])
            try writeSiteFiles(
                at: destination,
                title: title,
                options: options,
                ledger: &ledger
            )
            return SiteScaffoldResult(
                destination: destination,
                createdRelativePaths: ledger.createdRelativePaths,
                modifiedRelativePaths: ledger.modifiedRelativePaths
            )
        } catch {
            if let createdRoot {
                try? fileManager.removeItem(at: createdRoot)
            }
            throw error
        }
    }

    /// Bookkeeping for a single scaffold run.
    ///
    /// `knownDirectories` is what makes each needed directory cost exactly one
    /// `createDirectory` call: `writeFile` consults it instead of unconditionally
    /// re-creating the parent of every file it writes.
    private struct ScaffoldLedger {
        var createdRelativePaths: [String] = []
        var modifiedRelativePaths: [String] = []
        private var knownDirectories: Set<String>

        init(existingDirectories: Set<String>) {
            self.knownDirectories = existingDirectories
        }

        /// Claims a directory for this run, returning `true` when the caller is the first
        /// to claim it and must therefore actually create it.
        mutating func claimDirectory(_ key: String) -> Bool {
            knownDirectories.insert(key).inserted
        }
    }

    /// Normalized identity for a directory, so the same directory reached by different
    /// URL spellings (trailing slash, `.` components) is only created once.
    private static func directoryKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func writeSiteFiles(
        at destination: URL,
        title: String,
        options: SiteScaffoldOptions,
        ledger: inout ScaffoldLedger
    ) throws {
        try writeGitignore(at: destination, ledger: &ledger)

        var files: [(relativePath: String, contents: String)] = [
            ("config.yaml", ScaffoldTemplates.configYAML(title: title, includeBlog: options.includeBlog)),
            ("content/index.md", ScaffoldTemplates.indexMarkdown(title: title)),
            ("content/about.md", ScaffoldTemplates.aboutMarkdown),
            ("templates/base.html", ScaffoldTemplates.baseHTML(includeBlog: options.includeBlog)),
            ("templates/default.html", ScaffoldTemplates.defaultHTML),
            ("static/css/style.css", ScaffoldTemplates.styleCSS)
        ]

        if options.includeBlog {
            files.append(("templates/post.html", ScaffoldTemplates.postHTML))
            files.append(("content/posts/hello-world.md", ScaffoldTemplates.helloWorldPost()))
        }

        for file in files {
            try writeFile(
                file.contents,
                relativePath: file.relativePath,
                at: destination,
                ledger: &ledger
            )
        }
    }

    private static let ignoredDestinationEntries: Set<String> = [
        ".git", ".gitignore", ".DS_Store", ".svn", ".hg"
    ]

    /// Scalars rejected in a site title.
    ///
    /// `controlCharacters` only covers Unicode categories Cc and Cf, so it misses
    /// U+2028 LINE SEPARATOR (Zl) and U+2029 PARAGRAPH SEPARATOR (Zp). Those would pass
    /// validation, be written verbatim into the double-quoted YAML scalar in `config.yaml`,
    /// and then be folded to a plain space by the YAML parser — so the title would not
    /// round-trip. `newlines` adds exactly the line-breaking scalars, U+2028/U+2029 included.
    private static let forbiddenTitleScalars: CharacterSet =
        CharacterSet.controlCharacters.union(.newlines)

    private func validateTitle(_ title: String) throws -> String {
        do {
            let trimmed = try ConfigValidation.validateNonEmptyAndLength(
                title,
                maxLength: 200,
                fieldName: "Site title"
            )
            if trimmed.unicodeScalars.contains(where: { Self.forbiddenTitleScalars.contains($0) }) {
                throw ScaffoldError.invalidTitle("Site title cannot contain control characters")
            }
            return trimmed
        } catch let error as ScaffoldError {
            throw error
        } catch let ConfigError.invalidValue(details) {
            throw ScaffoldError.invalidTitle(details)
        } catch let error as ConfigError {
            throw ScaffoldError.invalidTitle(error.localizedDescription)
        }
    }

    private func validateDestination(_ destination: URL, force: Bool) throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory)
        if exists && !isDirectory.boolValue {
            throw ScaffoldError.destinationIsFile(destination.path)
        }
        guard exists, !force else { return }

        let entries: [String]
        do {
            entries = try fileManager.contentsOfDirectory(atPath: destination.path)
        } catch {
            // The directory already exists; listing it is a read, so report a read failure
            // rather than claiming we could not create it.
            throw ScaffoldError.cannotReadDirectory(destination.path)
        }

        let hasOccupiedEntry = entries.contains { !Self.ignoredDestinationEntries.contains($0) }
        if hasOccupiedEntry {
            throw ScaffoldError.destinationNotEmpty(destination.path)
        }
    }

    /// Returns the highest ancestor of `url` (possibly `url` itself) that does not exist yet —
    /// the topmost directory `createDirectory(withIntermediateDirectories:)` would create,
    /// and therefore the only one safe to remove when rolling back.
    /// - Returns: `nil` when `url` already exists, so rollback leaves the user's directory alone.
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

    /// Creates a directory, translating any failure into a `ScaffoldError`.
    ///
    /// Deliberately not `SiteFileManager.createDirectory(at:)`: that type is constructed with
    /// an already-loaded `HirundoConfig`, which does not exist yet while scaffolding is still
    /// writing the `config.yaml` that would produce it. It also resolves symlinks before
    /// creating, which is right for output under `_site` but wrong for a destination the user
    /// named explicitly, and it surfaces raw `FileManager` errors rather than the
    /// `ScaffoldError` cases `hirundo init` reports. Keep the two in sync only in intent.
    private func createDirectory(at url: URL) throws {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ScaffoldError.cannotCreateDirectory(url.path)
        }
    }

    private func fileURL(at destination: URL, relativePath: String) -> URL {
        relativePath.split(separator: "/").reduce(destination) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    private func writeGitignore(
        at destination: URL,
        ledger: inout ScaffoldLedger
    ) throws {
        let relativePath = ".gitignore"
        let url = fileURL(at: destination, relativePath: relativePath)

        // An existing .gitignore is always merged, never overwritten — `--force` allows
        // scaffolding into a non-empty directory, it must not destroy the repository's
        // own ignore rules.
        guard fileManager.fileExists(atPath: url.path) else {
            try writeFile(
                ScaffoldTemplates.gitignore,
                relativePath: relativePath,
                at: destination,
                ledger: &ledger
            )
            return
        }

        let existing: String
        do {
            existing = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // No write has been attempted yet — this is the read of the user's existing
            // .gitignore failing (unreadable, or not valid UTF-8).
            throw ScaffoldError.cannotReadFile(url.path)
        }
        let merged = Self.mergingSiteIgnore(into: existing)
        guard merged != existing else { return }
        do {
            try Data(merged.utf8).write(to: url, options: .atomic)
        } catch {
            throw ScaffoldError.cannotWriteFile(url.path)
        }
        // The user's own .gitignore was edited in place, not created — report it
        // separately so `hirundo init` can tell them their tracked file changed.
        ledger.modifiedRelativePaths.append(relativePath)
    }

    private static func mergingSiteIgnore(into existing: String) -> String {
        let lines = existing.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let hasSiteIgnore = lines.contains { ignoresOutputDirectory(String($0)) }
        if hasSiteIgnore {
            return existing
        }
        var merged = existing
        if !merged.isEmpty && !merged.hasSuffix("\n") {
            merged += "\n"
        }
        merged += "_site/\n"
        return merged
    }

    /// Whether a single `.gitignore` line already ignores the `_site` output directory.
    ///
    /// Matches on the trailing path component so all the spellings git itself suggests
    /// count — `_site`, `_site/`, `/_site/` (the anchored form `git status` proposes),
    /// `_site/*` and `/_site/*` — otherwise repeated `hirundo init` runs would keep
    /// appending a duplicate `_site/` line. Comments (`#…`) and negations (`!…`) never
    /// match: a commented-out rule ignores nothing, and a negation asserts the opposite.
    private static func ignoresOutputDirectory(_ line: String) -> Bool {
        var pattern = line.trimmingCharacters(in: .whitespaces)
        guard !pattern.hasPrefix("#"), !pattern.hasPrefix("!") else { return false }
        if pattern.hasPrefix("/") {
            pattern.removeFirst()
        }
        if pattern.hasSuffix("/*") {
            pattern.removeLast(2)
        } else if pattern.hasSuffix("/") {
            pattern.removeLast()
        }
        return pattern == "_site"
    }

    /// Writes one scaffolded file, creating its parent directory only if this run has not
    /// created it already.
    ///
    /// Deliberately does not go through `SiteFileManager.writeFile(content:to:)`: this write
    /// is atomic (a failure must not leave a truncated starter file behind) and must land on
    /// the literal path the user asked to scaffold, whereas `SiteFileManager` resolves
    /// symlinks — appropriate when it writes generated output into `_site`, but wrong here,
    /// where a symlinked destination should be written through as given.
    private func writeFile(
        _ contents: String,
        relativePath: String,
        at destination: URL,
        ledger: inout ScaffoldLedger
    ) throws {
        let url = fileURL(at: destination, relativePath: relativePath)
        let parent = url.deletingLastPathComponent()
        if ledger.claimDirectory(Self.directoryKey(parent)) {
            try createDirectory(at: parent)
        }
        do {
            try Data(contents.utf8).write(to: url, options: .atomic)
        } catch {
            throw ScaffoldError.cannotWriteFile(url.path)
        }
        ledger.createdRelativePaths.append(relativePath)
    }
}

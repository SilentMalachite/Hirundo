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

    /// Creates a scaffold result.
    /// - Parameters:
    ///   - destination: Absolute URL of the created site root.
    ///   - createdRelativePaths: Relative paths created under `destination`.
    public init(destination: URL, createdRelativePaths: [String]) {
        self.destination = destination
        self.createdRelativePaths = createdRelativePaths
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
        try createDirectory(at: destination)

        var createdRelativePaths: [String] = []
        try writeFile(
            ScaffoldTemplates.gitignore,
            relativePath: ".gitignore",
            at: destination,
            createdRelativePaths: &createdRelativePaths
        )
        try writeFile(
            ScaffoldTemplates.configYAML(title: title, includeBlog: options.includeBlog),
            relativePath: "config.yaml",
            at: destination,
            createdRelativePaths: &createdRelativePaths
        )
        try writeFile(
            ScaffoldTemplates.indexMarkdown(title: title),
            relativePath: "content/index.md",
            at: destination,
            createdRelativePaths: &createdRelativePaths
        )
        try writeFile(
            ScaffoldTemplates.aboutMarkdown,
            relativePath: "content/about.md",
            at: destination,
            createdRelativePaths: &createdRelativePaths
        )
        try writeFile(
            ScaffoldTemplates.baseHTML(includeBlog: options.includeBlog),
            relativePath: "templates/base.html",
            at: destination,
            createdRelativePaths: &createdRelativePaths
        )
        try writeFile(
            ScaffoldTemplates.defaultHTML,
            relativePath: "templates/default.html",
            at: destination,
            createdRelativePaths: &createdRelativePaths
        )
        try writeFile(
            ScaffoldTemplates.styleCSS,
            relativePath: "static/css/style.css",
            at: destination,
            createdRelativePaths: &createdRelativePaths
        )

        if options.includeBlog {
            try writeFile(
                ScaffoldTemplates.postHTML,
                relativePath: "templates/post.html",
                at: destination,
                createdRelativePaths: &createdRelativePaths
            )
            try writeFile(
                ScaffoldTemplates.helloWorldPost(),
                relativePath: "content/posts/hello-world.md",
                at: destination,
                createdRelativePaths: &createdRelativePaths
            )
        }

        return SiteScaffoldResult(destination: destination, createdRelativePaths: createdRelativePaths)
    }

    private static let ignoredDestinationEntries: Set<String> = [
        ".git", ".gitignore", ".DS_Store", ".svn", ".hg"
    ]

    private func validateTitle(_ title: String) throws -> String {
        do {
            return try ConfigValidation.validateNonEmptyAndLength(
                title,
                maxLength: 200,
                fieldName: "Site title"
            )
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
            throw ScaffoldError.cannotCreateDirectory(destination.path)
        }

        let hasOccupiedEntry = entries.contains { !Self.ignoredDestinationEntries.contains($0) }
        if hasOccupiedEntry {
            throw ScaffoldError.destinationNotEmpty(destination.path)
        }
    }

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

    private func writeFile(
        _ contents: String,
        relativePath: String,
        at destination: URL,
        createdRelativePaths: inout [String]
    ) throws {
        let url = fileURL(at: destination, relativePath: relativePath)
        try createDirectory(at: url.deletingLastPathComponent())
        do {
            try Data(contents.utf8).write(to: url, options: .atomic)
        } catch {
            throw ScaffoldError.cannotWriteFile(url.path)
        }
        createdRelativePaths.append(relativePath)
    }
}

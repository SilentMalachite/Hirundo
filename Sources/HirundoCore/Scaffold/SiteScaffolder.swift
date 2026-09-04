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
        throw ScaffoldError.cannotWriteFile(destination.path)
    }
}

import Foundation

/// Every write the generator makes into `_site`, confined to `_site`.
///
/// The confinement follows ``OutputPathGuard``: the output root is resolved, a destination's
/// parent is resolved, and the last component never is — it is the file being replaced, so a
/// symbolic link found there is taken out rather than followed. That is what makes a `_site` left
/// holding links from an older layout repair itself on the next build instead of writing through
/// them to wherever they point.
///
/// Writes that are not generated output do not belong here. `ContentScaffolder` and
/// `SiteScaffolder` deliberately use plain `FileManager` so that `hirundo new` lands on the
/// literal path the user named, following the user's own symlinks; see their comments.
public class SiteFileManager {
    private let fileManager: FileManager
    private let config: HirundoConfig
    private let projectPath: String

    public init(config: HirundoConfig, projectPath: String, fileManager: FileManager = .default) {
        self.config = config
        self.projectPath = projectPath
        self.fileManager = fileManager
    }

    // MARK: - Output root

    /// The configured output directory, as spelled and as resolved.
    ///
    /// Recomputed on every call rather than cached at init. Resolving a path that does not exist
    /// yet is a no-op, so a root resolved before `prepareOutputDirectory` created it would still
    /// say `/var/…` while every parent resolved later says `/private/var/…`, and every write would
    /// be refused as escaping. The asset pipeline resolves its destination per write for the same
    /// reason.
    private func outputRoots() -> (resolved: URL, raw: URL) {
        let raw = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.outputDirectory)
        return (raw.resolvingSymlinksInPath(), raw)
    }

    /// A destination under either spelling of the root, or `nil` when it is under neither.
    ///
    /// Both spellings are accepted because a path that resolves under the configured output
    /// directory is logically inside the output tree even when some ancestor of the project is
    /// itself a link.
    private func confinedDestination(for url: URL) -> (OutputPathGuard, OutputPathGuard.Destination)? {
        let roots = outputRoots()
        for root in [roots.resolved, roots.raw] {
            let guardian = OutputPathGuard(root: root, fileManager: fileManager)
            if let destination = guardian.destination(for: url) {
                return (guardian, destination)
            }
        }
        return nil
    }

    // MARK: - Preparing the output directory

    /// Creates the configured output directory, optionally emptying it first.
    ///
    /// `clean` empties the directory; it does not remove it. Removing it would resolve the link
    /// when the root is one — `_site -> /Volumes/build/site` is a layout the asset pipeline
    /// already supports — and delete whatever it points at, which for `_site -> $HOME` is exactly
    /// as bad as it sounds. Emptying keeps the damage inside the output directory, which is what
    /// `--clean` means.
    public func prepareOutputDirectory(clean: Bool) throws {
        let roots = outputRoots()
        let rawPath = roots.raw.path

        if let attributes = try? fileManager.attributesOfItem(atPath: rawPath) {
            let type = attributes[.type] as? FileAttributeType
            let isLink = type == .typeSymbolicLink
            let target = isLink ? roots.raw.resolvingSymlinksInPath() : roots.raw
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory)

            guard !exists || isDirectory.boolValue else {
                throw FileManagerError.outputRootIsNotADirectory(rawPath)
            }
            if clean && exists {
                if isLink {
                    warn("\(rawPath) is a symbolic link; emptying \(target.path) instead of removing the link")
                }
                try emptyDirectory(at: target)
            }
        }

        try fileManager.createDirectory(at: roots.raw, withIntermediateDirectories: true)
    }

    /// Removes everything in `directory`, hidden entries included — `.nojekyll` and friends are
    /// generated output like anything else.
    private func emptyDirectory(at directory: URL) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for entry in contents {
            try fileManager.removeItem(at: entry)
        }
    }

    // MARK: - Writing

    /// Creates a directory inside the output tree.
    ///
    /// A link found at the last component is kept when it stays inside the output tree — the
    /// asset pipeline's manifest already resolves through those — and taken out when it does not,
    /// so a stale layout repairs itself.
    public func createDirectory(at url: URL) throws {
        guard let (guardian, destination) = confinedDestination(for: url) else {
            throw FileManagerError.outputPathEscapes(url.path)
        }
        if guardian.isSymbolicLink(at: destination.url),
           !PathBoundary.contains(destination.url.resolvingSymlinksInPath(), in: guardian.root) {
            try fileManager.removeItem(at: destination.url)
        }
        guard try guardian.createDirectories(upTo: destination.url) else {
            throw FileManagerError.outputPathEscapes(url.path)
        }
    }

    /// Writes a generated file into the output tree, atomically.
    public func writeFile(content: String, to url: URL) throws {
        guard let (guardian, destination) = confinedDestination(for: url) else {
            throw FileManagerError.outputPathEscapes(url.path)
        }
        guard try guardian.createDirectories(upTo: destination.parent) else {
            throw FileManagerError.outputPathEscapes(url.path)
        }
        try guardian.removeStaleSymlink(at: destination.url)
        try Data(content.utf8).write(to: destination.url, options: .atomic)
    }

    // MARK: - Queries

    /// Whether anything exists at `path`.
    ///
    /// Deliberately not confined to the output directory: `SiteGenerator` uses it to ask whether
    /// `static/` is there at all. It reads, it never writes, so there is nothing to confine.
    public func fileExists(at path: String) -> Bool {
        return fileManager.fileExists(atPath: path)
    }

    private func warn(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("⚠️  \(message)\n".utf8))
    }
}

/// Failures the confinement raises. Anything the filesystem itself refuses is rethrown as the
/// `FileManager` error it came with, which carries a reason worth reading.
public enum FileManagerError: LocalizedError {
    case outputPathEscapes(String)
    case outputRootIsNotADirectory(String)

    public var errorDescription: String? {
        switch self {
        case .outputPathEscapes(let path):
            return "Output path escapes the output directory: \(path)"
        case .outputRootIsNotADirectory(let path):
            return "Output path exists and is not a directory: \(path)"
        }
    }
}

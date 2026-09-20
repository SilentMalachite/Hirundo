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
    /// `clean` empties the directory; it does not remove it. See ``emptyOutputDirectory(at:fileManager:)``
    /// for why.
    public func prepareOutputDirectory(clean: Bool) throws {
        let roots = outputRoots()

        if clean {
            try Self.emptyOutputDirectory(at: roots.raw, fileManager: fileManager)
        } else {
            // Nothing to empty, but a root that is a file rather than a directory is still worth
            // reporting here rather than deep inside the first write.
            _ = try Self.outputRoot(at: roots.raw, fileManager: fileManager)
        }

        try fileManager.createDirectory(at: roots.raw, withIntermediateDirectories: true)
    }

    /// Empties an output directory, leaving the directory itself in place.
    ///
    /// It does not remove the directory, and that is the whole point. `removeItem` on a root that
    /// is a symbolic link takes out the link — `_site -> /Volumes/build/site` is a layout the
    /// asset pipeline supports, and the next build would write to a fresh `_site` beside it
    /// instead of the volume the author pointed at. An older spelling was worse: it resolved the
    /// root first, so `_site -> $HOME` deleted the home directory. Emptying keeps the damage
    /// inside the output directory, which is what "clean" means.
    ///
    /// `hirundo build --clean` and `hirundo clean --force` both come through here, so the two
    /// cannot drift apart.
    ///
    /// Hidden entries are emptied too: `.nojekyll` and friends are generated output like anything
    /// else. Does nothing when there is no output directory to empty.
    public static func emptyOutputDirectory(at root: URL, fileManager: FileManager = .default) throws {
        guard let found = try outputRoot(at: root, fileManager: fileManager) else { return }
        let target = found.target

        if found.isLink {
            eprintWarning(
                "\(root.path) is a symbolic link; emptying \(target.path) instead of removing the link"
            )
        }
        let contents = try fileManager.contentsOfDirectory(
            at: target,
            includingPropertiesForKeys: nil
        )
        for entry in contents {
            try fileManager.removeItem(at: entry)
        }
    }

    /// The directory an output root names, following a link at the root itself, or `nil` when
    /// nothing is there. Throws when something is there and is not a directory.
    private static func outputRoot(
        at root: URL, fileManager: FileManager
    ) throws -> (target: URL, isLink: Bool)? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: root.path) else {
            return nil
        }
        let isLink = attributes[.type] as? FileAttributeType == .typeSymbolicLink
        let target = isLink ? root.resolvingSymlinksInPath() : root

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: target.path, isDirectory: &isDirectory) else {
            return nil
        }
        guard isDirectory.boolValue else {
            throw FileManagerError.outputRootIsNotADirectory(root.path)
        }
        return (target, isLink)
    }

    private static func eprintWarning(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("⚠️  \(message)\n".utf8))
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
        try guardian.requireDirectories(upTo: destination.url, reporting: url.path)
    }

    /// Writes a generated file into the output tree, atomically.
    public func writeFile(content: String, to url: URL) throws {
        try writeFile(data: Data(content.utf8), to: url)
    }

    /// Writes generated bytes into the output tree, atomically.
    ///
    /// The same guarantees as the `String` form, for the outputs that are not text this module
    /// built: `search-index.json` and `asset-manifest.json` come out of a `JSONEncoder` as
    /// `Data`, and both used to be written straight through `Data.write` with no containment
    /// check and no atomic flag.
    public func writeFile(data: Data, to url: URL) throws {
        guard let (guardian, destination) = confinedDestination(for: url) else {
            throw FileManagerError.outputPathEscapes(url.path)
        }
        try guardian.requireDirectories(upTo: destination.parent, reporting: url.path)
        try guardian.removeStaleSymlink(at: destination.url)
        try data.write(to: destination.url, options: .atomic)
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

import Foundation

/// Keeps every write inside a generated-output tree, and keeps it from travelling through a
/// symbolic link to get there.
///
/// The rule this type exists to hold is that **the last path component is never resolved**. It is
/// the thing being replaced, not a path being traversed. Resolving it means a `_site` left holding
/// a symlink — which is exactly what an older version of Hirundo wrote — can never be built over:
/// the build fails because the link's target is outside the output directory, and it cannot repair
/// itself, which kills `hirundo serve`. Resolving the parent instead also closes a hole the other
/// spelling had: symlink resolution is a no-op on a path that does not exist yet, so an output
/// directory replaced by a link to somewhere outside was invisible on a build that had not yet
/// written that file, and assets were written straight through it.
///
/// The root is expected to arrive already resolved — the caller owns that decision, as
/// ``PathBoundary`` explains.
internal struct OutputPathGuard {
    /// A write target: where it actually lands, the resolved directory holding it, and where that
    /// directory sits relative to the root.
    struct Destination {
        /// Resolved parent plus the unresolved last component. This is the path to write to.
        let url: URL
        /// The parent, with symlinks resolved.
        let parent: URL
        /// `parent` relative to the root; `""` directly under it.
        let relativeDirectory: String
    }

    let root: URL
    let fileManager: FileManager

    init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    /// The path `url` would actually be written to, or `nil` when that lands outside the root.
    ///
    /// Returns rather than throws, for the callers that are deciding rather than demanding —
    /// ``AssetPruner`` skips what falls outside instead of failing the build. A caller that needs
    /// the destination wants ``requireDestination(for:)``, which reports the refusal.
    func destination(for url: URL) -> Destination? {
        let lastComponent = url.lastPathComponent
        guard lastComponent != ".", lastComponent != ".." else { return nil }

        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        guard let relativeDirectory = PathBoundary.relativePath(of: parent, under: root) else {
            return nil
        }
        return Destination(
            url: parent.appendingPathComponent(lastComponent),
            parent: parent,
            relativeDirectory: relativeDirectory
        )
    }

    /// ``destination(for:)``, refusing rather than returning `nil`.
    ///
    /// The refusal is one error with one message, wherever it comes from. It used to be two: the
    /// generator raised `FileManagerError.outputPathEscapes` and the asset pipeline wrapped its
    /// own sentence in `AssetPipelineError.processingFailed`, so the same rule broken in the same
    /// way read differently depending on which caller happened to reach it first.
    func requireDestination(for url: URL) throws -> Destination {
        guard let destination = destination(for: url) else {
            throw FileManagerError.outputPathEscapes(url.path)
        }
        return destination
    }

    /// ``createDirectories(upTo:)``, refusing rather than returning `false`.
    ///
    /// - Parameter reporting: the path to name in the refusal, when the directory being created
    ///   is a step towards something else and naming it would be less use than naming the
    ///   destination it was for.
    func requireDirectories(upTo directory: URL, reporting path: String? = nil) throws {
        guard try createDirectories(upTo: directory) else {
            throw FileManagerError.outputPathEscapes(path ?? directory.path)
        }
    }

    /// Removes a file from inside the output tree, or does nothing when it is not inside one.
    ///
    /// The same rule as a write, for the same reason: the parent is resolved, so a link in the
    /// chain that leaves the output tree takes the file out of reach, and the last component is
    /// not, so what gets removed is the entry itself. `removeItem` never follows a link, so a
    /// stale link left at a generated name is taken out rather than its target.
    ///
    /// That last part is why this is not the resolve-both-sides test the pruner used to carry:
    /// resolving the last component means a link at a generated name resolves outside the tree,
    /// fails the containment test, and is skipped — so it is never cleaned up, and every rebuild
    /// leaves it there. The write path has taken such a link out since the confinement landed;
    /// this makes the delete path agree.
    ///
    /// - Returns: the removed entry's path relative to the root, or `nil` when nothing was
    ///   removed because the entry fell outside it.
    @discardableResult
    func remove(at url: URL) throws -> String? {
        guard let destination = destination(for: url) else { return nil }
        guard fileManager.fileExists(atPath: destination.url.path)
                || isSymbolicLink(at: destination.url) else { return nil }
        try fileManager.removeItem(at: destination.url)
        return relativePath(of: destination)
    }

    /// Where a destination sits relative to the root, as a `/`-separated path.
    func relativePath(of destination: Destination) -> String {
        let name = destination.url.lastPathComponent
        return destination.relativeDirectory.isEmpty
            ? name
            : destination.relativeDirectory + "/" + name
    }

    /// Removes a symbolic link sitting where a file is about to be written.
    ///
    /// A link left in the output — again, what an older version of Hirundo wrote — makes
    /// `replaceItemAt` fail with "file doesn't exist", and makes a plain write follow the link to
    /// wherever it points. The last component is the thing being replaced, so both write paths
    /// take the link out first and let a non-clean rebuild repair itself. `attributesOfItem` is
    /// `lstat`-equivalent and does not follow the link, so a broken one is caught too.
    func removeStaleSymlink(at url: URL) throws {
        guard isSymbolicLink(at: url) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Creates `directory` and any missing parents, one component at a time, refusing to create
    /// anything once the chain leaves the root.
    ///
    /// Creating the whole chain in one `withIntermediateDirectories: true` call would trust a
    /// single resolution of a path that does not fully exist yet, and resolution is a no-op on
    /// the part that does not. Walking it lets each existing link be re-checked against the root
    /// as it is reached. Output trees are two or three levels deep, so the extra calls do not
    /// register.
    ///
    /// - Returns: `false` when the chain escapes the root, in which case nothing was created.
    @discardableResult
    func createDirectories(upTo directory: URL) throws -> Bool {
        guard let relative = PathBoundary.relativePath(of: directory, under: root) else {
            return false
        }
        var current = root
        try createIfMissing(current)
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component))
            // An existing link here is fine as long as it stays inside the output tree. One that
            // leaves it is refused rather than repaired: an intermediate directory is a path
            // being traversed, not the thing being replaced, and the asset pipeline refuses the
            // same shape. Only the last component self-heals, and its caller handles that.
            //
            // A link whose target does not exist is refused as well, and it has to be checked
            // separately: `resolvingSymlinksInPath()` cannot resolve a dangling link, so it
            // hands back the path unchanged — which is inside the root by construction, and
            // sails through the containment test no matter where the link actually points.
            // Creating the directory then fails deep in Foundation with `Input/output error`,
            // naming neither the link nor the reason.
            if isSymbolicLink(at: current) {
                let target = current.resolvingSymlinksInPath()
                guard fileManager.fileExists(atPath: target.path),
                      PathBoundary.contains(target, in: root) else {
                    return false
                }
            }
            try createIfMissing(current)
        }
        return true
    }

    /// True when something exists at `url` and is itself a symbolic link, broken or not.
    func isSymbolicLink(at url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return false
        }
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
    }

    private func createIfMissing(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

/// What breaking the confinement raises, for every caller that enforces it.
///
/// Anything the filesystem itself refuses is rethrown as the `FileManager` error it came with,
/// which carries a reason worth reading. These two are the rule's own refusals, and they live
/// beside the rule rather than beside one of the types that applies it.
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

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
    /// Returns rather than throws: the callers report containment failures with their own error
    /// types, and folding those into one would change messages the tests pin down.
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
            if isSymbolicLink(at: current),
               !PathBoundary.contains(current.resolvingSymlinksInPath(), in: root) {
                return false
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

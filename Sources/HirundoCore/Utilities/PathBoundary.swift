import Foundation

/// Where one absolute path sits relative to another, decided on path components alone.
///
/// The boundary is always a whole path component, never a bare string prefix. `content-extra`,
/// `content-posts`, `contents` and `content2` are ordinary sibling names that all start with
/// `content` without being anywhere inside it, and `/a/stat` is not inside `/a/static`. A prefix
/// match would publish those siblings' pages at a URL made of whatever characters were left over,
/// and would report an overlap between directories that do not overlap.
///
/// **Symbolic links are never resolved here, and the resolution policy is the caller's.** The
/// call sites disagree on purpose — the pruner resolves both sides so `/var` and `/private/var`
/// fold together, the asset pipeline resolves a destination's parent but not its last component,
/// `WatchPathValidation` resolves nothing because it is validating the configuration rather than
/// the filesystem — and every one of those choices is load-bearing with a comment to say why.
/// Folding them into one policy here would quietly break whichever call site lost. So: `/var/x`
/// is *not* inside `/private/var` as far as this type is concerned. Resolve first, then ask.
///
/// Both arguments must be absolute paths.
internal enum PathBoundary {
    /// `""` when `path` is `root` itself, the relative path when it is inside `root`, `nil` when
    /// it is outside.
    static func relativePath(of path: String, under root: String) -> String? {
        let root = normalizedRoot(root)
        guard path != root else { return "" }
        let prefix = root == "/" ? "/" : root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    /// ``relativePath(of:under:)`` with the root itself folded into `nil`, for callers that must
    /// not count the root as being inside itself.
    static func descendantRelativePath(of path: String, under root: String) -> String? {
        guard let relative = relativePath(of: path, under: root), !relative.isEmpty else {
            return nil
        }
        return relative
    }

    /// True when `path` is `root` itself or a descendant of it.
    static func contains(_ path: String, in root: String) -> Bool {
        relativePath(of: path, under: root) != nil
    }

    /// Trailing separators carry no meaning in a directory path, so `/a/` and `/a` name the same
    /// root. The filesystem root is the one path that is nothing but a separator.
    private static func normalizedRoot(_ root: String) -> String {
        guard root.hasSuffix("/"), root != "/" else { return root }
        var root = root
        while root.hasSuffix("/"), root != "/" { root.removeLast() }
        return root
    }
}

extension PathBoundary {
    static func relativePath(of url: URL, under root: URL) -> String? {
        relativePath(of: url.path, under: root.path)
    }

    static func descendantRelativePath(of url: URL, under root: URL) -> String? {
        descendantRelativePath(of: url.path, under: root.path)
    }

    static func contains(_ url: URL, in root: URL) -> Bool {
        contains(url.path, in: root.path)
    }
}

import Foundation

public enum WatchPathError: Error, LocalizedError, Equatable {
    /// The build's output directory and one or more watched directories occupy the same tree.
    case outputOverlapsWatchPaths(watchPaths: [String], outputPath: String)

    public var errorDescription: String? {
        switch self {
        case .outputOverlapsWatchPaths(let watchPaths, let outputPath):
            let listed = watchPaths.map { "'\($0)'" }.joined(separator: ", ")
            return "Build output directory '\(outputPath)' overlaps the watched " +
                "director\(watchPaths.count == 1 ? "y" : "ies") \(listed). " +
                "Every rebuild writes into that tree, the write is reported as a file change, " +
                "and the change starts another rebuild — the server would rebuild forever. " +
                "Point build.outputDirectory in config.yaml at a directory outside the content, " +
                "templates and static directories (for example '_site')."
        }
    }
}

/// Watched directories that a rebuild's own output would re-trigger.
///
/// Live reload only terminates while the build writes somewhere nobody is watching. `Build`'s
/// validation only compares the four directory *names*, so `outputDirectory: "static/out"` is
/// accepted — it is relative, contains no `..`, and is not equal to `content`, `static` or
/// `templates`. `HotReloadManager` cannot save us either: it matches `ignorePatterns` against a
/// path's last component only, so the pattern `static/out` never matches anything and the
/// rebuild's own `static/out/index.html` looks exactly like an edit.
///
/// The overlap is checked in both directions. Output nested under a watched directory is the
/// common typo; a watched directory nested under the output (`outputDirectory: "."`, or a
/// content directory placed inside `_site`) produces the same loop from the other side.
///
/// Comparison is on standardized absolute paths, and a shared string prefix is not containment:
/// `/a/stat` is not inside `/a/static`, so the check appends the separator before testing.
public func watchPathsOverlappingOutput(watchPaths: [String], outputPath: String) -> [String] {
    let output = standardizedPath(outputPath)
    return watchPaths.filter { watchPath in
        let watch = standardizedPath(watchPath)
        return isSameOrInside(output, of: watch) || isSameOrInside(watch, of: output)
    }
}

/// Refuses a `serve` configuration whose rebuilds would feed their own file watcher.
///
/// Called before the watcher is started so the user gets a message naming the two directories
/// rather than a server that pins a core and never settles.
public func validateWatchPaths(_ watchPaths: [String], outputPath: String) throws {
    let overlapping = watchPathsOverlappingOutput(watchPaths: watchPaths, outputPath: outputPath)
    guard overlapping.isEmpty else {
        throw WatchPathError.outputOverlapsWatchPaths(
            watchPaths: overlapping,
            outputPath: outputPath
        )
    }
}

/// Absolute path with `.`/`..` removed and any trailing separator dropped.
///
/// `URL.standardized` and not `URL.standardizedFileURL`: the latter consults the filesystem and
/// drops a leading `/private` only when the resulting path exists, which silently defeats the
/// whole check. At startup the watched directories exist and the output directory usually does
/// not, so under `/private/tmp` (or any other aliased root) the watched path standardized to
/// `/tmp/…/static` while the output stayed `/private/tmp/…/static/out` — no shared prefix, no
/// overlap reported, and the rebuild loop shipped anyway. Comparing lexically makes the answer
/// depend only on the configuration, which is what is actually being validated.
///
/// Symlinks are left alone for the same reason: the watcher and the build both address files by
/// the paths the configuration names, so resolving links here would compare something neither
/// of them uses.
private func standardizedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardized.path
}

/// True when `path` is `other` itself or a descendant of it. Both arguments must already be
/// standardized. The separator is appended to `other` so that `/a/stat` does not count as being
/// inside `/a/static`; the root directory already ends in one.
private func isSameOrInside(_ path: String, of other: String) -> Bool {
    if path == other { return true }
    let prefix = other.hasSuffix("/") ? other : other + "/"
    return path.hasPrefix(prefix)
}

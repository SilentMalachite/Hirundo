import Foundation

/// Where `hirundo init` should scaffold, and how the user gets there afterwards.
public struct InitDestination: Equatable, Sendable {
    /// Absolute, standardized directory to scaffold into.
    public let url: URL

    /// `true` when the destination and the current directory are the same directory,
    /// even if the user spelled it differently (`.`, an absolute path, or a symlink).
    public let isCurrentDirectory: Bool

    /// Ready-to-paste shell command that moves into the new site, or `nil` when the user
    /// is already there. The path argument is quoted, so spaces and apostrophes are safe.
    public let changeDirectoryCommand: String?

    public init(url: URL, isCurrentDirectory: Bool, changeDirectoryCommand: String?) {
        self.url = url
        self.isCurrentDirectory = isCurrentDirectory
        self.changeDirectoryCommand = changeDirectoryCommand
    }
}

/// Turns the raw path argument of `hirundo init` into a destination plus the follow-up
/// step the CLI should print.
public enum InitDestinationResolver {
    /// Resolves the destination for a `hirundo init` invocation.
    ///
    /// The "are we already in that directory?" check compares both sides after
    /// `resolvingSymlinksInPath()`. Comparing a standardized path against a raw one is
    /// wrong on macOS, where `/tmp`, `$TMPDIR` and `$(pwd)` may name the same directory
    /// through different symlinked spellings; without resolving both sides the CLI prints
    /// a redundant (and sometimes unusable) `cd` step.
    ///
    /// - Parameters:
    ///   - path: The raw path argument as typed by the user.
    ///   - currentDirectory: The directory the command was invoked from.
    /// - Returns: The absolute destination and the `cd` step, if one is needed.
    /// - Throws: `ScaffoldError.emptyDestinationPath` when `path` is empty, so that an
    ///   empty argument is reported rather than silently treated as the current directory.
    public static func resolve(path: String, currentDirectory: URL) throws -> InitDestination {
        guard !path.isEmpty else {
            throw ScaffoldError.emptyDestinationPath
        }

        let base = URL(fileURLWithPath: currentDirectory.path, isDirectory: true)
        let destination = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
        let isCurrent = destination.resolvingSymlinksInPath().path
            == base.resolvingSymlinksInPath().path

        return InitDestination(
            url: destination,
            isCurrentDirectory: isCurrent,
            changeDirectoryCommand: isCurrent ? nil : "cd \(path.posixShellQuoted)"
        )
    }
}

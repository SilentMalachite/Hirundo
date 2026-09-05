import Foundation

/// Why `NewContentContext.resolve` fell back to defaults instead of the values in
/// `config.yaml`.
///
/// Only `.unreadable` is worth telling the user about: a missing config is normal and
/// expected — most commands (like `hirundo clean`) treat it the same way — so it stays
/// silent.
public enum NewContentContextFallback: Sendable, Equatable {
    /// No `config.yaml` file exists at the project root.
    case missing
    /// `config.yaml` exists but could not be read or parsed.
    case unreadable
}

/// Build and limits settings `hirundo new` needs, resolved from `config.yaml`, with the
/// fallback used when there is no config file to read.
///
/// Only `build.contentDirectory` and the two length limits matter here, so this resolves
/// to `Build`/`Limits` rather than a whole `HirundoConfig` — synthesising a `HirundoConfig`
/// would mean inventing a `site.title` and `site.url` that nothing reads.
///
/// Mirrors `InitDestinationResolver`: per-invocation context resolution for a command
/// lives in `HirundoCore`, testable in isolation, rather than in the CLI target (which
/// `HirundoTests` cannot reach). `HirundoCore` does not print; `fallback` tells the caller
/// why defaults were used so the CLI can decide what, if anything, to say about it.
public struct NewContentContext: Sendable {
    public let build: Build
    public let limits: Limits
    public let fallback: NewContentContextFallback?

    public init(build: Build, limits: Limits, fallback: NewContentContextFallback?) {
        self.build = build
        self.limits = limits
        self.fallback = fallback
    }

    /// Reads `config.yaml` from `projectRoot`, falling back to defaults when it is absent
    /// or unreadable. Matches how `hirundo clean` resolves its output directory: a missing
    /// config is not a reason to refuse to create a file.
    /// - Parameter projectRoot: Directory expected to hold `config.yaml`.
    public static func resolve(projectRoot: URL) -> NewContentContext {
        let configURL = projectRoot.appendingPathComponent("config.yaml")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return NewContentContext(build: Build.defaultBuild(), limits: Limits(), fallback: .missing)
        }
        guard let config = try? HirundoConfig.load(from: configURL) else {
            return NewContentContext(build: Build.defaultBuild(), limits: Limits(), fallback: .unreadable)
        }
        return NewContentContext(build: config.build, limits: config.limits, fallback: nil)
    }
}

import Foundation

/// What the user typed on the command line for `hirundo serve`. `nil` means "not specified",
/// which is distinct from a flag's own default — the caller needs to be able to tell "the user
/// didn't say anything about the port" from "the user asked for the port config.yaml already
/// has", and only an optional preserves that distinction through to ``resolveServeOptions``.
public struct ServeCommandLineOptions: Equatable, Sendable {
    public let port: Int?
    public let noReload: Bool

    public init(port: Int?, noReload: Bool) {
        self.port = port
        self.noReload = noReload
    }
}

/// The effective settings the development server runs with, after combining the command line
/// with `config.yaml`.
public struct ServeOptions: Equatable, Sendable {
    public let port: Int
    public let liveReload: Bool
}

/// Resolves `hirundo serve`'s options: CLI overrides config, config overrides the built-in
/// default.
///
/// `Server`'s decoder already fills in the "port 8080, live reload on" default when
/// `config.yaml` omits `server:` entirely, so this function only has to decide between what the
/// user typed and what the config (already defaulted) says. `--no-reload` is a flag, not an
/// optional bool, so there is no way for it to mean "unspecified" — its absence has to be
/// treated as "defer to config", which is why it flows through `noReload: Bool` rather than
/// `Bool?`.
public func resolveServeOptions(cli: ServeCommandLineOptions, config: Server) -> ServeOptions {
    let port = cli.port ?? config.port
    let liveReload = cli.noReload ? false : config.liveReload
    return ServeOptions(port: port, liveReload: liveReload)
}

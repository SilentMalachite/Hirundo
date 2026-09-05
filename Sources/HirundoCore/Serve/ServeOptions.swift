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

    /// Lowest port `hirundo serve` accepts. Port 0 is deliberately excluded: see
    /// ``resolveServeOptions(cli:config:)``.
    public static let minimumPort = 1
    /// Highest port a TCP socket can carry — `UInt16.max`.
    public static let maximumPort = 65535
}

public enum ServeOptionsError: Error, LocalizedError, Equatable {
    case portOutOfRange(Int)

    public var errorDescription: String? {
        switch self {
        case .portOutOfRange(let port):
            var message = "Server port must be between \(ServeOptions.minimumPort) and " +
                "\(ServeOptions.maximumPort), but got \(port). " +
                "Set it with --port, or with server.port in config.yaml."
            if port == 0 {
                message += " Port 0 asks the kernel for any free port, and hirundo serve has no " +
                    "way to report which one it got — the URL it prints and opens would be wrong."
            }
            return message
        }
    }
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
///
/// The port is range-checked here because this is the one point both sources converge on, and
/// because the alternative is a trap rather than an error: the port ultimately reaches
/// `UInt16(port)` in `DevelopmentServer.start()`, and that conversion kills the process with
/// `Fatal error: Not enough bits to represent the passed value` for anything outside 0...65535.
/// A `server: { port: 99999 }` typo has to produce a diagnostic, not a crash.
///
/// Port 0 is rejected even though the socket layer accepts it as "bind any free port". The
/// kernel would pick a port, but nothing reads it back: `serve` prints, and opens a browser at,
/// the port it was asked for, so the user would be sent to `http://127.0.0.1:0`. Silently
/// serving on an address the tool cannot name is worse than refusing.
public func resolveServeOptions(cli: ServeCommandLineOptions, config: Server) throws -> ServeOptions {
    let port = cli.port ?? config.port
    guard (ServeOptions.minimumPort...ServeOptions.maximumPort).contains(port) else {
        throw ServeOptionsError.portOutOfRange(port)
    }
    let liveReload = cli.noReload ? false : config.liveReload
    return ServeOptions(port: port, liveReload: liveReload)
}

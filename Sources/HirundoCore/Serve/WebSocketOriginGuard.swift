import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Decides whether a live-reload WebSocket handshake came from the page this server served.
///
/// A WebSocket handshake is exempt from the same-origin policy: any page open in the developer's
/// browser may connect to `ws://127.0.0.1:8080/livereload` and nothing in the browser stops it.
/// What the browser does guarantee is the pair of headers checked here — a page cannot forge
/// either — so they are enough to tell our own page apart from someone else's without a token,
/// and therefore without a way to hand that token out.
///
/// Two different attacks need two different headers, which is why neither check alone would do:
///
/// - `Origin` identifies the page that opened the socket. It is what rejects a cross-site
///   connection from a page the developer merely happened to have open.
/// - `Host` identifies how that page reached us. It is what rejects DNS rebinding, where the
///   attacker's own name is re-pointed at the loopback address so that `Origin` and `Host` agree
///   and an origin check alone waves the connection through. A browser aimed at a development
///   server addresses it by literal address, so a name in `Host` means a resolver we do not
///   trust chose where the connection went.
///
/// The guard deliberately takes no configuration and knows nothing about the address the server
/// bound: the two rules hold identically for a loopback bind and for `--host 0.0.0.0`, and a
/// setting to relax them would be a setting to reintroduce the attacks.
///
/// What it is not: both rules rest on the browser being the one filling the headers in. Anything
/// that is not a browser writes whatever it likes, so under `--host 0.0.0.0` this stops nothing
/// coming from the network itself. It is a same-origin check, not authentication — it says which
/// page is calling, never who.
public struct WebSocketOriginGuard: Sendable {
    public init() {}

    /// Why a handshake was refused. Each case carries the header text it rejected so the reason
    /// can name it — see ``Rejection/reason``, which is what sanitizes that text for display.
    public enum Rejection: Equatable, Sendable {
        /// No usable `Host` header. HTTP/1.1 requires one, so this is a malformed request.
        case missingHost
        /// `Host` named something other than an IP literal or `localhost`.
        case hostNotAddressLiteral(String)
        /// No `Origin` header, which means the handshake did not come from a browser.
        case missingOrigin
        /// `Origin` was opaque (`null`) or not an http(s) URL, so it names no authority.
        case originNotWebScheme(String)
        /// `Origin` named a different authority than `Host`.
        case originMismatch(origin: String, host: String)

        /// A single line explaining the refusal, safe to write to a terminal.
        ///
        /// The header values quoted here are attacker-controlled, so they get the same treatment
        /// `EditorLauncher` gives the environment values it echoes back: control characters
        /// stripped so a value cannot forge a second line of output, and a cap on length so it
        /// cannot flood the log.
        public var reason: String {
            switch self {
            case .missingHost:
                return "the request has no Host header"
            case .hostNotAddressLiteral(let host):
                return "Host '\(Self.displayable(host))' is a name, not an address — a browser " +
                    "reaches a development server by address, so this connection was routed by " +
                    "a resolver. Open the site by IP address (or localhost) instead."
            case .missingOrigin:
                return "the handshake has no Origin header, so it did not come from a browser"
            case .originNotWebScheme(let origin):
                return "Origin '\(Self.displayable(origin))' is not an http(s) address"
            case .originMismatch(let origin, let host):
                return "Origin '\(Self.displayable(origin))' does not match Host " +
                    "'\(Self.displayable(host))'"
            }
        }

        private static func displayable(_ value: String) -> String {
            // `.newlines` as well as `.controlCharacters`: U+2028 and U+2029 break a line
            // without being control characters, so the control set alone would let a value
            // forge a second line after all.
            let forbidden = CharacterSet.controlCharacters.union(.newlines)
            let cleaned = value.unicodeScalars.filter { !forbidden.contains($0) }
            // Counted in scalars rather than characters, because a run of combining marks is a
            // single character no matter how long it is — `prefix` on characters would let one
            // through whole.
            guard cleaned.count > 80 else {
                return String(String.UnicodeScalarView(cleaned))
            }
            return String(String.UnicodeScalarView(cleaned.prefix(80))) + "…"
        }
    }

    public enum Decision: Equatable, Sendable {
        case allow
        case deny(Rejection)
    }

    /// Evaluates one handshake from its `Origin` and `Host` headers.
    ///
    /// `Host` is checked first: until we know the connection was addressed the way a browser
    /// addresses us, a matching `Origin` proves nothing, because rebinding produces exactly that
    /// match. Both parameters are optional because a header may simply be absent.
    public func evaluate(origin: String?, host: String?) -> Decision {
        let hostHeader = (host ?? "").trimmingCharacters(in: .whitespaces)
        guard !hostHeader.isEmpty else {
            return .deny(.missingHost)
        }

        // A `Host` we cannot parse is reported as a name rather than as malformed input: the
        // distinction makes no difference to the caller, and "not an address" is the accurate
        // description of every value that reaches this branch.
        guard let hostAuthority = Authority(authority: hostHeader) else {
            return .deny(.hostNotAddressLiteral(hostHeader))
        }
        guard !hostAuthority.host.isEmpty else {
            return .deny(.missingHost)
        }
        guard Self.isAddressLiteralOrLocalhost(hostAuthority.host) else {
            return .deny(.hostNotAddressLiteral(hostAuthority.host))
        }

        let originHeader = (origin ?? "").trimmingCharacters(in: .whitespaces)
        guard !originHeader.isEmpty else {
            return .deny(.missingOrigin)
        }
        guard let originAuthority = Authority(originURL: originHeader) else {
            return .deny(.originNotWebScheme(originHeader))
        }

        // Only the authority is compared, never the scheme — an origin identifies a site by
        // scheme, host and port, and the first of those is the one this server cannot observe
        // about itself. Note that this does not add up to supporting a proxy in front of the
        // server: an origin of `https://…` with no port means port 443, which no `Host` a
        // plain-HTTP server sees will match. Reach the server directly.
        guard originAuthority.normalized == hostAuthority.normalized else {
            return .deny(.originMismatch(
                origin: originAuthority.normalized,
                host: hostAuthority.normalized
            ))
        }

        return .allow
    }

    /// True for an IPv4 or IPv6 literal, and for `localhost`.
    ///
    /// `localhost` is the one name allowed because it is the one name a browser does not have to
    /// ask a resolver about: RFC 6761 reserves it for the loopback address, and browsers
    /// implement that. It is an exception on the browser's authority, not on ours — an attacker
    /// who can already answer for `localhost` on this machine has more direct things to do than
    /// rebind a development server.
    private static func isAddressLiteralOrLocalhost(_ host: String) -> Bool {
        if host.lowercased() == "localhost" {
            return true
        }
        var ipv4 = in_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            return true
        }
        var ipv6 = in6_addr()
        return inet_pton(AF_INET6, host, &ipv6) == 1
    }
}

/// The `host:port` pair from either header, reduced to one comparable form.
///
/// `URLComponents` does the parsing so that bracketed IPv6 literals, percent-encoding and the
/// port are handled the way the rest of this repo already handles URLs, rather than by a second
/// hand-rolled splitter that would disagree with it at the edges.
private struct Authority {
    let host: String
    let port: Int

    /// Parses a bare `host:port` authority, as the `Host` header carries it.
    ///
    /// A scheme is prepended because `URLComponents` only finds a host in something shaped like a
    /// URL. `http` also supplies the right default port: the request being parsed arrived over
    /// HTTP, so an absent port means 80.
    init?(authority: String) {
        self.init(url: "http://" + authority, allowedSchemes: ["http"])
    }

    /// Parses an `Origin` header, which is a full URL with no path.
    init?(originURL: String) {
        self.init(url: originURL, allowedSchemes: ["http", "https"])
    }

    private init?(url: String, allowedSchemes: Set<String>) {
        // Checked against the text as it arrived, before `URLComponents` sees it, because what
        // it hands back has already been decoded and folded: `%31%32%37…` comes back as
        // `127.0.0.1`, a fullwidth `Ｌｏ` as `lo`, and an ideographic full stop as `.`. Each of
        // those is a different string claiming to be an address literal, and none of them can be
        // told apart from the real thing after the fact. A browser writes neither header that
        // way, so refusing the spelling costs nothing.
        guard url.unicodeScalars.allSatisfy({ Self.urlScalars.contains($0) }) else {
            return nil
        }
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              allowedSchemes.contains(scheme) else {
            return nil
        }
        // An authority is only a host and a port. Anything else in the value — a path, a
        // userinfo section, a query — means it was not the header it claimed to be, and a
        // permissive parse is how a check like this gets bypassed.
        guard components.path.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }
        // Foundation leaves an IPv6 literal bracketed in `host`, but `inet_pton` and a
        // case-folded comparison both want the bare address, so the brackets come off here and
        // go back on in ``normalized``.
        let host = Self.unbracketed(components.host ?? "")

        // `URLComponents` reports a host it has already decoded and folded, and neither
        // transformation is safe to build an address check on. `%00` comes back as a NUL, and
        // Swift hands a String to `inet_pton` as a C string, so `127.0.0.1%00.evil.example`
        // would be measured only as far as the NUL and pass as a literal. Fullwidth digits and
        // an ideographic full stop fold to ASCII the same way. Requiring the host to already be
        // spelled in the characters an address or a name is made of rejects all of it at once,
        // and costs nothing real: a browser percent-encodes neither header.
        guard host.unicodeScalars.allSatisfy({ Self.hostScalars.contains($0) }) else {
            return nil
        }

        // A port outside the range a socket can carry cannot be the port this request arrived
        // on, whatever `URLComponents` was willing to parse.
        let port = components.port ?? (scheme == "https" ? 443 : 80)
        guard (0...65535).contains(port) else {
            return nil
        }

        self.host = host
        self.port = port
    }

    private static let alphanumerics =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    /// The characters an IPv4 or IPv6 literal, or a host name, is written with — nothing else.
    private static let hostScalars = CharacterSet(charactersIn: alphanumerics + ".-_:")

    /// What a scheme, an authority and their separators are written with. Notably absent: `%`,
    /// so a percent-encoded byte never reaches the parser; `@`, `?` and `#`, so nothing can be
    /// parked behind a userinfo, query or fragment; and everything outside ASCII.
    private static let urlScalars = CharacterSet(charactersIn: alphanumerics + ".-_:/[]")

    private static func unbracketed(_ host: String) -> String {
        guard host.hasPrefix("["), host.hasSuffix("]"), host.count > 2 else { return host }
        return String(host.dropFirst().dropLast())
    }

    /// Case-folded `host:port`, with IPv6 literals re-bracketed so the colon that separates the
    /// port stays unambiguous.
    var normalized: String {
        let name = host.lowercased()
        return name.contains(":") ? "[\(name)]:\(port)" : "\(name):\(port)"
    }
}

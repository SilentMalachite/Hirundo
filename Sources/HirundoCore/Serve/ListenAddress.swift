import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A numeric address the development server can actually bind to.
///
/// Swifter creates either an `AF_INET` or an `AF_INET6` socket, never both, so the caller has
/// to decide the address family up front rather than letting the OS pick. `--host localhost`
/// is the case that motivates this type: depending on `/etc/hosts` and the resolver, a browser
/// may resolve `localhost` to `::1` while the server bound `127.0.0.1` (or the reverse), and the
/// connection then simply fails with no useful error. Resolving to a concrete numeric address
/// before binding, and using that same address (via ``displayHost``) in the URL we print and
/// open in the browser, removes the ambiguity entirely.
public struct ListenAddress: Equatable, Sendable {
    /// Numeric address handed to Swifter's `listenAddressIPv4` / `listenAddressIPv6`.
    public let address: String
    /// Whether the socket must be created as AF_INET rather than AF_INET6.
    public let forceIPv4: Bool
    /// True when the address is the any-address, i.e. reachable from other machines.
    public let isWildcard: Bool

    /// Host as it should appear in a URL — IPv6 literals are bracketed.
    public var displayHost: String {
        if !forceIPv4 && address.contains(":") {
            return "[\(address)]"
        }
        return address
    }
}

public enum ListenAddressError: Error, LocalizedError, Equatable {
    case notNumeric(String)

    public var errorDescription: String? {
        switch self {
        case .notNumeric(let host):
            return "Server host must be a numeric IP address, not a host name: '\(host)'. " +
                "Use 127.0.0.1 for local access or 0.0.0.0 to accept connections from other machines."
        }
    }
}

/// Resolves a `--host` value into a concrete address the server can bind.
///
/// `localhost` is special-cased to the IPv4 loopback address rather than being resolved through
/// DNS/`/etc/hosts`: see the type-level documentation above for why binding to whichever address
/// the resolver happens to prefer is not safe. Everything else must already be a numeric literal
/// — accepting arbitrary host names here would mean silently doing a DNS lookup for something
/// the caller almost certainly meant as a bind address, not a name to resolve.
public func resolveListenAddress(host: String) throws -> ListenAddress {
    let trimmed = host.trimmingCharacters(in: .whitespaces)

    if trimmed.lowercased() == "localhost" {
        return ListenAddress(address: "127.0.0.1", forceIPv4: true, isWildcard: false)
    }

    var ipv4Address = in_addr()
    if inet_pton(AF_INET, trimmed, &ipv4Address) == 1 {
        let isWildcard = withUnsafeBytes(of: ipv4Address) { $0.allSatisfy { $0 == 0 } }
        return ListenAddress(address: trimmed, forceIPv4: true, isWildcard: isWildcard)
    }

    var ipv6Address = in6_addr()
    if inet_pton(AF_INET6, trimmed, &ipv6Address) == 1 {
        let isWildcard = withUnsafeBytes(of: ipv6Address) { $0.allSatisfy { $0 == 0 } }
        return ListenAddress(address: trimmed, forceIPv4: false, isWildcard: isWildcard)
    }

    throw ListenAddressError.notNumeric(trimmed)
}

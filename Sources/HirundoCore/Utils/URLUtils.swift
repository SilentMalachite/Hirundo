import Foundation

/// Building the URL a generated file is published under.
///
/// One rule, in one place: **a name on disk is the decoded form, a URL is the encoded form, and
/// the encoding happens once — at the point a raw name becomes a URL component.**
///
/// Static hosting is why. nginx, Apache, GitHub Pages and S3 all percent-decode a request path
/// before they look for a file, so a directory literally named `%E3%83%86%E3%82%B9%E3%83%88` is
/// not what `/tags/%E3%83%86%E3%82%B9%E3%83%88/` asks for — it asks for `tags/テスト/`.
/// `DevelopmentServer.resolveFilePath` decodes each component for the same reason, so the
/// development server and a deployed site resolve a URL the same way.
public enum URLUtils {
    /// The characters a path component may hold as themselves: RFC 3986's unreserved set.
    ///
    /// Spelled out rather than derived from `.urlPathAllowed` minus a few characters, for three
    /// reasons. The set is then ours, not Foundation's, so a test can state it. `.urlPathAllowed`
    /// keeps `/`, which a component must not. And it keeps the sub-delimiters, of which two are
    /// worth refusing: `&`, because HTML expands `&lt` without its semicolon when what follows is
    /// neither alphanumeric nor `=`, so a path holding `&lt/` reads as `</` in any template that
    /// interpolates a URL without the `escape` filter; and `'`, because the repository spells it
    /// two ways (`&#39;` in `HTMLEscaping`, `&apos;` in `escapeXML`) and a URL should not depend
    /// on which sink it reaches.
    ///
    /// Encoding more than the minimum is safe: every consumer — `hirundo serve`, nginx, Apache,
    /// GitHub Pages, S3 — decodes the path before it looks anything up. The one escape that would
    /// change a meaning is `%2F`, and it only appears when a component really holds a slash,
    /// which no name on disk does.
    ///
    /// `%` is outside the set, which is the part that keeps "encode once" a rule a test can hold:
    /// an already-encoded string handed to ``encodedComponent(_:)`` comes back with `%25`, so
    /// encoding twice is visible rather than silent.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Turns one raw path component into a URL component.
    ///
    /// Give it a name as it is spelled on disk, never a string this function already produced.
    public static func encodedComponent(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: unreserved) ?? raw
    }

    /// Encodes a `/`-separated raw path one component at a time, keeping the separators and any
    /// leading or trailing slash.
    public static func encodedPath(_ rawPath: String) -> String {
        rawPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { encodedComponent(String($0)) }
            .joined(separator: "/")
    }

    /// The path part of `site.url`, as a prefix: `""` for a site hosted at a host's root,
    /// otherwise a leading slash and no trailing one (`https://example.com/blog/` → `/blog`).
    ///
    /// Not re-encoded. The author wrote `site.url` as a URL, so its path is already in URL form.
    public static func sitePathPrefix(of siteURL: String) -> String {
        guard let path = URLComponents(string: siteURL)?.percentEncodedPath, !path.isEmpty else {
            return ""
        }
        var prefix = path.hasPrefix("/") ? path : "/" + path
        while prefix.count > 1, prefix.hasSuffix("/") {
            prefix.removeLast()
        }
        return prefix == "/" ? "" : prefix
    }

    /// Joins a site base URL and an **already-encoded** site-relative path.
    ///
    /// - Parameters:
    ///   - base: The site's base URL. Only its origin is used — `https://example.com/blog`
    ///     contributes `https://example.com` — because `path` already carries the base path (see
    ///     ``sitePathPrefix(of:)``, which `SiteGenerator.siteRelativePath` prepends). Taking both
    ///     would publish `/blog/blog/…`.
    ///   - path: A site-relative URL, already percent-encoded by ``encodedPath(_:)``. It is
    ///     concatenated rather than appended as a path component: `appendingPathComponent` treats
    ///     its argument as raw and would turn `%E3%83%86` into `%25E3%2583%2586`.
    /// - Returns: A normalized absolute URL string.
    public static func joinSiteURL(base: String, path: String) -> String {
        return origin(of: base) + normalizeLeadingSlash(for: path)
    }

    /// `scheme://host[:port]` of a site URL, with any path, query and fragment dropped.
    private static func origin(of siteURL: String) -> String {
        guard var components = URLComponents(string: siteURL), components.scheme != nil else {
            return trimTrailingSlash(from: siteURL)
        }
        components.percentEncodedPath = ""
        components.query = nil
        components.fragment = nil
        guard let origin = components.string else {
            return trimTrailingSlash(from: siteURL)
        }
        return trimTrailingSlash(from: origin)
    }

    private static func trimTrailingSlash(from s: String) -> String {
        guard s.count > 1, s.hasSuffix("/") else { return s }
        return String(s.dropLast())
    }

    private static func normalizeLeadingSlash(for s: String) -> String {
        if s.isEmpty { return "/" }
        return s.hasPrefix("/") ? s : "/" + s
    }
}

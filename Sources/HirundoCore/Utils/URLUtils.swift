import Foundation

public enum URLUtils {
    /// Joins a site base URL and a relative path, normalizing slashes safely.
    /// - Parameters:
    ///   - base: Site base URL, e.g. "https://example.com" or "https://example.com/blog" (trailing slash optional)
    ///   - path: Relative path starting with or without leading slash, e.g. "/about/" or "posts/hello/"
    /// - Returns: A normalized absolute URL string
    public static func joinSiteURL(base: String, path: String) -> String {
        // Fast path for empty path
        let trimmedBase = trimTrailingSlash(from: base)
        let cleanedPath = normalizeLeadingSlash(for: path)
        
        // If the path is exactly "/", just ensure base ends with a single trailing slash
        if cleanedPath == "/" {
            return trimmedBase + "/"
        }
        
        // Try Foundation URL joining for correctness
        if let baseURL = URL(string: trimmedBase) {
            let rel = String(cleanedPath.dropFirst()) // drop leading "/" for appendingPathComponent
            let joined = baseURL.appendingPathComponent(rel)
            return joined.absoluteString
        }
        
        // Fallback to manual concatenation
        return trimmedBase + cleanedPath
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

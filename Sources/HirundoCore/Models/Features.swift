import Foundation

/// Built-in feature toggles (stage 1: internalize plugins as features)
public struct Features: Codable, Sendable, Equatable {
    public var sitemap: Bool
    public var rss: Bool
    public var searchIndex: Bool
    public var minify: Bool

    public init(sitemap: Bool = false, rss: Bool = false, searchIndex: Bool = false, minify: Bool = false) {
        self.sitemap = sitemap
        self.rss = rss
        self.searchIndex = searchIndex
        self.minify = minify
    }

    // Legacy plugin mapping removed in Stage 2
}

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

    enum CodingKeys: String, CodingKey, CaseIterable {
        case sitemap, rss, searchIndex, minify
    }

    /// Decodes every flag independently, defaulting to off.
    ///
    /// The synthesized decoder would require all four keys, so `features:` with a single flag
    /// under it failed the whole configuration parse. Every other optional block (`build`,
    /// `server`, `blog`, `limits`) defaults its missing keys, and so does this one.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sitemap = try container.decodeIfPresent(Bool.self, forKey: .sitemap) ?? false
        self.rss = try container.decodeIfPresent(Bool.self, forKey: .rss) ?? false
        self.searchIndex = try container.decodeIfPresent(Bool.self, forKey: .searchIndex) ?? false
        self.minify = try container.decodeIfPresent(Bool.self, forKey: .minify) ?? false
    }

    // Legacy plugin mapping removed in Stage 2
}

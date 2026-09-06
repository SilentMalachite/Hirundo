import Foundation

// Page model
public struct Page {
    public let title: String
    public let slug: String
    public let url: String
    public let description: String?
    public let content: String
    
    public init(title: String, slug: String, url: String, description: String? = nil, content: String) {
        self.title = title
        self.slug = slug
        self.url = url
        self.description = description
        self.content = content
    }
}

// Post model
public struct Post {
    public let title: String
    public let slug: String
    public let url: String
    public let date: Date
    public let author: String?
    public let description: String?
    public let categories: [String]
    public let tags: [String]
    public let content: String
    
    public init(
        title: String,
        slug: String,
        url: String,
        date: Date,
        author: String? = nil,
        description: String? = nil,
        categories: [String] = [],
        tags: [String] = [],
        content: String
    ) {
        self.title = title
        self.slug = slug
        self.url = url
        self.date = date
        self.author = author
        self.description = description
        self.categories = categories
        self.tags = tags
        self.content = content
    }
}

// MARK: - Content and Asset Items (formerly in plugin module)

public struct ContentItem: Sendable {
    public var path: String
    public var frontMatter: [String: AnyCodable]
    public var content: String
    public let type: ContentType
    
    public enum ContentType: Equatable, Sendable { case post, page }
    
    public init(path: String, frontMatter: [String: Any], content: String, type: ContentType) {
        self.path = path
        self.frontMatter = frontMatter.mapValues { AnyCodable($0) }
        self.content = content
        self.type = type
    }
    
    public init(path: String, frontMatter: [String: AnyCodable], content: String, type: ContentType) {
        self.path = path
        self.frontMatter = frontMatter
        self.content = content
        self.type = type
    }
}

public enum AssetType: Equatable, Sendable {
    case css
    case javascript
    case image(String)
    case other(String)
}

/// 1.1.x までの公開 API との互換のためだけに残している。次のメジャーバージョンで削除する。
///
/// 1.1.4 以前は `AssetType` がこの構造体のネスト型で、`AssetPipeline.detectAssetType` の
/// 戻り値も `AssetItem.AssetType` だった。この構造体自体はリポジトリ内のどこからも生成されて
/// おらず（`sourcePath` / `outputPath` / `processed` / `metadata` は誰も読まない）、ネスト型
/// だけが使われていたので、`AssetType` をトップレベルへ出した。外部の利用者が
/// `AssetItem.AssetType` と書いていてもコンパイルが通るよう、`typealias` で橋渡しする。
@available(*, deprecated, message: "Use the top-level AssetType. AssetItem will be removed in the next major version.")
public struct AssetItem: Sendable {
    public typealias AssetType = HirundoCore.AssetType

    public let sourcePath: String
    public let outputPath: String
    public let type: AssetType
    public var processed: Bool = false
    public var metadata: [String: AnyCodable] = [:]

    public init(sourcePath: String, outputPath: String, type: AssetType) {
        self.sourcePath = sourcePath
        self.outputPath = outputPath
        self.type = type
    }
}

import Foundation
import Yams

/// ブログ設定
public struct Blog: Codable, Sendable {
    public let postsPerPage: Int
    public let generateArchive: Bool
    public let generateCategories: Bool
    public let generateTags: Bool
    
    public init(
        postsPerPage: Int = 10,
        generateArchive: Bool = true,
        generateCategories: Bool = true,
        generateTags: Bool = true
    ) throws {
        // postsPerPageの検証（簡素化）
        self.postsPerPage = try ConfigValidation.validatePositiveInt(postsPerPage, fieldName: "postsPerPage")
        guard postsPerPage <= 100 else {
            throw ConfigError.invalidValue("postsPerPage cannot exceed 100")
        }
        
        self.generateArchive = generateArchive
        self.generateCategories = generateCategories
        self.generateTags = generateTags
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let postsPerPage = try container.decodeIfPresent(Int.self, forKey: .postsPerPage) ?? 10
        let generateArchive = try container.decodeIfPresent(Bool.self, forKey: .generateArchive) ?? true
        let generateCategories = try container.decodeIfPresent(Bool.self, forKey: .generateCategories) ?? true
        let generateTags = try container.decodeIfPresent(Bool.self, forKey: .generateTags) ?? true
        
        try self.init(
            postsPerPage: postsPerPage,
            generateArchive: generateArchive,
            generateCategories: generateCategories,
            generateTags: generateTags
        )
    }
    
    enum CodingKeys: String, CodingKey {
        case postsPerPage, generateArchive, generateCategories, generateTags
    }
    
    /// デフォルトのブログ設定を作成
    public static func defaultBlog() -> Blog {
        do {
            return try Blog()
        } catch {
            return Blog(postsPerPage: 10, generateArchive: true, generateCategories: true, generateTags: true, skipValidation: true)
        }
    }
    
    /// 内部イニシャライザ（検証スキップ）
    private init(postsPerPage: Int, generateArchive: Bool, generateCategories: Bool, generateTags: Bool, skipValidation: Bool) {
        self.postsPerPage = postsPerPage
        self.generateArchive = generateArchive
        self.generateCategories = generateCategories
        self.generateTags = generateTags
    }
}

/// ブログ設定のパーサー
public struct BlogConfig {
    public let blog: Blog
    
    public static func parse(from yaml: String) throws -> BlogConfig {
        do {
            let decoder = YAMLDecoder()
            let data = try decoder.decode([String: Blog].self, from: yaml)
            
            guard let blog = data["blog"] else {
                throw ConfigError.missingRequiredField("blog")
            }
            
            return BlogConfig(blog: blog)
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }
}
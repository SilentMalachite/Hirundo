import Foundation
import Yams

/// サイトの基本情報
public struct Site: Codable, Sendable {
    public let title: String
    public let description: String?
    public let url: String
    public let language: String?
    public let author: Author?
    
    public init(
        title: String,
        description: String? = nil,
        url: String,
        language: String? = "en-US",
        author: Author? = nil
    ) throws {
        // タイトルの検証（簡素化）
        self.title = try ConfigValidation.validateNonEmptyAndLength(title, maxLength: 200, fieldName: "Site title")
        
        // 説明の検証（簡素化）
        self.description = try ConfigValidation.validateOptionalLength(description, maxLength: 500, fieldName: "Site description")
        
        // URLの検証（簡素化）
        let trimmedUrl = try ConfigValidation.validateNonEmptyAndLength(url, maxLength: 2000, fieldName: "Site URL")
        guard ConfigValidation.isValidURL(trimmedUrl) else {
            throw ConfigError.invalidValue("Invalid URL format: \(trimmedUrl)")
        }
        self.url = trimmedUrl
        
        // 言語コードの検証（簡素化）
        if let language = language {
            // 35 is the longest well-formed BCP 47 language tag in practice; 10 cut off tags
            // such as `nan-Hant-TW`.
            let trimmedLanguage = try ConfigValidation.validateLength(language, maxLength: 35, fieldName: "Language code")
            guard ConfigValidation.isValidLanguageCode(trimmedLanguage) else {
                throw ConfigError.invalidValue("Invalid language code format: \(trimmedLanguage)")
            }
            self.language = trimmedLanguage
        } else {
            self.language = nil
        }
        
        self.author = author
    }
    
    /// Spelled out (rather than left to synthesis) so that `ConfigDiagnostics` can report keys
    /// the decoder ignores without keeping a second copy of this list.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case title, description, url, language, author
    }
    
    /// Routes decoding through the throwing initializer above.
    ///
    /// The synthesized decoder assigns straight to the stored properties, so every rule in that
    /// initializer — URL shape, title and description length, language code format — was dead
    /// for anything read from `config.yaml`. An absent `language` stays absent, as before.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            title: container.decode(String.self, forKey: .title),
            description: container.decodeIfPresent(String.self, forKey: .description),
            url: container.decode(String.self, forKey: .url),
            language: container.decodeIfPresent(String.self, forKey: .language),
            author: container.decodeIfPresent(Author.self, forKey: .author)
        )
    }
}

/// サイト設定のパーサー
public struct SiteConfig {
    public let site: Site
    
    public static func parse(from yaml: String) throws -> SiteConfig {
        do {
            let decoder = YAMLDecoder()
            let data = try decoder.decode([String: Site].self, from: yaml)
            
            guard let site = data["site"] else {
                throw ConfigError.missingRequiredField("site")
            }
            
            return SiteConfig(site: site)
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }
}
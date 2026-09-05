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
        author: Author? = nil,
        limits: Limits = Limits()
    ) throws {
        // タイトルの検証（簡素化）
        self.title = try ConfigValidation.validateNonEmptyAndLength(title, maxLength: limits.maxTitleLength, fieldName: "Site title")
        
        // 説明の検証（簡素化）
        self.description = try ConfigValidation.validateOptionalLength(description, maxLength: limits.maxDescriptionLength, fieldName: "Site description")
        
        // URLの検証（簡素化）
        let trimmedUrl = try ConfigValidation.validateNonEmptyAndLength(url, maxLength: limits.maxUrlLength, fieldName: "Site URL")
        guard ConfigValidation.isValidURL(trimmedUrl) else {
            throw ConfigError.invalidValue("Invalid URL format: \(trimmedUrl)")
        }
        self.url = trimmedUrl
        
        // 言語コードの検証（簡素化）
        if let language = language {
            let trimmedLanguage = try ConfigValidation.validateLength(language, maxLength: limits.maxLanguageCodeLength, fieldName: "Language code")
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
        try self.init(from: decoder, limits: decoder.hirundoLimits)
    }

    /// Decodes with the parent configuration's limits, including the nested author.
    init(from decoder: Decoder, limits: Limits) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decodeAuthor() throws -> Author? {
            guard container.contains(.author), try !container.decodeNil(forKey: .author) else {
                return nil
            }
            return try Author(from: container.superDecoder(forKey: .author), limits: limits)
        }
        try self.init(
            title: container.decode(String.self, forKey: .title),
            description: container.decodeIfPresent(String.self, forKey: .description),
            url: container.decode(String.self, forKey: .url),
            language: container.decodeIfPresent(String.self, forKey: .language),
            author: decodeAuthor(),
            limits: limits
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

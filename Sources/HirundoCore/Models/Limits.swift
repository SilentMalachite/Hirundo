import Foundation

/// セキュリティとパフォーマンス制限設定
public struct Limits: Codable, Sendable {
    public let maxMarkdownFileSize: Int
    public let maxConfigFileSize: Int
    public let maxFrontMatterSize: Int
    public let maxFilenameLength: Int
    public let maxTitleLength: Int
    public let maxDescriptionLength: Int
    public let maxUrlLength: Int
    public let maxAuthorNameLength: Int
    public let maxEmailLength: Int
    public let maxLanguageCodeLength: Int
    
    public init(
        maxMarkdownFileSize: Int = 10_485_760, // 10MB
        maxConfigFileSize: Int = 1_048_576, // 1MB
        maxFrontMatterSize: Int = 100_000, // 100KB
        maxFilenameLength: Int = 255,
        maxTitleLength: Int = 200,
        maxDescriptionLength: Int = 500,
        maxUrlLength: Int = 2000,
        maxAuthorNameLength: Int = 100,
        maxEmailLength: Int = 254,
        maxLanguageCodeLength: Int = 10
    ) {
        self.maxMarkdownFileSize = maxMarkdownFileSize
        self.maxConfigFileSize = maxConfigFileSize
        self.maxFrontMatterSize = maxFrontMatterSize
        self.maxFilenameLength = maxFilenameLength
        self.maxTitleLength = maxTitleLength
        self.maxDescriptionLength = maxDescriptionLength
        self.maxUrlLength = maxUrlLength
        self.maxAuthorNameLength = maxAuthorNameLength
        self.maxEmailLength = maxEmailLength
        self.maxLanguageCodeLength = maxLanguageCodeLength
    }
    
    enum CodingKeys: String, CodingKey, CaseIterable {
        case maxMarkdownFileSize, maxConfigFileSize, maxFrontMatterSize, maxFilenameLength
        case maxTitleLength, maxDescriptionLength, maxUrlLength, maxAuthorNameLength
        case maxEmailLength, maxLanguageCodeLength
    }
    
    /// Decodes every limit independently, falling back to the default above.
    ///
    /// The synthesized decoder required all ten keys, so raising a single limit meant restating
    /// the other nine. The defaults live in one place: the memberwise initializer.
    ///
    /// Values are checked here rather than in that initializer, which is non-throwing and is
    /// what supplies the defaults. Every limit is a size or a length, so zero and negative
    /// values are always a mistake — `maxMarkdownFileSize: 0` would otherwise make every
    /// Markdown file "too large" with an error that names neither the limit nor the config.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Limits()
        func limit(_ key: CodingKeys, or fallback: Int) throws -> Int {
            guard let decoded = try container.decodeIfPresent(Int.self, forKey: key) else {
                return fallback
            }
            return try ConfigValidation.validatePositiveInt(decoded, fieldName: key.stringValue)
        }
        self.maxMarkdownFileSize = try limit(.maxMarkdownFileSize, or: defaults.maxMarkdownFileSize)
        self.maxConfigFileSize = try limit(.maxConfigFileSize, or: defaults.maxConfigFileSize)
        self.maxFrontMatterSize = try limit(.maxFrontMatterSize, or: defaults.maxFrontMatterSize)
        self.maxFilenameLength = try limit(.maxFilenameLength, or: defaults.maxFilenameLength)
        self.maxTitleLength = try limit(.maxTitleLength, or: defaults.maxTitleLength)
        self.maxDescriptionLength = try limit(.maxDescriptionLength, or: defaults.maxDescriptionLength)
        self.maxUrlLength = try limit(.maxUrlLength, or: defaults.maxUrlLength)
        self.maxAuthorNameLength = try limit(.maxAuthorNameLength, or: defaults.maxAuthorNameLength)
        self.maxEmailLength = try limit(.maxEmailLength, or: defaults.maxEmailLength)
        self.maxLanguageCodeLength = try limit(.maxLanguageCodeLength, or: defaults.maxLanguageCodeLength)
    }
}
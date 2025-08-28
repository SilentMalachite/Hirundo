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
}
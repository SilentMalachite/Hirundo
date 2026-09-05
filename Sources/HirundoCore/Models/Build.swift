import Foundation
import Yams

/// ビルド設定
public struct Build: Codable, Sendable {
    public let contentDirectory: String
    public let outputDirectory: String
    public let staticDirectory: String
    public let templatesDirectory: String
    
    public init(
        contentDirectory: String = "content",
        outputDirectory: String = "_site",
        staticDirectory: String = "static",
        templatesDirectory: String = "templates"
    ) throws {
        // ディレクトリパスの検証（簡素化）
        try Self.validateDirectory(contentDirectory, name: "contentDirectory")
        try Self.validateDirectory(outputDirectory, name: "outputDirectory")
        try Self.validateDirectory(staticDirectory, name: "staticDirectory")
        try Self.validateDirectory(templatesDirectory, name: "templatesDirectory")
        
        // ディレクトリの重複チェック（簡素化）
        let directories = [contentDirectory, staticDirectory, templatesDirectory]
        let uniqueDirectories = Set(directories)
        if uniqueDirectories.count != directories.count {
            throw ConfigError.invalidValue("Build directories must be unique")
        }
        
        // 出力ディレクトリの重複チェック
        if directories.contains(outputDirectory) {
            throw ConfigError.invalidValue("Output directory cannot be the same as other directories")
        }
        
        self.contentDirectory = contentDirectory
        self.outputDirectory = outputDirectory
        self.staticDirectory = staticDirectory
        self.templatesDirectory = templatesDirectory
    }
    
    /// デフォルトのビルド設定を作成
    public static func defaultBuild() -> Build {
        // The four directory names below are distinct and relative, which is everything the
        // initializer validates, so this cannot actually throw.
        return try! Build()
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let contentDirectory = try container.decodeIfPresent(String.self, forKey: .contentDirectory) ?? "content"
        let outputDirectory = try container.decodeIfPresent(String.self, forKey: .outputDirectory) ?? "_site"
        let staticDirectory = try container.decodeIfPresent(String.self, forKey: .staticDirectory) ?? "static"
        let templatesDirectory = try container.decodeIfPresent(String.self, forKey: .templatesDirectory) ?? "templates"
        
        try self.init(
            contentDirectory: contentDirectory,
            outputDirectory: outputDirectory,
            staticDirectory: staticDirectory,
            templatesDirectory: templatesDirectory
        )
    }
    
    enum CodingKeys: String, CodingKey, CaseIterable {
        case contentDirectory, outputDirectory, staticDirectory, templatesDirectory
    }
    
    /// ディレクトリパスの検証（簡素化）
    private static func validateDirectory(_ path: String, name: String) throws {
        let trimmedPath = try ConfigValidation.validateNonEmptyAndLength(path, maxLength: 255, fieldName: name)
        
        // 禁止文字のチェック（簡素化）
        let forbiddenChars = CharacterSet(charactersIn: "<>:\"|?*\0")
        if trimmedPath.rangeOfCharacter(from: forbiddenChars) != nil {
            throw ConfigError.invalidValue("\(name) contains forbidden characters")
        }
        
        // パストラバーサルチェック
        if trimmedPath.contains("..") {
            throw ConfigError.invalidValue("\(name) cannot contain path traversal sequences")
        }
        
        // 絶対パスチェック
        if trimmedPath.hasPrefix("/") || trimmedPath.hasPrefix("\\") {
            throw ConfigError.invalidValue("\(name) cannot be an absolute path")
        }
    }
}

/// ビルド設定のパーサー
public struct BuildConfig {
    public let build: Build
    
    public static func parse(from yaml: String) throws -> BuildConfig {
        do {
            let decoder = YAMLDecoder()
            let data = try decoder.decode([String: Build].self, from: yaml)
            
            guard let build = data["build"] else {
                throw ConfigError.missingRequiredField("build")
            }
            
            return BuildConfig(build: build)
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }
}
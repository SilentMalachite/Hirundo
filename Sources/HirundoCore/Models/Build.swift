import Foundation
import Yams

/// ビルド設定
public struct Build: Codable, Sendable {
    public let contentDirectory: String
    public let outputDirectory: String
    public let staticDirectory: String
    public let templatesDirectory: String
    public let enableAssetFingerprinting: Bool?
    public let enableSourceMaps: Bool?
    public let concatenateJS: Bool?
    public let concatenateCSS: Bool?
    
    public init(
        contentDirectory: String = "content",
        outputDirectory: String = "_site",
        staticDirectory: String = "static",
        templatesDirectory: String = "templates",
        enableAssetFingerprinting: Bool? = nil,
        enableSourceMaps: Bool? = nil,
        concatenateJS: Bool? = nil,
        concatenateCSS: Bool? = nil
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
        self.enableAssetFingerprinting = enableAssetFingerprinting
        self.enableSourceMaps = enableSourceMaps
        self.concatenateJS = concatenateJS
        self.concatenateCSS = concatenateCSS
    }
    
    /// デフォルトのビルド設定を作成
    public static func defaultBuild() -> Build {
        do {
            return try Build()
        } catch {
            // エラーが発生した場合は安全なデフォルト値を使用
            return Build(
                contentDirectory: "content",
                outputDirectory: "_site",
                staticDirectory: "static",
                templatesDirectory: "templates",
                enableAssetFingerprinting: nil,
                enableSourceMaps: nil,
                concatenateJS: nil,
                concatenateCSS: nil,
                skipValidation: true
            )
        }
    }
    
    /// 内部イニシャライザ（検証スキップ）
    private init(
        contentDirectory: String,
        outputDirectory: String,
        staticDirectory: String,
        templatesDirectory: String,
        enableAssetFingerprinting: Bool?,
        enableSourceMaps: Bool?,
        concatenateJS: Bool?,
        concatenateCSS: Bool?,
        skipValidation: Bool
    ) {
        self.contentDirectory = contentDirectory
        self.outputDirectory = outputDirectory
        self.staticDirectory = staticDirectory
        self.templatesDirectory = templatesDirectory
        self.enableAssetFingerprinting = enableAssetFingerprinting
        self.enableSourceMaps = enableSourceMaps
        self.concatenateJS = concatenateJS
        self.concatenateCSS = concatenateCSS
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let contentDirectory = try container.decodeIfPresent(String.self, forKey: .contentDirectory) ?? "content"
        let outputDirectory = try container.decodeIfPresent(String.self, forKey: .outputDirectory) ?? "_site"
        let staticDirectory = try container.decodeIfPresent(String.self, forKey: .staticDirectory) ?? "static"
        let templatesDirectory = try container.decodeIfPresent(String.self, forKey: .templatesDirectory) ?? "templates"
        let enableAssetFingerprinting = try container.decodeIfPresent(Bool.self, forKey: .enableAssetFingerprinting)
        let enableSourceMaps = try container.decodeIfPresent(Bool.self, forKey: .enableSourceMaps)
        let concatenateJS = try container.decodeIfPresent(Bool.self, forKey: .concatenateJS)
        let concatenateCSS = try container.decodeIfPresent(Bool.self, forKey: .concatenateCSS)
        
        try self.init(
            contentDirectory: contentDirectory,
            outputDirectory: outputDirectory,
            staticDirectory: staticDirectory,
            templatesDirectory: templatesDirectory,
            enableAssetFingerprinting: enableAssetFingerprinting,
            enableSourceMaps: enableSourceMaps,
            concatenateJS: concatenateJS,
            concatenateCSS: concatenateCSS
        )
    }
    
    enum CodingKeys: String, CodingKey {
        case contentDirectory, outputDirectory, staticDirectory, templatesDirectory
        case enableAssetFingerprinting, enableSourceMaps, concatenateJS, concatenateCSS
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
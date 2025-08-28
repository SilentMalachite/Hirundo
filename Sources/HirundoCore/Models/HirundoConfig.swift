import Foundation
import Yams

/// Hirundoのメイン設定構造体
public struct HirundoConfig: Codable, Sendable {
    public let site: Site
    public let build: Build
    public let server: Server
    public let blog: Blog
    public let plugins: [PluginConfiguration]
    public let limits: Limits
    public let timeouts: TimeoutConfig
    
    enum CodingKeys: String, CodingKey {
        case site, build, server, blog, plugins, limits, timeouts
    }
    
    public init(
        site: Site,
        build: Build = Build.defaultBuild(),
        server: Server = Server.defaultServer(),
        blog: Blog = Blog.defaultBlog(),
        plugins: [PluginConfiguration] = [],
        limits: Limits = Limits(),
        timeouts: TimeoutConfig = TimeoutConfig.defaultTimeout()
    ) {
        self.site = site
        self.build = build
        self.server = server
        self.blog = blog
        self.plugins = plugins
        self.limits = limits
        self.timeouts = timeouts
    }
    
    /// テストと開発用のデフォルト設定を作成
    public static func createDefault() -> HirundoConfig {
        do {
            let defaultSite = try Site(
                title: "Test Site",
                description: "A test site for development",
                url: "https://localhost:8080",
                language: "en-US",
                author: try Author(name: "Test Author", email: "test@example.com")
            )
            
            return HirundoConfig(
                site: defaultSite,
                build: Build.defaultBuild(),
                server: Server.defaultServer(),
                blog: Blog.defaultBlog(),
                plugins: [],
                limits: Limits(),
                timeouts: TimeoutConfig.defaultTimeout()
            )
        } catch {
            // フォールバック設定
            do {
                let fallbackSite = try Site(
                    title: "Test Site",
                    description: nil,
                    url: "https://localhost:8080",
                    language: "en-US",
                    author: nil
                )
                
                return HirundoConfig(
                    site: fallbackSite,
                    build: Build.defaultBuild(),
                    server: Server.defaultServer(),
                    blog: Blog.defaultBlog(),
                    plugins: [],
                    limits: Limits(),
                    timeouts: TimeoutConfig.defaultTimeout()
                )
            } catch {
                fatalError("Unable to create even minimal default configuration: \(error)")
            }
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.site = try container.decode(Site.self, forKey: .site)
        self.build = try container.decodeIfPresent(Build.self, forKey: .build) ?? Build.defaultBuild()
        self.server = try container.decodeIfPresent(Server.self, forKey: .server) ?? Server.defaultServer()
        self.blog = try container.decodeIfPresent(Blog.self, forKey: .blog) ?? Blog.defaultBlog()
        self.plugins = try container.decodeIfPresent([PluginConfiguration].self, forKey: .plugins) ?? []
        self.limits = try container.decodeIfPresent(Limits.self, forKey: .limits) ?? Limits()
        self.timeouts = try container.decodeIfPresent(TimeoutConfig.self, forKey: .timeouts) ?? TimeoutConfig.defaultTimeout()
    }
    
    /// YAML文字列から設定を解析
    public static func parse(from yaml: String) throws -> HirundoConfig {
        do {
            let decoder = YAMLDecoder()
            let config = try decoder.decode(HirundoConfig.self, from: yaml)
            
            if config.site.url.isEmpty {
                throw ConfigError.missingRequiredField("url")
            }
            
            return config
        } catch let error as ConfigError {
            throw error
        } catch let error as DecodingError {
            switch error {
            case .keyNotFound(let key, _):
                if key.stringValue == "url" {
                    throw ConfigError.missingRequiredField("url")
                }
                throw ConfigError.invalidFormat("Missing key: \(key.stringValue)")
            case .typeMismatch(let type, let context):
                throw ConfigError.invalidFormat("Type mismatch: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .valueNotFound(let type, let context):
                throw ConfigError.invalidFormat("Value not found: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
            case .dataCorrupted(let context):
                throw ConfigError.invalidFormat("Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)")
            default:
                throw ConfigError.parseError("YAML parsing failed: \(String(describing: error))")
            }
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }
    
    /// ファイルから設定を読み込み
    public static func load(from url: URL) throws -> HirundoConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigError.fileNotFound(url.path)
        }
        
        do {
            let yaml = try String(contentsOf: url, encoding: .utf8)
            let config = try parse(from: yaml)
            
            // 設定ファイルサイズの検証
            guard yaml.count <= config.limits.maxConfigFileSize else {
                let maxSizeMB = config.limits.maxConfigFileSize / 1_048_576
                throw ConfigError.invalidValue("Configuration file too large (max \(maxSizeMB)MB)")
            }
            
            return config
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }
}
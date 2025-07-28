import Foundation
import Yams

public struct Author: Codable {
    public let name: String
    public let email: String?
    
    public init(name: String, email: String? = nil) throws {
        // Validate name
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigError.invalidValue("Author name cannot be empty")
        }
        guard name.count <= 100 else {
            throw ConfigError.invalidValue("Author name cannot exceed 100 characters")
        }
        
        // Validate email if provided
        if let email = email {
            guard email.count <= 254 else {
                throw ConfigError.invalidValue("Email cannot exceed 254 characters")
            }
            guard isValidEmail(email) else {
                throw ConfigError.invalidValue("Invalid email format: \(email)")
            }
        }
        
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = email
    }
}

public struct Site: Codable {
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
        // Validate title
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigError.invalidValue("Site title cannot be empty")
        }
        guard title.count <= 200 else {
            throw ConfigError.invalidValue("Site title cannot exceed 200 characters")
        }
        
        // Validate description
        if let description = description {
            guard description.count <= 500 else {
                throw ConfigError.invalidValue("Site description cannot exceed 500 characters")
            }
        }
        
        // Validate URL
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigError.invalidValue("Site URL cannot be empty")
        }
        guard url.count <= 2000 else {
            throw ConfigError.invalidValue("Site URL cannot exceed 2000 characters")
        }
        guard isValidURL(url) else {
            throw ConfigError.invalidValue("Invalid URL format: \(url)")
        }
        
        // Validate language code
        if let language = language {
            guard language.count <= 10 else {
                throw ConfigError.invalidValue("Language code cannot exceed 10 characters")
            }
            guard isValidLanguageCode(language) else {
                throw ConfigError.invalidValue("Invalid language code format: \(language)")
            }
        }
        
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language
        self.author = author
    }
}

public struct SiteConfig {
    public let site: Site
    
    public static func parse(from yaml: String) throws -> SiteConfig {
        do {
            let decoder = YAMLDecoder()
            let data = try decoder.decode([String: Site].self, from: yaml)
            
            guard let site = data["site"] else {
                throw ConfigError.missingRequiredField("site")
            }
            
            if site.url.isEmpty {
                throw ConfigError.missingRequiredField("url")
            }
            
            return SiteConfig(site: site)
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }
}

public struct Build: Codable {
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
}

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

public struct Server: Codable {
    public let port: Int
    public let liveReload: Bool
    public let cors: CorsConfig?
    
    public init(port: Int = 8080, liveReload: Bool = true, cors: CorsConfig? = nil) {
        self.port = port
        self.liveReload = liveReload
        self.cors = cors
    }
}

// CORS configuration
public struct CorsConfig: Codable {
    public let enabled: Bool
    public let allowedOrigins: [String]
    public let allowedMethods: [String]
    public let allowedHeaders: [String]
    public let exposedHeaders: [String]?
    public let maxAge: Int?
    public let allowCredentials: Bool
    
    public init(
        enabled: Bool = true,
        allowedOrigins: [String] = ["http://localhost:*", "https://localhost:*"],
        allowedMethods: [String] = ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowedHeaders: [String] = ["Content-Type", "Authorization"],
        exposedHeaders: [String]? = nil,
        maxAge: Int? = 3600,
        allowCredentials: Bool = false
    ) {
        self.enabled = enabled
        self.allowedOrigins = allowedOrigins
        self.allowedMethods = allowedMethods
        self.allowedHeaders = allowedHeaders
        self.exposedHeaders = exposedHeaders
        self.maxAge = maxAge
        self.allowCredentials = allowCredentials
    }
}

public struct ServerConfig {
    public let server: Server
    
    public static func parse(from yaml: String) throws -> ServerConfig {
        do {
            let decoder = YAMLDecoder()
            let data = try decoder.decode([String: Server].self, from: yaml)
            
            guard let server = data["server"] else {
                throw ConfigError.missingRequiredField("server")
            }
            
            return ServerConfig(server: server)
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }
}

public struct Blog: Codable {
    public let postsPerPage: Int
    public let generateArchive: Bool
    public let generateCategories: Bool
    public let generateTags: Bool
    
    public init(
        postsPerPage: Int = 10,
        generateArchive: Bool = true,
        generateCategories: Bool = true,
        generateTags: Bool = true
    ) {
        self.postsPerPage = postsPerPage
        self.generateArchive = generateArchive
        self.generateCategories = generateCategories
        self.generateTags = generateTags
    }
}

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


public struct PluginsConfig {
    public let plugins: [HirundoConfig.PluginConfiguration]
    
    public static func parse(from yaml: String) throws -> PluginsConfig {
        do {
            let decoder = YAMLDecoder()
            let data = try decoder.decode([String: [HirundoConfig.PluginConfiguration]].self, from: yaml)
            
            guard let plugins = data["plugins"] else {
                throw ConfigError.missingRequiredField("plugins")
            }
            
            return PluginsConfig(plugins: plugins)
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }
}

// Security and performance limits configuration
public struct Limits: Codable {
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

public struct HirundoConfig: Codable {
    // Plugin configuration
    public struct PluginConfiguration: Codable {
        public let name: String
        public let enabled: Bool
        public let settings: [String: Any]
        
        private struct DynamicCodingKeys: CodingKey {
            var stringValue: String
            init?(stringValue: String) {
                self.stringValue = stringValue
            }
            
            var intValue: Int?
            init?(intValue: Int) {
                return nil
            }
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
            
            // Required fields
            guard let nameKey = DynamicCodingKeys(stringValue: "name") else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Could not create key for 'name'"
                ))
            }
            self.name = try container.decode(String.self, forKey: nameKey)
            
            // Optional enabled field
            if let enabledKey = DynamicCodingKeys(stringValue: "enabled") {
                self.enabled = try container.decodeIfPresent(Bool.self, forKey: enabledKey) ?? true
            } else {
                self.enabled = true
            }
            
            // Collect all other fields as settings
            var settings: [String: Any] = [:]
            for key in container.allKeys {
                if key.stringValue != "name" && key.stringValue != "enabled" {
                    settings[key.stringValue] = try container.decode(AnyCodable.self, forKey: key).value
                }
            }
            self.settings = settings
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicCodingKeys.self)
            
            guard let nameKey = DynamicCodingKeys(stringValue: "name") else {
                throw EncodingError.invalidValue("name", EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Could not create key for 'name'"
                ))
            }
            try container.encode(name, forKey: nameKey)
            
            if let enabledKey = DynamicCodingKeys(stringValue: "enabled") {
                try container.encode(enabled, forKey: enabledKey)
            }
            
            for (key, value) in settings {
                if let codingKey = DynamicCodingKeys(stringValue: key) {
                    try container.encode(AnyCodable(value), forKey: codingKey)
                }
            }
        }
    }
    
    public let site: Site
    public let build: Build
    public let server: Server
    public let blog: Blog
    public let plugins: [PluginConfiguration]
    public let limits: Limits
    
    enum CodingKeys: String, CodingKey {
        case site, build, server, blog, plugins, limits
    }
    
    public init(
        site: Site,
        build: Build = Build(),
        server: Server = Server(),
        blog: Blog = Blog(),
        plugins: [PluginConfiguration] = [],
        limits: Limits = Limits()
    ) {
        self.site = site
        self.build = build
        self.server = server
        self.blog = blog
        self.plugins = plugins
        self.limits = limits
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.site = try container.decode(Site.self, forKey: .site)
        self.build = try container.decodeIfPresent(Build.self, forKey: .build) ?? Build()
        self.server = try container.decodeIfPresent(Server.self, forKey: .server) ?? Server()
        self.blog = try container.decodeIfPresent(Blog.self, forKey: .blog) ?? Blog()
        self.plugins = try container.decodeIfPresent([PluginConfiguration].self, forKey: .plugins) ?? []
        self.limits = try container.decodeIfPresent(Limits.self, forKey: .limits) ?? Limits()
    }
    
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
                throw ConfigError.invalidFormat(error.localizedDescription)
            case .typeMismatch(_, _):
                throw ConfigError.invalidFormat(error.localizedDescription)
            default:
                throw ConfigError.parseError(error.localizedDescription)
            }
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }
    
    public static func load(from url: URL) throws -> HirundoConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigError.fileNotFound(url.path)
        }
        
        do {
            let yaml = try String(contentsOf: url, encoding: .utf8)
            
            // Parse config first to get limits
            let config = try parse(from: yaml)
            
            // Validate YAML size using configured limits
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

// MARK: - Validation Utilities

/// Validates an email address format
/// - Parameter email: The email to validate
/// - Returns: True if the email is valid, false otherwise
private func isValidEmail(_ email: String) -> Bool {
    let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
    let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
    return emailPredicate.evaluate(with: email)
}

/// Validates a URL format
/// - Parameter url: The URL to validate
/// - Returns: True if the URL is valid, false otherwise
private func isValidURL(_ url: String) -> Bool {
    // Check for basic URL structure
    guard let urlComponents = URLComponents(string: url) else {
        return false
    }
    
    // Must have a scheme (http/https)
    guard let scheme = urlComponents.scheme?.lowercased(),
          ["http", "https"].contains(scheme) else {
        return false
    }
    
    // Must have a host
    guard let host = urlComponents.host, !host.isEmpty else {
        return false
    }
    
    // Prevent dangerous schemes and local addresses
    if host.hasPrefix("localhost") || host.hasPrefix("127.0.0.1") || host.hasPrefix("0.0.0.0") {
        return false
    }
    
    return true
}

/// Validates a language code format (e.g., "en", "en-US", "ja-JP")
/// - Parameter languageCode: The language code to validate
/// - Returns: True if the language code is valid, false otherwise
private func isValidLanguageCode(_ languageCode: String) -> Bool {
    let languageRegex = "^[a-z]{2,3}(-[A-Z]{2})?$"
    let languagePredicate = NSPredicate(format: "SELF MATCHES %@", languageRegex)
    return languagePredicate.evaluate(with: languageCode)
}
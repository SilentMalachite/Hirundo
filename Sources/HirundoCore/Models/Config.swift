import Foundation
import Yams

public struct Author: Codable, Sendable {
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
        // Basic path validation
        try Self.validateDirectory(contentDirectory, name: "contentDirectory")
        try Self.validateDirectory(outputDirectory, name: "outputDirectory")
        try Self.validateDirectory(staticDirectory, name: "staticDirectory")
        try Self.validateDirectory(templatesDirectory, name: "templatesDirectory")
        
        // Cross-relationship validation (check for directory duplication)
        let directories = [contentDirectory, staticDirectory, templatesDirectory]
        let uniqueDirectories = Set(directories)
        if uniqueDirectories.count != directories.count {
            throw ConfigError.invalidValue("Build directories must be unique (content, static, templates)")
        }
        
        // Ensure output directory is not the same as other directories
        if directories.contains(outputDirectory) {
            throw ConfigError.invalidValue("Output directory cannot be the same as content, static, or templates directory")
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
    
    /// Non-throwing convenience initializer (for compatibility with existing code)
    public static func defaultBuild() -> Build {
        do {
            return try Build()
        } catch {
            // Use safe default values if an error occurs
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
    
    /// Internal initializer (validation skipped)
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
    
    /// Directory path validation
    private static func validateDirectory(_ path: String, name: String) throws {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigError.invalidValue("\(name) cannot be empty")
        }
        
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Length check
        guard trimmedPath.count <= 255 else {
            throw ConfigError.invalidValue("\(name) path cannot exceed 255 characters")
        }
        
        // Forbidden characters check
        let forbiddenChars = CharacterSet(charactersIn: "<>:\"|?*\0")
        if trimmedPath.rangeOfCharacter(from: forbiddenChars) != nil {
            throw ConfigError.invalidValue("\(name) contains forbidden characters")
        }
        
        // Path traversal check
        if trimmedPath.contains("..") {
            throw ConfigError.invalidValue("\(name) cannot contain path traversal sequences (..)")
        }
        
        // Absolute path check
        if trimmedPath.hasPrefix("/") || trimmedPath.hasPrefix("\\") {
            throw ConfigError.invalidValue("\(name) cannot be an absolute path")
        }
        
        // Special directory names check
        let specialDirs = [".git", ".svn", ".hg", "node_modules", ".DS_Store"]
        for specialDir in specialDirs {
            if trimmedPath.contains(specialDir) {
                throw ConfigError.invalidValue("\(name) cannot contain special directory: \(specialDir)")
            }
        }
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

public struct Server: Codable, Sendable {
    public let port: Int
    public let liveReload: Bool
    public let cors: CorsConfig?
    public let websocketAuth: WebSocketAuthConfig?
    
    public init(port: Int = 8080, liveReload: Bool = true, cors: CorsConfig? = nil, websocketAuth: WebSocketAuthConfig? = nil) throws {
        // Detailed port number validation
        try Self.validatePort(port)
        
        self.port = port
        self.liveReload = liveReload
        self.cors = cors
        self.websocketAuth = websocketAuth
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 8080
        let liveReload = try container.decodeIfPresent(Bool.self, forKey: .liveReload) ?? true
        let cors = try container.decodeIfPresent(CorsConfig.self, forKey: .cors)
        let websocketAuth = try container.decodeIfPresent(WebSocketAuthConfig.self, forKey: .websocketAuth)
        
        try self.init(port: port, liveReload: liveReload, cors: cors, websocketAuth: websocketAuth)
    }
    
    enum CodingKeys: String, CodingKey {
        case port, liveReload, cors, websocketAuth
    }
    
    /// Detailed port number validation
    private static func validatePort(_ port: Int) throws {
        // Basic range check
        guard port > 0 && port <= 65535 else {
            throw ConfigError.invalidValue("Port must be between 1 and 65535")
        }
        
        // System reserved ports check (1-1023)
        if port <= 1023 && port != 8080 && port != 3000 && port != 4000 {
            throw ConfigError.invalidValue("Port \(port) is in the system reserved range (1-1023). Use ports above 1023 for development.")
        }
        
        // Warning for commonly used service ports
        let commonServicePorts = [22, 25, 53, 80, 110, 143, 443, 993, 995, 3306, 5432, 6379, 27017]
        if commonServicePorts.contains(port) {
            throw ConfigError.invalidValue("Port \(port) is commonly used by other services. Consider using a different port.")
        }
        
        // Recommend default development port range
        if port < 3000 || port > 9999 {
            print("[Warning] Port \(port) is outside the common development range (3000-9999). This may cause conflicts.")
        }
    }
    
    /// Non-throwing convenience initializer (compatibility with existing code)
    public static func defaultServer() -> Server {
        do {
            return try Server()
        } catch {
            return Server(port: 8080, liveReload: true, cors: nil, websocketAuth: nil, skipValidation: true)
        }
    }
    
    /// Internal initializer (validation skipped)
    private init(port: Int, liveReload: Bool, cors: CorsConfig?, websocketAuth: WebSocketAuthConfig?, skipValidation: Bool) {
        self.port = port
        self.liveReload = liveReload
        self.cors = cors
        self.websocketAuth = websocketAuth
    }
}

// WebSocket authentication configuration
public struct WebSocketAuthConfig: Codable, Sendable {
    public let enabled: Bool
    public let tokenExpirationMinutes: Int
    public let maxActiveTokens: Int
    
    public init(
        enabled: Bool = true,
        tokenExpirationMinutes: Int = 60,
        maxActiveTokens: Int = 100
    ) throws {
        // Token expiration validation
        guard tokenExpirationMinutes > 0 else {
            throw ConfigError.invalidValue("tokenExpirationMinutes must be greater than 0")
        }
        guard tokenExpirationMinutes <= 1440 else { // 24 hours
            throw ConfigError.invalidValue("tokenExpirationMinutes cannot exceed 1440 minutes (24 hours)")
        }
        
        // Maximum active tokens validation
        guard maxActiveTokens > 0 else {
            throw ConfigError.invalidValue("maxActiveTokens must be greater than 0")
        }
        guard maxActiveTokens <= 10000 else {
            throw ConfigError.invalidValue("maxActiveTokens cannot exceed 10000 (memory consideration)")
        }
        
        // Security warning
        if tokenExpirationMinutes > 480 { // 8 hours
            print("[Warning] tokenExpirationMinutes \(tokenExpirationMinutes) is quite long. Consider shorter expiration for better security.")
        }
        
        if maxActiveTokens > 1000 {
            print("[Warning] maxActiveTokens \(maxActiveTokens) is quite high. This may impact memory usage.")
        }
        
        self.enabled = enabled
        self.tokenExpirationMinutes = tokenExpirationMinutes
        self.maxActiveTokens = maxActiveTokens
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let tokenExpirationMinutes = try container.decodeIfPresent(Int.self, forKey: .tokenExpirationMinutes) ?? 60
        let maxActiveTokens = try container.decodeIfPresent(Int.self, forKey: .maxActiveTokens) ?? 100
        
        try self.init(
            enabled: enabled,
            tokenExpirationMinutes: tokenExpirationMinutes,
            maxActiveTokens: maxActiveTokens
        )
    }
    
    enum CodingKeys: String, CodingKey {
        case enabled, tokenExpirationMinutes, maxActiveTokens
    }
    
    /// Non-throwing convenience initializer (compatibility with existing code)
    public static func defaultWebSocketAuth() -> WebSocketAuthConfig {
        do {
            return try WebSocketAuthConfig()
        } catch {
            return WebSocketAuthConfig(enabled: true, tokenExpirationMinutes: 60, maxActiveTokens: 100, skipValidation: true)
        }
    }
    
    /// Internal initializer (validation skipped)
    private init(enabled: Bool, tokenExpirationMinutes: Int, maxActiveTokens: Int, skipValidation: Bool) {
        self.enabled = enabled
        self.tokenExpirationMinutes = tokenExpirationMinutes
        self.maxActiveTokens = maxActiveTokens
    }
}

// CORS configuration
public struct CorsConfig: Codable, Sendable {
    public let enabled: Bool
    public let allowedOrigins: [String]
    public let allowedMethods: [String]
    public let allowedHeaders: [String]
    public let exposedHeaders: [String]?
    public let maxAge: Int?
    public let allowCredentials: Bool
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        enabled = try container.decode(Bool.self, forKey: .enabled)
        allowedOrigins = try container.decode([String].self, forKey: .allowedOrigins)
        allowedMethods = try container.decode([String].self, forKey: .allowedMethods)
        allowedHeaders = try container.decode([String].self, forKey: .allowedHeaders)
        exposedHeaders = try container.decodeIfPresent([String].self, forKey: .exposedHeaders)
        maxAge = try container.decodeIfPresent(Int.self, forKey: .maxAge)
        allowCredentials = try container.decodeIfPresent(Bool.self, forKey: .allowCredentials) ?? false
    }
    
    enum CodingKeys: String, CodingKey {
        case enabled, allowedOrigins, allowedMethods, allowedHeaders, exposedHeaders, maxAge, allowCredentials
    }
    
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
        // postsPerPage validation
        guard postsPerPage > 0 else {
            throw ConfigError.invalidValue("postsPerPage must be greater than 0")
        }
        guard postsPerPage <= 100 else {
            throw ConfigError.invalidValue("postsPerPage cannot exceed 100 (performance consideration)")
        }
        
        // Performance warning
        if postsPerPage > 50 {
            print("[Warning] postsPerPage \(postsPerPage) is quite high. Consider using a smaller value for better performance.")
        }
        
        self.postsPerPage = postsPerPage
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
    
    /// Non-throwing convenience initializer (compatibility with existing code)
    public static func defaultBlog() -> Blog {
        do {
            return try Blog()
        } catch {
            return Blog(postsPerPage: 10, generateArchive: true, generateCategories: true, generateTags: true, skipValidation: true)
        }
    }
    
    /// Internal initializer (validation skipped)
    private init(postsPerPage: Int, generateArchive: Bool, generateCategories: Bool, generateTags: Bool, skipValidation: Bool) {
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

// Timeout configuration for I/O operations
public struct TimeoutConfig: Codable, Sendable {
    public let fileReadTimeout: TimeInterval
    public let fileWriteTimeout: TimeInterval
    public let directoryOperationTimeout: TimeInterval
    public let httpRequestTimeout: TimeInterval
    public let fsEventsTimeout: TimeInterval
    public let serverStartTimeout: TimeInterval
    
    public init(
        fileReadTimeout: TimeInterval = 30.0,
        fileWriteTimeout: TimeInterval = 30.0,
        directoryOperationTimeout: TimeInterval = 15.0,
        httpRequestTimeout: TimeInterval = 10.0,
        fsEventsTimeout: TimeInterval = 5.0,
        serverStartTimeout: TimeInterval = 30.0
    ) throws {
        // Validate timeout values
        let timeouts = [
            ("fileReadTimeout", fileReadTimeout),
            ("fileWriteTimeout", fileWriteTimeout),
            ("directoryOperationTimeout", directoryOperationTimeout),
            ("httpRequestTimeout", httpRequestTimeout),
            ("fsEventsTimeout", fsEventsTimeout),
            ("serverStartTimeout", serverStartTimeout)
        ]
        
        for (name, value) in timeouts {
            guard value > 0 else {
                throw ConfigError.invalidValue("\(name) must be greater than 0")
            }
            guard value <= 600.0 else { // Maximum 10 minutes
                throw ConfigError.invalidValue("\(name) cannot exceed 600 seconds (10 minutes)")
            }
        }
        
        self.fileReadTimeout = fileReadTimeout
        self.fileWriteTimeout = fileWriteTimeout
        self.directoryOperationTimeout = directoryOperationTimeout
        self.httpRequestTimeout = httpRequestTimeout
        self.fsEventsTimeout = fsEventsTimeout
        self.serverStartTimeout = serverStartTimeout
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let fileReadTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .fileReadTimeout) ?? 30.0
        let fileWriteTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .fileWriteTimeout) ?? 30.0
        let directoryOperationTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .directoryOperationTimeout) ?? 15.0
        let httpRequestTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .httpRequestTimeout) ?? 10.0
        let fsEventsTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .fsEventsTimeout) ?? 5.0
        let serverStartTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .serverStartTimeout) ?? 30.0
        
        // Use the throwing initializer to validate
        try self.init(
            fileReadTimeout: fileReadTimeout,
            fileWriteTimeout: fileWriteTimeout,
            directoryOperationTimeout: directoryOperationTimeout,
            httpRequestTimeout: httpRequestTimeout,
            fsEventsTimeout: fsEventsTimeout,
            serverStartTimeout: serverStartTimeout
        )
    }
    
    enum CodingKeys: String, CodingKey {
        case fileReadTimeout, fileWriteTimeout, directoryOperationTimeout
        case httpRequestTimeout, fsEventsTimeout, serverStartTimeout
    }
    
    /// Non-throwing convenience initializer (compatibility with existing code)
    public static func defaultConfig() -> TimeoutConfig {
        do {
            return try TimeoutConfig()
        } catch {
            // Use safe default values if an error occurs
            return TimeoutConfig(
                fileReadTimeout: 30.0,
                fileWriteTimeout: 30.0,
                directoryOperationTimeout: 15.0,
                httpRequestTimeout: 10.0,
                fsEventsTimeout: 5.0,
                serverStartTimeout: 30.0,
                skipValidation: true
            )
        }
    }
    
    /// Internal initializer (validation skipped)
    private init(
        fileReadTimeout: TimeInterval,
        fileWriteTimeout: TimeInterval,
        directoryOperationTimeout: TimeInterval,
        httpRequestTimeout: TimeInterval,
        fsEventsTimeout: TimeInterval,
        serverStartTimeout: TimeInterval,
        skipValidation: Bool
    ) {
        self.fileReadTimeout = fileReadTimeout
        self.fileWriteTimeout = fileWriteTimeout
        self.directoryOperationTimeout = directoryOperationTimeout
        self.httpRequestTimeout = httpRequestTimeout
        self.fsEventsTimeout = fsEventsTimeout
        self.serverStartTimeout = serverStartTimeout
    }
}

public struct HirundoConfig: Codable, Sendable {
    // Plugin configuration
    public struct PluginConfiguration: Codable, Sendable {
        public let name: String
        public let enabled: Bool
        public let settings: [String: AnyCodable]
        
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
            var settings: [String: AnyCodable] = [:]
            for key in container.allKeys {
                if key.stringValue != "name" && key.stringValue != "enabled" {
                    settings[key.stringValue] = try container.decode(AnyCodable.self, forKey: key)
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
        timeouts: TimeoutConfig = TimeoutConfig.defaultConfig()
    ) {
        self.site = site
        self.build = build
        self.server = server
        self.blog = blog
        self.plugins = plugins
        self.limits = limits
        self.timeouts = timeouts
    }
    
    /// Create a default configuration for testing and development
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
                timeouts: TimeoutConfig.defaultConfig()
            )
        } catch {
            // Fallback with minimal configuration if validation fails
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
                    timeouts: TimeoutConfig.defaultConfig()
                )
            } catch {
                // If even the minimal fallback fails, create an absolute minimal config
                // This should never happen in practice, but provides a safety net
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
        self.timeouts = try container.decodeIfPresent(TimeoutConfig.self, forKey: .timeouts) ?? TimeoutConfig.defaultConfig()
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
    
    public static func load(from url: URL) throws -> HirundoConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigError.fileNotFound(url.path)
        }
        
        do {
            // Use a reasonable default timeout for config loading
            let yaml = try TimeoutFileManager.readFile(at: url.path, timeout: 10.0)
            
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
        } catch let error as TimeoutError {
            throw ConfigError.parseError("Configuration file read timed out: \(error.localizedDescription)")
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
    
    // Allow localhost for development - this is a static site generator
    // that needs to work with localhost during development
    // Still block cloud metadata endpoints for security
    let lowercasedHost = host.lowercased()
    let blockedMetadataHosts = [
        "metadata.google.internal",
        "169.254.169.254",  // AWS/GCP/Azure metadata endpoint
        "metadata.aws.internal"
    ]
    if blockedMetadataHosts.contains(lowercasedHost) {
        return false
    }
    
    return true
}

/// Checks if the given host is a private IP address
/// - Parameter host: The host to check
/// - Returns: True if the host is a private IP address, false otherwise
private func isPrivateIPAddress(_ host: String) -> Bool {
    // Parse IPv4 address
    let components = host.split(separator: ".").compactMap { Int($0) }
    guard components.count == 4 else { return false }
    
    // Check for private IP ranges (RFC 1918)
    // 10.0.0.0/8
    if components[0] == 10 {
        return true
    }
    
    // 172.16.0.0/12
    if components[0] == 172 && components[1] >= 16 && components[1] <= 31 {
        return true
    }
    
    // 192.168.0.0/16
    if components[0] == 192 && components[1] == 168 {
        return true
    }
    
    return false
}

/// Validates a language code format (e.g., "en", "en-US", "ja-JP")
/// - Parameter languageCode: The language code to validate
/// - Returns: True if the language code is valid, false otherwise
private func isValidLanguageCode(_ languageCode: String) -> Bool {
    let languageRegex = "^[a-z]{2,3}(-[A-Z]{2})?$"
    let languagePredicate = NSPredicate(format: "SELF MATCHES %@", languageRegex)
    return languagePredicate.evaluate(with: languageCode)
}
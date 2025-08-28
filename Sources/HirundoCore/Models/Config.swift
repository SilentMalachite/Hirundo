import Foundation
import Yams

// Build and BuildConfig are defined in Models/Build.swift

// Server, WebSocketAuthConfig, CorsConfig, and ServerConfig are defined in Models/Server.swift

// Blog and BlogConfig are defined in Models/Blog.swift


// PluginsConfig and PluginConfiguration are defined in Models/Plugins.swift

// Security and performance limits configuration
// Limits is defined in Models/Limits.swift

// Timeout configuration for I/O operations
// TimeoutConfig is defined in Models/Timeout.swift

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
                timeouts: TimeoutConfig.defaultTimeout()
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
                    timeouts: TimeoutConfig.defaultTimeout()
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
        self.timeouts = try container.decodeIfPresent(TimeoutConfig.self, forKey: .timeouts) ?? TimeoutConfig.defaultTimeout()
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

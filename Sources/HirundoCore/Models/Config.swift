import Foundation
import Yams

// Build and BuildConfig are defined in Models/Build.swift

// Server, WebSocketAuthConfig, CorsConfig, and ServerConfig are defined in Models/Server.swift

// Blog and BlogConfig are defined in Models/Blog.swift


// Plugin system removed in Stage 2; use Features instead

// Security and performance limits configuration
// Limits is defined in Models/Limits.swift

public struct HirundoConfig: Codable, Sendable {
    
    public let site: Site
    public let build: Build
    public let server: Server
    public let blog: Blog
    public let features: Features
    public let limits: Limits
    
    enum CodingKeys: String, CodingKey {
        case site, build, server, blog, features, limits
    }
    
    public init(
        site: Site,
        build: Build = Build.defaultBuild(),
        server: Server = Server.defaultServer(),
        blog: Blog = Blog.defaultBlog(),
        features: Features = Features(),
        limits: Limits = Limits()
    ) {
        self.site = site
        self.build = build
        self.server = server
        self.blog = blog
        self.features = features
        self.limits = limits
    }
    
    /// Create a default configuration for testing and development
    public static func createDefault() -> HirundoConfig {
        let defaultSite = try! Site(
            title: "Test Site",
            description: "A test site for development",
            url: "https://localhost:8080",
            language: "en-US",
            author: try! Author(name: "Test Author", email: "test@example.com")
        )
        
        return HirundoConfig(
            site: defaultSite,
            build: Build.defaultBuild(),
            server: Server.defaultServer(),
            blog: Blog.defaultBlog(),
            features: Features(),
            limits: Limits()
        )
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.site = try container.decode(Site.self, forKey: .site)
        self.build = try container.decodeIfPresent(Build.self, forKey: .build) ?? Build.defaultBuild()
        self.server = try container.decodeIfPresent(Server.self, forKey: .server) ?? Server.defaultServer()
        self.blog = try container.decodeIfPresent(Blog.self, forKey: .blog) ?? Blog.defaultBlog()
        // Features only (Stage 2)
        self.features = try container.decodeIfPresent(Features.self, forKey: .features) ?? Features()
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
            return try parse(from: yaml)
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

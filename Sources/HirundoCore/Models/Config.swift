import Foundation
import Yams

// Build and BuildConfig are defined in Models/Build.swift

// Server and ServerConfig are defined in Models/Server.swift.
// Server decodes only `port` and `liveReload` — there is no CORS or WebSocket auth configuration.

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
    
    /// `CaseIterable` so that `ConfigDiagnostics` can report keys the decoder ignores without
    /// keeping a second copy of this list that could drift out of sync.
    enum CodingKeys: String, CodingKey, CaseIterable {
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

        // Resolve limits here so every Codable entry point validates the same way.
        self.limits = try container.decodeIfPresent(Limits.self, forKey: .limits) ?? Limits()
        guard container.contains(.site) else {
            throw DecodingError.keyNotFound(CodingKeys.site, .init(
                codingPath: container.codingPath,
                debugDescription: "No value associated with key site."
            ))
        }
        self.site = try Site(from: container.superDecoder(forKey: .site), limits: limits)
        self.build = try container.decodeIfPresent(Build.self, forKey: .build) ?? Build.defaultBuild()
        self.server = try container.decodeIfPresent(Server.self, forKey: .server) ?? Server.defaultServer()
        self.blog = try container.decodeIfPresent(Blog.self, forKey: .blog) ?? Blog.defaultBlog()
        // Features only (Stage 2)
        self.features = try container.decodeIfPresent(Features.self, forKey: .features) ?? Features()
    }
    
    public static func parse(from yaml: String) throws -> HirundoConfig {
        do {
            return try YAMLDecoder().decode(HirundoConfig.self, from: yaml)
        } catch let error as ConfigError {
            throw error
        } catch let error as DecodingError {
            throw configError(for: error)
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }
    
    /// Renders a `DecodingError` as a message that names the key that went wrong.
    ///
    /// `DecodingError.localizedDescription` is a generic Foundation sentence — "The data
    /// couldn't be read because it is missing." — with no key path at all, which is useless for
    /// a file the user wrote by hand.
    private static func configError(for error: DecodingError) -> ConfigError {
        func path(_ codingPath: [CodingKey], _ missingKey: CodingKey? = nil) -> String {
            let keys = codingPath + (missingKey.map { [$0] } ?? [])
            return keys.isEmpty ? "(top level)" : keys.map { $0.stringValue }.joined(separator: ".")
        }
        
        /// The decoder names the YAML node type it wanted — "Mapping", "Scalar" — which means
        /// nothing to someone editing a configuration file.
        func describe(_ type: Any.Type) -> String {
            switch String(describing: type) {
            case "Mapping": return "a block of keys"
            case "Sequence": return "a list"
            case "Scalar": return "a single value"
            default: return "\(type)"
            }
        }
        
        switch error {
        case .keyNotFound(let key, let context):
            return .missingRequiredField(path(context.codingPath, key))
        case .typeMismatch(let type, let context):
            return .invalidValue("\(path(context.codingPath)): expected \(describe(type))")
        case .valueNotFound(let type, let context):
            return .invalidValue("\(path(context.codingPath)): expected \(describe(type)), found nothing")
        case .dataCorrupted(let context):
            // Yams re-wraps anything a model's `init(from:)` threw as `dataCorrupted` with an
            // empty coding path and "The given data was not valid YAML" — which is simply false
            // when the YAML parsed and a validation rule rejected a value. The real reason is
            // the only useful thing here.
            if let configError = context.underlyingError as? ConfigError {
                return configError
            }
            // Anything else — a duplicate key, a tab where spaces belong — comes back as the
            // same "The given data was not valid YAML." sentence. The YAML parser's own error
            // carries the line and column; `localizedDescription` would throw them away.
            if let underlying = context.underlyingError {
                let prefix = context.codingPath.isEmpty ? "" : "\(path(context.codingPath)): "
                // A duplicate-key error quotes the whole document back as its context, which
                // for a large configuration means a megabyte on stderr and in CI logs. The
                // useful part — which key, which line — comes first.
                var detail = String(describing: underlying)
                if detail.count > 500 {
                    detail = detail.prefix(500) + "… (truncated)"
                }
                return .parseError(prefix + detail)
            }
            return .parseError("\(path(context.codingPath)): \(context.debugDescription)")
        @unknown default:
            return .parseError(error.localizedDescription)
        }
    }
    
    /// Reads a configuration file, refusing one large enough to be a mistake.
    ///
    /// The cap is `Limits.maxConfigFileSize`, a constant rather than a `limits` key: a file's
    /// own size limit cannot be read out of that same file.
    static func readConfigFile(at url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigError.fileNotFound(url.path)
        }
        // Reading one byte past the cap, rather than asking for the file's size, is what makes
        // this hold: `attributesOfItem` reports the size of a symlink and not of its target, and
        // a file can grow between being measured and being read.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Limits.maxConfigFileSize + 1) ?? Data()
        guard data.count <= Limits.maxConfigFileSize else {
            throw ConfigError.invalidValue(
                "Configuration file is larger than \(Limits.maxConfigFileSize) bytes"
            )
        }
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw ConfigError.parseError("Configuration file is not valid UTF-8")
        }
        return yaml
    }
    
    public static func load(from url: URL) throws -> HirundoConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigError.fileNotFound(url.path)
        }
        
        do {
            return try parse(from: try readConfigFile(at: url))
        } catch let error as ConfigError {
            // `parse` already produced a configuration error with a usable message; wrapping it
            // again only prefixed the text a second time.
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

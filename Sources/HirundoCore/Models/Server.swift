import Foundation
import Yams

/// サーバー設定
public struct Server: Codable, Sendable {
    public let port: Int
    public let liveReload: Bool
    public let cors: CorsConfig?
    public let websocketAuth: WebSocketAuthConfig?
    
    public init(port: Int = 8080, liveReload: Bool = true, cors: CorsConfig? = nil, websocketAuth: WebSocketAuthConfig? = nil) throws {
        // ポート番号の検証（簡素化）
        self.port = try ConfigValidation.validatePort(port)
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
    
    /// デフォルトのサーバー設定を作成
    public static func defaultServer() -> Server {
        do {
            return try Server()
        } catch {
            return Server(port: 8080, liveReload: true, cors: nil, websocketAuth: nil, skipValidation: true)
        }
    }
    
    /// 内部イニシャライザ（検証スキップ）
    private init(port: Int, liveReload: Bool, cors: CorsConfig?, websocketAuth: WebSocketAuthConfig?, skipValidation: Bool) {
        self.port = port
        self.liveReload = liveReload
        self.cors = cors
        self.websocketAuth = websocketAuth
    }
}

/// WebSocket認証設定
public struct WebSocketAuthConfig: Codable, Sendable {
    public let enabled: Bool
    public let tokenExpirationMinutes: Int
    public let maxActiveTokens: Int
    
    public init(
        enabled: Bool = true,
        tokenExpirationMinutes: Int = 60,
        maxActiveTokens: Int = 100
    ) throws {
        // トークン有効期限の検証（簡素化）
        self.tokenExpirationMinutes = try ConfigValidation.validatePositiveInt(tokenExpirationMinutes, fieldName: "tokenExpirationMinutes")
        guard tokenExpirationMinutes <= 1440 else { // 24時間
            throw ConfigError.invalidValue("tokenExpirationMinutes cannot exceed 1440 minutes (24 hours)")
        }
        
        // 最大アクティブトークン数の検証（簡素化）
        self.maxActiveTokens = try ConfigValidation.validatePositiveInt(maxActiveTokens, fieldName: "maxActiveTokens")
        guard maxActiveTokens <= 10000 else {
            throw ConfigError.invalidValue("maxActiveTokens cannot exceed 10000")
        }
        
        self.enabled = enabled
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
    
    /// デフォルトのWebSocket認証設定を作成
    public static func defaultWebSocketAuth() -> WebSocketAuthConfig {
        do {
            return try WebSocketAuthConfig()
        } catch {
            return WebSocketAuthConfig(enabled: true, tokenExpirationMinutes: 60, maxActiveTokens: 100, skipValidation: true)
        }
    }
    
    /// 内部イニシャライザ（検証スキップ）
    private init(enabled: Bool, tokenExpirationMinutes: Int, maxActiveTokens: Int, skipValidation: Bool) {
        self.enabled = enabled
        self.tokenExpirationMinutes = tokenExpirationMinutes
        self.maxActiveTokens = maxActiveTokens
    }
}

/// CORS設定
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

/// サーバー設定のパーサー
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
import Foundation
import Yams

/// サーバー設定
public struct Server: Codable, Sendable {
    public let port: Int
    public let liveReload: Bool
    
    public init(port: Int = 8080, liveReload: Bool = true) {
        self.port = port
        self.liveReload = liveReload
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 8080
        let liveReload = try container.decodeIfPresent(Bool.self, forKey: .liveReload) ?? true
        
        self.init(port: port, liveReload: liveReload)
    }
    
    enum CodingKeys: String, CodingKey {
        case port, liveReload
    }
    
    /// デフォルトのサーバー設定を作成
    public static func defaultServer() -> Server {
        return Server()
    }
}
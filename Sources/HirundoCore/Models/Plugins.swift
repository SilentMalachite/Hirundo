import Foundation
import Yams

/// プラグイン設定
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
            throw EncodingError.invalidValue(name, EncodingError.Context(
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

/// プラグイン設定のパーサー
public struct PluginsConfig {
    public let plugins: [PluginConfiguration]
    
    public static func parse(from yaml: String) throws -> PluginsConfig {
        do {
            let decoder = YAMLDecoder()
            let data = try decoder.decode([String: [PluginConfiguration]].self, from: yaml)
            
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
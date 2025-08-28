import Foundation

/// プラグインマニフェスト
public struct PluginManifest: Codable {
    public let name: String
    public let version: String
    public let description: String
    public let author: String?
    public let dependencies: [String]?
    public let entryPoint: String?
}

/// プラグインリソース制限
public struct PluginResourceLimits {
    public var memoryLimit: Int = 100_000_000 // 100MB デフォルト
    public var cpuTimeLimit: Double = 10.0 // 10秒 デフォルト
    public var fileOperationLimit: Int = 1000 // 1000ファイル操作 デフォルト
    
    public init() {}
}

/// プラグインセキュリティコンテキスト
public struct PluginSecurityContext {
    public var allowedDirectories: [String] = []
    public var sandboxingEnabled: Bool = false
    public var allowNetworkAccess: Bool = true
    public var allowProcessExecution: Bool = true
    public var maxExecutionTime: TimeInterval = 30.0 // プラグイン実行あたり30秒最大
    public var maxMemoryUsage: Int64 = 512 * 1024 * 1024 // 512MB最大メモリ増加
    
    public init() {}
}
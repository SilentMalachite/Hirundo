import Foundation

// Plugin priority levels
public enum PluginPriority: Int, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    
    public static func < (lhs: PluginPriority, rhs: PluginPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// Plugin metadata
public struct PluginMetadata {
    public let name: String
    public let version: String
    public let author: String
    public let description: String
    public let dependencies: [String]
    public let priority: PluginPriority
    
    public init(
        name: String,
        version: String,
        author: String,
        description: String,
        dependencies: [String] = [],
        priority: PluginPriority = .normal
    ) {
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.dependencies = dependencies
        self.priority = priority
    }
}

// Plugin context passed to plugins
public struct PluginContext {
    public let projectPath: String
    public let config: HirundoConfig
    public var data: [String: Any]
    
    public init(projectPath: String, config: HirundoConfig, data: [String: Any] = [:]) {
        self.projectPath = projectPath
        self.config = config
        self.data = data
    }
}

// Build context for build hooks
public struct BuildContext {
    public let outputPath: String
    public let isDraft: Bool
    public let isClean: Bool
    public let pages: [ContentItem]
    public let config: HirundoConfig
    
    public init(outputPath: String, isDraft: Bool, isClean: Bool, pages: [ContentItem] = [], config: HirundoConfig) {
        self.outputPath = outputPath
        self.isDraft = isDraft
        self.isClean = isClean
        self.pages = pages
        self.config = config
    }
}

// Content item for transformation
public struct ContentItem {
    public var path: String
    public var frontMatter: [String: Any]
    public var content: String
    public let type: ContentType
    
    public enum ContentType: Equatable {
        case markdown
        case html
        case other(String)
    }
    
    public init(path: String, frontMatter: [String: Any], content: String, type: ContentType) {
        self.path = path
        self.frontMatter = frontMatter
        self.content = content
        self.type = type
    }
}

// Asset item for processing
public struct AssetItem {
    public let sourcePath: String
    public let outputPath: String
    public let type: AssetType
    public var processed: Bool = false
    public var metadata: [String: Any] = [:]
    
    public enum AssetType: Equatable {
        case css
        case javascript
        case image(String) // extension
        case other(String)
    }
    
    public init(sourcePath: String, outputPath: String, type: AssetType) {
        self.sourcePath = sourcePath
        self.outputPath = outputPath
        self.type = type
    }
}

// Plugin configuration
public struct PluginConfig {
    public let name: String
    public let enabled: Bool
    public let settings: [String: Any]
    
    public init(name: String, enabled: Bool = true, settings: [String: Any] = [:]) {
        self.name = name
        self.enabled = enabled
        self.settings = settings
    }
}

// Main plugin protocol
public protocol Plugin: AnyObject {
    var metadata: PluginMetadata { get }
    
    // Lifecycle
    func initialize(context: PluginContext) throws
    func cleanup() throws
    
    // Optional hooks
    func configure(with config: PluginConfig) throws
    func beforeBuild(context: BuildContext) throws
    func afterBuild(context: BuildContext) throws
    func beforeContentTransform(_ content: ContentItem) throws -> ContentItem
    func transformContent(_ content: ContentItem) throws -> ContentItem
    func afterContentTransform(_ content: ContentItem) throws -> ContentItem
    func enrichTemplateData(_ data: [String: Any]) throws -> [String: Any]
    func processAsset(_ asset: AssetItem) throws -> AssetItem
    func beforeServe(port: Int, host: String) throws
    func afterServe() throws
}

// Default implementations for optional methods
public extension Plugin {
    func configure(with config: PluginConfig) throws {}
    func beforeBuild(context: BuildContext) throws {}
    func afterBuild(context: BuildContext) throws {}
    func beforeContentTransform(_ content: ContentItem) throws -> ContentItem { return content }
    func transformContent(_ content: ContentItem) throws -> ContentItem { return content }
    func afterContentTransform(_ content: ContentItem) throws -> ContentItem { return content }
    func enrichTemplateData(_ data: [String: Any]) throws -> [String: Any] { return data }
    func processAsset(_ asset: AssetItem) throws -> AssetItem { return asset }
    func beforeServe(port: Int, host: String) throws {}
    func afterServe() throws {}
}

// Plugin errors
public enum PluginError: LocalizedError {
    case pluginNotFound(String)
    case duplicatePlugin(String)
    case initializationFailed(String, String)
    case configurationFailed(String, String)
    case dependencyNotFound(String, String)
    case circularDependency([String])
    case hookFailed(String, String)
    case invalidPlugin(String)
    
    public var errorDescription: String? {
        switch self {
        case .pluginNotFound(let name):
            return "Plugin not found: \(name)"
        case .duplicatePlugin(let name):
            return "Plugin already registered: \(name)"
        case .initializationFailed(let name, let reason):
            return "Plugin initialization failed for \(name): \(reason)"
        case .configurationFailed(let name, let reason):
            return "Plugin configuration failed for \(name): \(reason)"
        case .dependencyNotFound(let plugin, let dependency):
            return "Plugin \(plugin) requires \(dependency) which is not found"
        case .circularDependency(let plugins):
            return "Circular dependency detected: \(plugins.joined(separator: " -> "))"
        case .hookFailed(let hook, let reason):
            return "Plugin hook \(hook) failed: \(reason)"
        case .invalidPlugin(let reason):
            return "Invalid plugin: \(reason)"
        }
    }
}

// Plugin security errors
public enum PluginSecurityError: LocalizedError {
    case unauthorizedFileAccess(String)
    case unauthorizedSystemModification(String)
    case sandboxViolation(String)
    case networkAccessDenied
    case processExecutionDenied
    
    public var errorDescription: String? {
        switch self {
        case .unauthorizedFileAccess(let path):
            return "Plugin attempted unauthorized file access: \(path)"
        case .unauthorizedSystemModification(let path):
            return "Plugin attempted to modify system file: \(path)"
        case .sandboxViolation(let reason):
            return "Plugin sandbox violation: \(reason)"
        case .networkAccessDenied:
            return "Plugin network access denied in sandbox mode"
        case .processExecutionDenied:
            return "Plugin process execution denied in sandbox mode"
        }
    }
}

// Plugin resource limit errors
public enum PluginResourceLimitError: LocalizedError {
    case memoryLimitExceeded(Int, Int)
    case cpuTimeLimitExceeded(Double)
    case fileLimitExceeded(Int)
    
    public var resourceType: ResourceType {
        switch self {
        case .memoryLimitExceeded:
            return .memory
        case .cpuTimeLimitExceeded:
            return .cpuTime
        case .fileLimitExceeded:
            return .fileCount
        }
    }
    
    public var errorDescription: String? {
        switch self {
        case .memoryLimitExceeded(let used, let limit):
            return "Plugin exceeded memory limit: \(used) bytes (limit: \(limit))"
        case .cpuTimeLimitExceeded(let limit):
            return "Plugin exceeded CPU time limit: \(limit) seconds"
        case .fileLimitExceeded(let limit):
            return "Plugin exceeded file operation limit: \(limit)"
        }
    }
}

// Resource types for limits
public enum ResourceType {
    case memory
    case cpuTime
    case fileCount
}
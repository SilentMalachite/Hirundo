import Foundation

// Secure file manager for plugin sandboxing
class SecureFileManager {
    private let allowedDirectories: [String]
    private let projectPath: String
    
    init(allowedDirectories: [String], projectPath: String) {
        self.allowedDirectories = allowedDirectories
        self.projectPath = projectPath
    }
    
    func checkFileAccess(_ path: String) throws {
        let normalizedPath = URL(fileURLWithPath: path).standardized.path
        
        // Always allow access within project directory
        if normalizedPath.hasPrefix(projectPath) {
            return
        }
        
        // Check if path is in allowed directories
        let isAllowed = allowedDirectories.contains { allowedDir in
            normalizedPath.hasPrefix(allowedDir)
        }
        
        if !isAllowed {
            throw PluginSecurityError.unauthorizedFileAccess(path)
        }
    }
}

// Plugin manifest structure for external plugins
struct PluginManifest: Codable {
    let name: String
    let version: String
    let description: String
    let author: String?
    let dependencies: [String]?
    let entryPoint: String?
}

// Plugin resource limits
public struct PluginResourceLimits {
    public var memoryLimit: Int = 100_000_000 // 100MB default
    public var cpuTimeLimit: Double = 10.0 // 10 seconds default
    public var fileOperationLimit: Int = 1000 // 1000 file operations default
    
    public init() {}
}

// Plugin security context
public struct PluginSecurityContext {
    public var allowedDirectories: [String] = []
    public var sandboxingEnabled: Bool = false
    public var allowNetworkAccess: Bool = true
    public var allowProcessExecution: Bool = true
    
    public init() {}
}

// Plugin execution monitor
class PluginExecutionMonitor {
    private var startTime: Date?
    private var memoryBaseline: Int = 0
    private var fileOperationCount: Int = 0
    
    func startMonitoring() {
        startTime = Date()
        memoryBaseline = getCurrentMemoryUsage()
        fileOperationCount = 0
    }
    
    func checkResourceLimits(_ limits: PluginResourceLimits) throws {
        // Check CPU time
        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > limits.cpuTimeLimit {
                throw PluginResourceLimitError.cpuTimeLimitExceeded(limits.cpuTimeLimit)
            }
        }
        
        // Check memory usage
        let currentMemory = getCurrentMemoryUsage()
        let memoryUsed = currentMemory - memoryBaseline
        if memoryUsed > limits.memoryLimit {
            throw PluginResourceLimitError.memoryLimitExceeded(memoryUsed, limits.memoryLimit)
        }
        
        // Check file operations
        if fileOperationCount > limits.fileOperationLimit {
            throw PluginResourceLimitError.fileLimitExceeded(limits.fileOperationLimit)
        }
    }
    
    func incrementFileOperations() {
        fileOperationCount += 1
    }
    
    private func getCurrentMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size) : 0
    }
}

// Plugin manager handles registration and execution of plugins
public class PluginManager {
    private var plugins: [String: Plugin] = [:]
    private var pluginOrder: [String] = []
    private var initialized = false
    private var context: PluginContext?
    private var resourceLimits = PluginResourceLimits()
    private var securityContext = PluginSecurityContext()
    private var executionMonitor = PluginExecutionMonitor()
    
    public init() {}
    
    // Get registered plugins
    public var registeredPlugins: [Plugin] {
        return pluginOrder.compactMap { plugins[$0] }
    }
    
    // Register a plugin
    public func register(_ plugin: Plugin) throws {
        let name = plugin.metadata.name
        
        if plugins[name] != nil {
            throw PluginError.duplicatePlugin(name)
        }
        
        plugins[name] = plugin
        
        // Rebuild plugin order based on dependencies and priority
        try rebuildPluginOrder()
    }
    
    // Configure a plugin
    public func configure(pluginNamed name: String, with config: PluginConfig) throws {
        guard let plugin = plugins[name] else {
            throw PluginError.pluginNotFound(name)
        }
        
        do {
            try plugin.configure(with: config)
        } catch {
            throw PluginError.configurationFailed(name, error.localizedDescription)
        }
    }
    
    // Initialize all plugins
    public func initializeAll(context: PluginContext) throws {
        self.context = context
        
        for name in pluginOrder {
            guard let plugin = plugins[name] else { continue }
            
            do {
                try plugin.initialize(context: context)
            } catch {
                throw PluginError.initializationFailed(name, error.localizedDescription)
            }
        }
        
        initialized = true
    }
    
    // Cleanup all plugins
    public func cleanupAll() throws {
        // Cleanup in reverse order
        for name in pluginOrder.reversed() {
            guard let plugin = plugins[name] else { continue }
            try plugin.cleanup()
        }
        
        initialized = false
    }
    
    // Execute before build hook
    public func executeBeforeBuild(buildContext: BuildContext) throws {
        guard initialized else { return }
        
        for name in pluginOrder {
            guard let plugin = plugins[name] else { continue }
            
            do {
                try plugin.beforeBuild(context: buildContext)
            } catch {
                throw PluginError.hookFailed("beforeBuild", error.localizedDescription)
            }
        }
    }
    
    // Execute after build hook
    public func executeAfterBuild(buildContext: BuildContext) throws {
        guard initialized else { return }
        
        for name in pluginOrder {
            guard let plugin = plugins[name] else { continue }
            
            executionMonitor.startMonitoring()
            
            do {
                try executeWithSecurity {
                    try plugin.afterBuild(context: buildContext)
                }
                
                // Check resource limits
                try executionMonitor.checkResourceLimits(resourceLimits)
                
            } catch let error as PluginResourceLimitError {
                throw error
            } catch let error as PluginSecurityError {
                throw error
            } catch {
                throw PluginError.hookFailed("afterBuild", error.localizedDescription)
            }
        }
    }
    
    // Set resource limits
    public func setResourceLimit(_ type: ResourceType, value: Any) {
        switch type {
        case .memory:
            if let limit = value as? Int {
                resourceLimits.memoryLimit = limit
            }
        case .cpuTime:
            if let limit = value as? Double {
                resourceLimits.cpuTimeLimit = limit
            }
        case .fileCount:
            if let limit = value as? Int {
                resourceLimits.fileOperationLimit = limit
            }
        }
    }
    
    // Set allowed directories for file access
    public func setAllowedDirectories(_ directories: [String]) {
        securityContext.allowedDirectories = directories
    }
    
    // Enable sandboxing
    public func enableSandboxing() {
        securityContext.sandboxingEnabled = true
        securityContext.allowNetworkAccess = false
        securityContext.allowProcessExecution = false
    }
    
    // Transform content through all plugins
    public func transformContent(_ content: ContentItem) throws -> ContentItem {
        guard initialized else { return content }
        
        var transformed = content
        
        // Sort plugins by priority for content transformation
        let sortedPlugins = pluginOrder
            .compactMap { plugins[$0] }
            .sorted { $0.metadata.priority > $1.metadata.priority }
        
        for plugin in sortedPlugins {
            executionMonitor.startMonitoring()
            
            do {
                // Before transform
                transformed = try executeWithSecurity {
                    try plugin.beforeContentTransform(transformed)
                }
                
                // Check resource limits
                try executionMonitor.checkResourceLimits(resourceLimits)
                
                // Main transform
                transformed = try executeWithSecurity {
                    try plugin.transformContent(transformed)
                }
                
                // Check resource limits again
                try executionMonitor.checkResourceLimits(resourceLimits)
                
                // After transform
                transformed = try executeWithSecurity {
                    try plugin.afterContentTransform(transformed)
                }
                
                // Final resource check
                try executionMonitor.checkResourceLimits(resourceLimits)
                
            } catch let error as PluginResourceLimitError {
                throw error
            } catch let error as PluginSecurityError {
                throw error
            } catch {
                throw PluginError.hookFailed("transformContent", error.localizedDescription)
            }
        }
        
        return transformed
    }
    
    // Enrich template data through all plugins
    public func enrichTemplateData(_ data: [String: Any]) throws -> [String: Any] {
        guard initialized else { return data }
        
        var enriched = data
        
        for name in pluginOrder {
            guard let plugin = plugins[name] else { continue }
            enriched = try plugin.enrichTemplateData(enriched)
        }
        
        return enriched
    }
    
    // Process asset through all plugins
    public func processAsset(_ asset: AssetItem) throws -> AssetItem {
        guard initialized else { return asset }
        
        var processed = asset
        
        for name in pluginOrder {
            guard let plugin = plugins[name] else { continue }
            processed = try plugin.processAsset(processed)
        }
        
        return processed
    }
    
    // Execute before serve hook
    public func executeBeforeServe(port: Int, host: String) throws {
        guard initialized else { return }
        
        for name in pluginOrder {
            guard let plugin = plugins[name] else { continue }
            
            do {
                try plugin.beforeServe(port: port, host: host)
            } catch {
                throw PluginError.hookFailed("beforeServe", error.localizedDescription)
            }
        }
    }
    
    // Execute after serve hook
    public func executeAfterServe() throws {
        guard initialized else { return }
        
        for name in pluginOrder.reversed() {
            guard let plugin = plugins[name] else { continue }
            
            do {
                try plugin.afterServe()
            } catch {
                throw PluginError.hookFailed("afterServe", error.localizedDescription)
            }
        }
    }
    
    // Load plugins from directory
    public func loadPlugins(from directory: String) throws {
        let fileManager = FileManager.default
        let pluginDir = URL(fileURLWithPath: directory)
        
        guard fileManager.fileExists(atPath: directory) else {
            return // No plugins directory is okay
        }
        
        let contents = try fileManager.contentsOfDirectory(
            at: pluginDir,
            includingPropertiesForKeys: nil
        )
        
        for url in contents {
            if url.pathExtension == "swift" {
                // Swift source plugins would require compilation
                print("📝 Found Swift plugin source: \(url.lastPathComponent)")
                print("   Note: Swift plugin compilation not yet supported")
            } else if url.pathExtension == "plugin" {
                // Load pre-compiled plugin bundles
                try loadPluginBundle(at: url)
            } else if url.pathExtension == "dylib" {
                // Load dynamic library plugins
                try loadDynamicPlugin(at: url)
            }
        }
    }
    
    // Load a plugin bundle
    private func loadPluginBundle(at url: URL) throws {
        print("📦 Loading plugin bundle: \(url.lastPathComponent)")
        
        // Read plugin manifest
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PluginError.invalidPlugin("Missing manifest.json in \(url.lastPathComponent)")
        }
        
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: manifestData)
        
        // For now, just register the metadata without loading the actual plugin
        print("   Name: \(manifest.name)")
        print("   Version: \(manifest.version)")
        print("   Description: \(manifest.description)")
    }
    
    // Load a dynamic library plugin
    private func loadDynamicPlugin(at url: URL) throws {
        print("🔧 Found dynamic plugin: \(url.lastPathComponent)")
        
        // Validate plugin path and signature
        try validatePluginSecurity(at: url)
        
        // TODO: Implement secure dynamic loading
        // This would require proper code signing validation and sandbox restrictions
        throw PluginError.invalidPlugin("Dynamic plugin loading not implemented for security reasons")
    }
    
    // Validate plugin security before loading
    private func validatePluginSecurity(at url: URL) throws {
        // Check if file is in allowed plugin directory
        let allowedPaths = [
            "/usr/local/lib/hirundo/plugins",
            NSHomeDirectory() + "/.hirundo/plugins"
        ]
        
        let pluginPath = url.path
        let isInAllowedPath = allowedPaths.contains { allowedPath in
            pluginPath.hasPrefix(allowedPath)
        }
        
        guard isInAllowedPath else {
            throw PluginError.invalidPlugin("Plugin not in allowed directory")
        }
        
        // Additional security checks could include:
        // - Code signature verification
        // - Capability restrictions
        // - Sandboxing
    }
    
    // Execute with security context
    private func executeWithSecurity<T>(_ block: () throws -> T) throws -> T {
        // Intercept file operations
        let originalFileManager = FileManager.default
        let secureFileManager = SecureFileManager(
            allowedDirectories: securityContext.allowedDirectories,
            projectPath: context?.projectPath ?? ""
        )
        
        // Temporarily replace file manager if needed
        // Note: In Swift, we can't actually replace FileManager.default,
        // so we need to catch errors at the plugin level
        
        do {
            // In a real implementation, we would use method swizzling or
            // a custom file access API that plugins must use
            return try block()
        } catch {
            // Check if it's a file access error
            if let nsError = error as NSError?,
               nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSFileReadNoPermissionError ||
               nsError.code == NSFileWriteNoPermissionError {
                throw PluginSecurityError.unauthorizedFileAccess(nsError.userInfo[NSFilePathErrorKey] as? String ?? "unknown")
            }
            throw error
        }
    }
    
    // Rebuild plugin order based on dependencies
    private func rebuildPluginOrder() throws {
        var order: [String] = []
        var visited: Set<String> = []
        var visiting: Set<String> = []
        
        func visit(_ name: String, path: [String] = []) throws {
            if visiting.contains(name) {
                throw PluginError.circularDependency(path + [name])
            }
            
            if visited.contains(name) {
                return
            }
            
            visiting.insert(name)
            
            guard let plugin = plugins[name] else {
                throw PluginError.pluginNotFound(name)
            }
            
            // Visit dependencies first
            for dep in plugin.metadata.dependencies {
                if plugins[dep] == nil {
                    throw PluginError.dependencyNotFound(name, dep)
                }
                try visit(dep, path: path + [name])
            }
            
            visiting.remove(name)
            visited.insert(name)
            order.append(name)
        }
        
        // Visit all plugins
        for name in plugins.keys {
            try visit(name)
        }
        
        pluginOrder = order
    }
}

// Plugin loader for built-in plugins
public class PluginLoader {
    private static var builtInPlugins: [String: () -> Plugin] = {
        var plugins: [String: () -> Plugin] = [:]
        // Register built-in plugins here
        plugins["sitemap"] = { SitemapPlugin() }
        plugins["rss"] = { RSSPlugin() }
        plugins["minify"] = { MinifyPlugin() }
        plugins["search"] = { SearchIndexPlugin() }
        return plugins
    }()
    
    // Register a built-in plugin type
    public static func registerBuiltIn(name: String, factory: @escaping () -> Plugin) {
        builtInPlugins[name] = factory
    }
    
    // Load a built-in plugin
    public static func loadBuiltIn(named name: String) -> Plugin? {
        return builtInPlugins[name]?()
    }
    
    // Get available built-in plugins
    public static var availableBuiltIns: [String] {
        return Array(builtInPlugins.keys).sorted()
    }
    
    // Load all enabled built-in plugins into manager
    public static func loadEnabledBuiltIns(into manager: PluginManager, config: HirundoConfig) throws {
        // Load plugins based on configuration
        let enabledPlugins = config.plugins.compactMap { pluginConfig in
            pluginConfig.enabled ? pluginConfig.name : nil
        }
        
        for pluginName in enabledPlugins {
            if let plugin = loadBuiltIn(named: pluginName) {
                try manager.register(plugin)
                
                // Configure if settings exist
                if let pluginConfig = config.plugins.first(where: { $0.name == pluginName }) {
                    let config = PluginConfig(
                        name: pluginName,
                        enabled: true,
                        settings: pluginConfig.settings
                    )
                    try manager.configure(pluginNamed: pluginName, with: config)
                }
            }
        }
    }
}
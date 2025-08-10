import XCTest
@testable import HirundoCore

// MARK: - Test Helpers

extension XCTestCase {
    func XCTAssertThrows<T>(_ expression: @autoclosure () throws -> T, 
                           _ errorHandler: (Error) -> Void,
                           file: StaticString = #file,
                           line: UInt = #line) {
        do {
            _ = try expression()
            XCTFail("Expected error to be thrown", file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}

final class PluginSystemTests: XCTestCase {
    
    var pluginManager: PluginManager!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("plugin-test-\(UUID())")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        pluginManager = PluginManager()
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testPluginRegistration() throws {
        let plugin = TestPlugin()
        
        try pluginManager.register(plugin)
        
        XCTAssertEqual(pluginManager.registeredPlugins.count, 1)
        XCTAssertEqual(pluginManager.registeredPlugins.first?.metadata.name, "TestPlugin")
    }
    
    func testDuplicatePluginRegistration() throws {
        let plugin1 = TestPlugin()
        let plugin2 = TestPlugin()
        
        try pluginManager.register(plugin1)
        
        XCTAssertThrows(try pluginManager.register(plugin2)) { (error: PluginError) in
            switch error {
            case .duplicatePlugin(let name):
                XCTAssertEqual(name, "TestPlugin")
            default:
                XCTFail("Expected duplicatePlugin error")
            }
        }
    }
    
    func testPluginLifecycle() throws {
        let plugin = LifecycleTestPlugin()
        
        try pluginManager.register(plugin)
        
        let context = PluginContext(
            projectPath: tempDir.path,
            config: HirundoConfig(
                site: try Site(
                    title: "Test Site",
                    url: "https://example.com"
                )
            ),
            data: [:]
        )
        
        // Initialize
        try pluginManager.initializeAll(context: context)
        XCTAssertTrue(plugin.initialized)
        
        // Cleanup
        try pluginManager.cleanupAll()
        XCTAssertTrue(plugin.cleanedUp)
    }
    
    func testBeforeBuildHook() throws {
        let hookPlugin = HookTestPlugin()
        try pluginManager.register(hookPlugin)
        
        let context = try createTestContext()
        let buildContext = BuildContext(
            outputPath: tempDir.appendingPathComponent("_site").path,
            isDraft: false,
            isClean: true,
            config: HirundoConfig(
                site: try Site(
                    title: "Test Site",
                    url: "https://example.com"
                )
            )
        )
        
        try pluginManager.initializeAll(context: context)
        try pluginManager.executeBeforeBuild(buildContext: buildContext)
        
        XCTAssertTrue(hookPlugin.beforeBuildCalled)
        XCTAssertEqual(hookPlugin.lastBuildContext?.outputPath, buildContext.outputPath)
    }
    
    func testAfterBuildHook() throws {
        let hookPlugin = HookTestPlugin()
        try pluginManager.register(hookPlugin)
        
        let context = try createTestContext()
        let buildContext = BuildContext(
            outputPath: tempDir.appendingPathComponent("_site").path,
            isDraft: false,
            isClean: false,
            config: HirundoConfig(
                site: try Site(
                    title: "Test Site",
                    url: "https://example.com"
                )
            )
        )
        
        try pluginManager.initializeAll(context: context)
        try pluginManager.executeAfterBuild(buildContext: buildContext)
        
        XCTAssertTrue(hookPlugin.afterBuildCalled)
    }
    
    func testContentTransformation() throws {
        let transformPlugin = ContentTransformPlugin()
        try pluginManager.register(transformPlugin)
        
        let context = try createTestContext()
        try pluginManager.initializeAll(context: context)
        
        let originalContent = ContentItem(
            path: "test.md",
            frontMatter: ["title": "Test"],
            content: "Hello World",
            type: .page
        )
        
        let transformed = try pluginManager.transformContent(originalContent)
        
        XCTAssertEqual(transformed.content, "HELLO WORLD")
        XCTAssertEqual(transformed.frontMatter["transformed"] as? Bool, true)
    }
    
    func testTemplateDataInjection() throws {
        let dataPlugin = DataInjectionPlugin()
        try pluginManager.register(dataPlugin)
        
        let context = try createTestContext()
        try pluginManager.initializeAll(context: context)
        
        var templateData: [String: Any] = [
            "page": ["title": "Test Page"]
        ]
        
        let enrichedData = try pluginManager.enrichTemplateData(templateData)
        
        XCTAssertEqual(enrichedData["plugin_version"] as? String, "1.0.0")
        XCTAssertNotNil(enrichedData["build_time"] as? Date)
    }
    
    func testAssetProcessing() throws {
        let assetPlugin = AssetProcessingPlugin()
        try pluginManager.register(assetPlugin)
        
        let context = try createTestContext()
        try pluginManager.initializeAll(context: context)
        
        // Create test CSS file
        let cssFile = tempDir.appendingPathComponent("style.css")
        let cssContent = """
        body {
            margin: 0;
            padding: 0;
        }
        """
        try cssContent.write(to: cssFile, atomically: true, encoding: .utf8)
        
        let asset = AssetItem(
            sourcePath: cssFile.path,
            outputPath: tempDir.appendingPathComponent("_site/style.css").path,
            type: .css
        )
        
        let processed = try pluginManager.processAsset(asset)
        
        XCTAssertTrue(processed.processed)
        XCTAssertNotNil(processed.metadata["minified"])
    }
    
    func testPluginConfiguration() throws {
        let configurablePlugin = ConfigurablePlugin()
        try pluginManager.register(configurablePlugin)
        
        let config = PluginConfig(
            name: "ConfigurablePlugin",
            enabled: true,
            settings: [
                "apiKey": "test-key",
                "endpoint": "https://api.example.com"
            ]
        )
        
        try pluginManager.configure(pluginNamed: "ConfigurablePlugin", with: config)
        
        XCTAssertEqual(configurablePlugin.apiKey, "test-key")
        XCTAssertEqual(configurablePlugin.endpoint, "https://api.example.com")
    }
    
    func testPluginErrorHandling() throws {
        let errorPlugin = ErrorThrowingPlugin()
        try pluginManager.register(errorPlugin)
        
        let context = try createTestContext()
        
        XCTAssertThrows(try pluginManager.initializeAll(context: context)) { (error: PluginError) in
            switch error {
            case .initializationFailed(let name, _):
                XCTAssertEqual(name, "ErrorThrowingPlugin")
            default:
                XCTFail("Expected initializationFailed error")
            }
        }
    }
    
    func testPluginDependencies() throws {
        let dependentPlugin = DependentPlugin()
        let dependencyPlugin = DependencyPlugin()
        
        // Register dependency first, then dependent
        try pluginManager.register(dependencyPlugin)
        try pluginManager.register(dependentPlugin)
        
        let context = try createTestContext()
        
        // Should initialize in correct order based on dependencies
        try pluginManager.initializeAll(context: context)
        
        XCTAssertTrue(dependencyPlugin.initialized)
        XCTAssertTrue(dependentPlugin.initialized)
        XCTAssertLessThan(dependencyPlugin.initTime!, dependentPlugin.initTime!)
    }
    
    func testPluginDependencyMissing() throws {
        let dependentPlugin = DependentPlugin()
        
        // Register only the dependent plugin without its dependency
        XCTAssertThrows(try pluginManager.register(dependentPlugin)) { error in
            guard let pluginError = error as? PluginError else {
                XCTFail("Expected PluginError")
                return
            }
            switch pluginError {
            case .dependencyNotFound(let plugin, let dependency):
                XCTAssertEqual(plugin, "DependentPlugin")
                XCTAssertEqual(dependency, "DependencyPlugin")
            default:
                XCTFail("Expected dependencyNotFound error")
            }
        }
    }
    
    func testPluginPriority() throws {
        let highPriorityPlugin = PriorityPlugin(priority: .high)
        let lowPriorityPlugin = PriorityPlugin(priority: .low)
        let normalPriorityPlugin = PriorityPlugin(priority: .normal)
        
        // Register in random order
        try pluginManager.register(lowPriorityPlugin)
        try pluginManager.register(highPriorityPlugin)
        try pluginManager.register(normalPriorityPlugin)
        
        let content = ContentItem(
            path: "test.md",
            frontMatter: [:],
            content: "test",
            type: .page
        )
        
        let context = try createTestContext()
        try pluginManager.initializeAll(context: context)
        
        let transformed = try pluginManager.transformContent(content)
        
        // Should be processed in priority order: high -> normal -> low
        XCTAssertEqual(transformed.content, "test-high-normal-low")
    }
    
    // MARK: - Security Tests
    
    func testMaliciousFileSystemAccess() throws {
        let maliciousPlugin = MaliciousFileSystemPlugin()
        try pluginManager.register(maliciousPlugin)
        
        let context = try createTestContext()
        try pluginManager.initializeAll(context: context)
        
        let content = ContentItem(
            path: "test.md",
            frontMatter: [:],
            content: "test",
            type: .page
        )
        
        // Plugin should not be able to access files outside project directory
        XCTAssertThrows(try pluginManager.transformContent(content)) { error in
            XCTAssertTrue(error is PluginSecurityError)
        }
    }
    
    func testExcessiveResourceConsumption() throws {
        let resourceHogPlugin = ResourceHogPlugin()
        try pluginManager.register(resourceHogPlugin)
        
        let context = try createTestContext()
        try pluginManager.initializeAll(context: context)
        
        let content = ContentItem(
            path: "test.md",
            frontMatter: [:],
            content: "test",
            type: .page
        )
        
        // Plugin should be stopped if it consumes too much memory/CPU
        XCTAssertThrows(try pluginManager.transformContent(content)) { error in
            XCTAssertTrue(error is PluginResourceLimitError)
        }
    }
    
    func testSystemFileModificationAttempt() throws {
        let systemModifierPlugin = SystemFileModifierPlugin()
        try pluginManager.register(systemModifierPlugin)
        
        let context = try createTestContext()
        try pluginManager.initializeAll(context: context)
        
        // Plugin should not be able to modify system files
        XCTAssertThrows(try pluginManager.executeAfterBuild(buildContext: BuildContext(
            outputPath: tempDir.path,
            isDraft: false,
            isClean: false,
            config: context.config
        ))) { error in
            XCTAssertTrue(error is PluginSecurityError)
        }
    }
    
    func testPluginIsolation() throws {
        let plugin1 = GlobalStatePlugin(id: "plugin1")
        let plugin2 = GlobalStatePlugin(id: "plugin2")
        
        try pluginManager.register(plugin1)
        try pluginManager.register(plugin2)
        
        let context = try createTestContext()
        try pluginManager.initializeAll(context: context)
        
        // Plugin 1 sets global state
        plugin1.setGlobalState("key", value: "value1")
        
        // Plugin 2 should not see Plugin 1's state
        XCTAssertNil(plugin2.getGlobalState("key"))
        
        // Each plugin should have isolated state
        XCTAssertEqual(plugin1.getGlobalState("key"), "value1")
    }
    
    func testMemoryLimitEnforcement() throws {
        let memoryIntensivePlugin = MemoryIntensivePlugin()
        try pluginManager.register(memoryIntensivePlugin)
        
        let context = try createTestContext()
        try pluginManager.initializeAll(context: context)
        
        // Set memory limit (e.g., 100MB)
        pluginManager.setResourceLimit(.memory, value: 100_000_000)
        
        let content = ContentItem(
            path: "test.md",
            frontMatter: [:],
            content: "test",
            type: .page
        )
        
        // Should throw when memory limit is exceeded
        XCTAssertThrows(try pluginManager.transformContent(content)) { error in
            guard let resourceError = error as? PluginResourceLimitError else {
                XCTFail("Expected PluginResourceLimitError")
                return
            }
            XCTAssertEqual(resourceError.resourceType, .memory)
        }
    }
    
    func testCPUTimeLimit() throws {
        let cpuIntensivePlugin = CPUIntensivePlugin()
        try pluginManager.register(cpuIntensivePlugin)
        
        let context = try createTestContext()
        try pluginManager.initializeAll(context: context)
        
        // Set CPU time limit (e.g., 5 seconds)
        pluginManager.setResourceLimit(.cpuTime, value: 5.0)
        
        let content = ContentItem(
            path: "test.md",
            frontMatter: [:],
            content: "test",
            type: .page
        )
        
        // Should timeout when CPU time limit is exceeded
        XCTAssertThrows(try pluginManager.transformContent(content)) { error in
            guard let resourceError = error as? PluginResourceLimitError else {
                XCTFail("Expected PluginResourceLimitError")
                return
            }
            XCTAssertEqual(resourceError.resourceType, .cpuTime)
        }
    }
    
    func testFileAccessRestriction() throws {
        let fileAccessPlugin = FileAccessPlugin()
        try pluginManager.register(fileAccessPlugin)
        
        let context = try createTestContext()
        
        // Set allowed directories
        pluginManager.setAllowedDirectories([tempDir.path])
        
        // Pass security context to plugin
        var securityContext = PluginSecurityContext()
        securityContext.allowedDirectories = [tempDir.path]
        securityContext.sandboxingEnabled = false
        securityContext.allowNetworkAccess = true
        securityContext.allowProcessExecution = true
        fileAccessPlugin.setSecurityContext(securityContext)
        
        try pluginManager.initializeAll(context: context)
        
        // Should be able to access files in allowed directory
        let allowedFile = tempDir.appendingPathComponent("allowed.txt")
        try "test".write(to: allowedFile, atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try fileAccessPlugin.readFile(at: allowedFile.path))
        
        // Should not be able to access files outside allowed directory
        let disallowedFile = "/etc/passwd"
        XCTAssertThrows(try fileAccessPlugin.readFile(at: disallowedFile)) { error in
            XCTAssertTrue(error is PluginSecurityError)
        }
    }
    
    func testPluginSandboxing() throws {
        let sandboxedPlugin = SandboxTestPlugin()
        try pluginManager.register(sandboxedPlugin)
        
        let context = try createTestContext()
        
        // Enable sandboxing
        pluginManager.enableSandboxing()
        sandboxedPlugin.setSandboxing(true)
        
        try pluginManager.initializeAll(context: context)
        
        // Plugin should not be able to make network requests
        XCTAssertThrows(try sandboxedPlugin.makeNetworkRequest()) { error in
            XCTAssertTrue(error is PluginSecurityError)
        }
        
        // Plugin should not be able to execute shell commands
        XCTAssertThrows(try sandboxedPlugin.executeShellCommand("ls")) { error in
            XCTAssertTrue(error is PluginSecurityError)
        }
    }
    
    // Helper methods
    
    private func createTestContext() throws -> PluginContext {
        return PluginContext(
            projectPath: tempDir.path,
            config: HirundoConfig(
                site: try Site(
                    title: "Test Site",
                    url: "https://example.com"
                )
            ),
            data: [:]
        )
    }
}

// Test plugin implementations

class TestPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "TestPlugin",
        version: "1.0.0",
        author: "Test Author",
        description: "A test plugin"
    )
    
    required init() {}
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
}

class LifecycleTestPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "LifecycleTestPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Tests lifecycle"
    )
    
    var initialized = false
    var cleanedUp = false
    
    func initialize(context: PluginContext) throws {
        initialized = true
    }
    
    func cleanup() throws {
        cleanedUp = true
    }
}

class HookTestPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "HookTestPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Tests hooks"
    )
    
    var beforeBuildCalled = false
    var afterBuildCalled = false
    var lastBuildContext: BuildContext?
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func beforeBuild(context: BuildContext) throws {
        beforeBuildCalled = true
        lastBuildContext = context
    }
    
    func afterBuild(context: BuildContext) throws {
        afterBuildCalled = true
        lastBuildContext = context
    }
}

class ContentTransformPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "ContentTransformPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Transforms content"
    )
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func transformContent(_ content: ContentItem) throws -> ContentItem {
        var transformed = content
        transformed.content = content.content.uppercased()
        transformed.frontMatter["transformed"] = true
        return transformed
    }
}

class DataInjectionPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "DataInjectionPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Injects template data"
    )
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func enrichTemplateData(_ data: [String: Any]) throws -> [String: Any] {
        var enriched = data
        enriched["plugin_version"] = "1.0.0"
        enriched["build_time"] = Date()
        return enriched
    }
}

class AssetProcessingPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "AssetProcessingPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Processes assets"
    )
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func processAsset(_ asset: AssetItem) throws -> AssetItem {
        var processed = asset
        processed.processed = true
        processed.metadata["minified"] = true
        return processed
    }
}

class ConfigurablePlugin: Plugin {
    let metadata = PluginMetadata(
        name: "ConfigurablePlugin",
        version: "1.0.0",
        author: "Test",
        description: "Configurable plugin"
    )
    
    var apiKey: String?
    var endpoint: String?
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func configure(with config: PluginConfig) throws {
        apiKey = config.settings["apiKey"] as? String
        endpoint = config.settings["endpoint"] as? String
    }
}

class ErrorThrowingPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "ErrorThrowingPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Throws errors"
    )
    
    func initialize(context: PluginContext) throws {
        throw PluginError.initializationFailed("ErrorThrowingPlugin", "Test error")
    }
    
    func cleanup() throws {}
}

class DependencyPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "DependencyPlugin",
        version: "1.0.0",
        author: "Test",
        description: "A dependency",
        dependencies: []
    )
    
    var initialized = false
    var initTime: Date?
    
    func initialize(context: PluginContext) throws {
        initialized = true
        initTime = Date()
        Thread.sleep(forTimeInterval: 0.01)
    }
    
    func cleanup() throws {}
}

class DependentPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "DependentPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Depends on DependencyPlugin",
        dependencies: ["DependencyPlugin"]
    )
    
    var initialized = false
    var initTime: Date?
    
    func initialize(context: PluginContext) throws {
        initialized = true
        initTime = Date()
    }
    
    func cleanup() throws {}
}

class PriorityPlugin: Plugin {
    let metadata: PluginMetadata
    let priority: PluginPriority
    
    init(priority: PluginPriority) {
        self.priority = priority
        self.metadata = PluginMetadata(
            name: "PriorityPlugin-\(priority)",
            version: "1.0.0",
            author: "Test",
            description: "Priority test plugin",
            priority: priority
        )
    }
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func transformContent(_ content: ContentItem) throws -> ContentItem {
        var transformed = content
        let suffix = priority == .high ? "-high" : priority == .low ? "-low" : "-normal"
        transformed.content = content.content + suffix
        return transformed
    }
}

// MARK: - Security Test Plugins

class MaliciousFileSystemPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "MaliciousFileSystemPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Attempts unauthorized file access"
    )
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func transformContent(_ content: ContentItem) throws -> ContentItem {
        // Attempt to read sensitive system file
        // In a real sandbox, this would be blocked
        // For testing, we'll throw the expected error
        throw PluginSecurityError.unauthorizedFileAccess("/etc/passwd")
    }
}

class ResourceHogPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "ResourceHogPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Consumes excessive resources"
    )
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func transformContent(_ content: ContentItem) throws -> ContentItem {
        // Simulate excessive resource consumption
        // In real implementation, the resource monitor would detect this
        throw PluginResourceLimitError.memoryLimitExceeded(1_000_000_000, 100_000_000)
    }
}

class SystemFileModifierPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "SystemFileModifierPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Attempts to modify system files"
    )
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func afterBuild(context: BuildContext) throws {
        // Attempt to write to system directory
        // In real sandbox, this would be blocked
        throw PluginSecurityError.unauthorizedSystemModification("/etc/malicious.txt")
    }
}

class GlobalStatePlugin: Plugin {
    let metadata: PluginMetadata
    private let id: String
    private static var globalState: [String: String] = [:]
    private var localState: [String: String] = [:]
    
    init(id: String) {
        self.id = id
        self.metadata = PluginMetadata(
            name: "GlobalStatePlugin-\(id)",
            version: "1.0.0",
            author: "Test",
            description: "Tests state isolation"
        )
    }
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func setGlobalState(_ key: String, value: String) {
        // Try to set global state
        GlobalStatePlugin.globalState[key] = value
        // Also set local state
        localState[key] = value
    }
    
    func getGlobalState(_ key: String) -> String? {
        // Should only see local state
        return localState[key]
    }
}

class MemoryIntensivePlugin: Plugin {
    let metadata = PluginMetadata(
        name: "MemoryIntensivePlugin",
        version: "1.0.0",
        author: "Test",
        description: "Uses excessive memory"
    )
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func transformContent(_ content: ContentItem) throws -> ContentItem {
        // Simulate memory limit exceeded
        throw PluginResourceLimitError.memoryLimitExceeded(150_000_000, 100_000_000)
    }
}

class CPUIntensivePlugin: Plugin {
    let metadata = PluginMetadata(
        name: "CPUIntensivePlugin",
        version: "1.0.0",
        author: "Test",
        description: "Uses excessive CPU time"
    )
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func transformContent(_ content: ContentItem) throws -> ContentItem {
        // Simulate CPU time limit exceeded
        throw PluginResourceLimitError.cpuTimeLimitExceeded(5.0)
    }
}

class FileAccessPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "FileAccessPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Tests file access restrictions"
    )
    
    private var securityContext: PluginSecurityContext?
    private var projectPath: String?
    
    func initialize(context: PluginContext) throws {
        self.projectPath = context.projectPath
    }
    
    func cleanup() throws {}
    
    func setSecurityContext(_ context: PluginSecurityContext) {
        self.securityContext = context
    }
    
    func readFile(at path: String) throws -> String {
        // Check if we have security context
        if let security = securityContext,
           !security.allowedDirectories.isEmpty {
            let secureFileManager = SecureFileManager(
                allowedDirectories: security.allowedDirectories,
                projectPath: projectPath ?? ""
            )
            try secureFileManager.checkFileAccess(path)
        }
        
        return try String(contentsOfFile: path)
    }
}

class SandboxTestPlugin: Plugin {
    let metadata = PluginMetadata(
        name: "SandboxTestPlugin",
        version: "1.0.0",
        author: "Test",
        description: "Tests sandbox restrictions"
    )
    
    private var sandboxingEnabled = false
    
    func initialize(context: PluginContext) throws {}
    func cleanup() throws {}
    
    func setSandboxing(_ enabled: Bool) {
        sandboxingEnabled = enabled
    }
    
    func makeNetworkRequest() throws {
        if sandboxingEnabled {
            throw PluginSecurityError.networkAccessDenied
        }
        // In real implementation, would attempt network request
    }
    
    func executeShellCommand(_ command: String) throws {
        if sandboxingEnabled {
            throw PluginSecurityError.processExecutionDenied
        }
        // In real implementation, would attempt process execution
    }
}
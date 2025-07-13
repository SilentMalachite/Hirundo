import XCTest
@testable import HirundoCore

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
            type: .markdown
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
        
        // Register in wrong order
        try pluginManager.register(dependentPlugin)
        try pluginManager.register(dependencyPlugin)
        
        let context = try createTestContext()
        
        // Should initialize in correct order based on dependencies
        try pluginManager.initializeAll(context: context)
        
        XCTAssertTrue(dependencyPlugin.initialized)
        XCTAssertTrue(dependentPlugin.initialized)
        XCTAssertLessThan(dependencyPlugin.initTime!, dependentPlugin.initTime!)
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
            type: .markdown
        )
        
        let context = try createTestContext()
        try pluginManager.initializeAll(context: context)
        
        let transformed = try pluginManager.transformContent(content)
        
        // Should be processed in priority order: high -> normal -> low
        XCTAssertEqual(transformed.content, "test-high-normal-low")
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
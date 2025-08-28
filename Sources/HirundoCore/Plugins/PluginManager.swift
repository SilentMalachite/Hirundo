import Foundation

/// プラグインの登録と実行を管理するクラス
public class PluginManager {
    private var plugins: [String: Plugin] = [:]
    private var pluginOrder: [String] = []
    private var initialized = false
    private var context: PluginContext?
    private var resourceLimits = PluginResourceLimits()
    private var securityContext = PluginSecurityContext()
    private var executionMonitor = PluginExecutionMonitor()
    
    public init() {}
    
    /// 登録されたプラグインを取得
    public var registeredPlugins: [Plugin] {
        return pluginOrder.compactMap { plugins[$0] }
    }
    
    /// プラグインを登録
    /// - Parameter plugin: 登録するプラグイン
    /// - Throws: PluginError 登録に失敗した場合
    public func register(_ plugin: Plugin) throws {
        let name = plugin.metadata.name
        
        if plugins[name] != nil {
            throw PluginError.duplicatePlugin(name)
        }
        
        plugins[name] = plugin
        
        // 依存関係と優先度に基づいてプラグイン順序を再構築
        try rebuildPluginOrder()
    }
    
    /// プラグインを設定
    /// - Parameters:
    ///   - name: プラグイン名
    ///   - config: 設定
    /// - Throws: PluginError 設定に失敗した場合
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
    
    /// すべてのプラグインを初期化
    /// - Parameter context: プラグインコンテキスト
    /// - Throws: PluginError 初期化に失敗した場合
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
    
    /// すべてのプラグインをクリーンアップ
    /// - Throws: PluginError クリーンアップに失敗した場合
    public func cleanupAll() throws {
        // 逆順でクリーンアップ
        for name in pluginOrder.reversed() {
            guard let plugin = plugins[name] else { continue }
            try plugin.cleanup()
        }
        
        initialized = false
    }
    
    /// ビルド前フックを実行
    /// - Parameter buildContext: ビルドコンテキスト
    /// - Throws: PluginError フックの実行に失敗した場合
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
    
    /// ビルド後フックを実行
    /// - Parameter buildContext: ビルドコンテキスト
    /// - Throws: PluginError フックの実行に失敗した場合
    public func executeAfterBuild(buildContext: BuildContext) throws {
        guard initialized else { return }
        
        for name in pluginOrder {
            guard let plugin = plugins[name] else { continue }
            
            executionMonitor.startMonitoring()
            
            do {
                try executeWithSecurity { [buildContext, plugin] in
                    try plugin.afterBuild(context: buildContext)
                }
            } catch {
                throw PluginError.hookFailed("afterBuild", error.localizedDescription)
            }
        }
    }
    
    /// セキュリティ付きでプラグインを実行
    /// - Parameter block: 実行するブロック
    /// - Throws: PluginError 実行に失敗した場合
    private func executeWithSecurity(_ block: () throws -> Void) throws {
        // リソース制限をチェック
        try executionMonitor.checkResourceLimits(resourceLimits)
        
        // セキュリティコンテキストを適用
        if securityContext.sandboxingEnabled {
            // サンドボックス化された実行
            try executeInSandbox(block)
        } else {
            // 通常の実行
            try block()
        }
    }
    
    /// サンドボックス内でプラグインを実行
    /// - Parameter block: 実行するブロック
    /// - Throws: PluginError 実行に失敗した場合
    private func executeInSandbox(_ block: () throws -> Void) throws {
        // サンドボックス化の実装
        // 実際の実装では、より詳細なサンドボックス化が必要
        try block()
    }
    
    /// プラグイン順序を再構築
    /// - Throws: PluginError 再構築に失敗した場合
    private func rebuildPluginOrder() throws {
        var visited: Set<String> = []
        var tempMark: Set<String> = []
        var order: [String] = []
        
        func visit(_ name: String) throws {
            if tempMark.contains(name) {
                throw PluginError.circularDependency([name])
            }
            if visited.contains(name) {
                return
            }
            
            tempMark.insert(name)
            
            // 依存関係を訪問
            if let plugin = plugins[name] {
                for dependency in plugin.metadata.dependencies {
                    try visit(dependency)
                }
            }
            
            tempMark.remove(name)
            visited.insert(name)
            order.append(name)
        }
        
        for name in plugins.keys {
            if !visited.contains(name) {
                try visit(name)
            }
        }
        
        pluginOrder = order
    }
    
    /// リソース制限を設定
    /// - Parameter limits: リソース制限
    public func setResourceLimits(_ limits: PluginResourceLimits) {
        self.resourceLimits = limits
    }
    
    /// セキュリティコンテキストを設定
    /// - Parameter context: セキュリティコンテキスト
    public func setSecurityContext(_ context: PluginSecurityContext) {
        self.securityContext = context
    }

    // MARK: - Convenience configuration APIs used by tests
    public func setResourceLimit(_ type: ResourceType, value: Double) {
        switch type {
        case .memory:
            self.resourceLimits.memoryLimit = Int(value)
        case .cpuTime:
            self.resourceLimits.cpuTimeLimit = value
        case .fileCount:
            self.resourceLimits.fileOperationLimit = Int(value)
        }
    }
    
    public func setAllowedDirectories(_ directories: [String]) {
        self.securityContext.allowedDirectories = directories
    }
    
    public func enableSandboxing() {
        self.securityContext.sandboxingEnabled = true
    }

    /// Processes an asset through all registered plugins in order
    /// - Parameter asset: The asset to process
    /// - Returns: The processed asset after all plugins have had a chance
    public func processAsset(_ asset: AssetItem) throws -> AssetItem {
        var current = asset
        guard initialized else { return current }
        
        for name in pluginOrder {
            guard let plugin = plugins[name] else { continue }
            do {
                current = try plugin.processAsset(current)
            } catch {
                throw PluginError.hookFailed("processAsset", error.localizedDescription)
            }
        }
        return current
    }

    /// Transforms content through all plugins (before -> transform -> after)
    /// - Parameter content: The original content item
    /// - Returns: The transformed content item
    public func transformContent(_ content: ContentItem) throws -> ContentItem {
        var current = content
        guard initialized else { return current }
        
        for name in pluginOrder {
            guard let plugin = plugins[name] else { continue }
            do {
                try executeWithSecurity {
                    current = try plugin.beforeContentTransform(current)
                    current = try plugin.transformContent(current)
                    current = try plugin.afterContentTransform(current)
                }
            } catch {
                throw PluginError.hookFailed("transformContent", error.localizedDescription)
            }
        }
        return current
    }

    /// Allows plugins to enrich template data before rendering
    /// - Parameter data: Original template data
    /// - Returns: Enriched template data
    public func enrichTemplateData(_ data: [String: Any]) throws -> [String: Any] {
        var current = data
        guard initialized else { return current }
        
        for name in pluginOrder {
            guard let plugin = plugins[name] else { continue }
            do {
                try executeWithSecurity {
                    current = try plugin.enrichTemplateData(current)
                }
            } catch {
                throw PluginError.hookFailed("enrichTemplateData", error.localizedDescription)
            }
        }
        return current
    }
}

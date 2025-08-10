import Foundation

/// Refactored SiteGenerator with separated responsibilities
public final class SiteGeneratorRefactored {
    // Sub-components with specific responsibilities
    private let contentProcessor: ContentProcessor
    private let staticFileHandler: StaticFileHandler
    private let pageRenderer: PageRenderer
    private let pluginManager: PluginManager
    
    // Configuration
    private let config: HirundoConfig
    private let fileManager: FileManager
    
    // Cache for performance
    private var contentCache: [String: ContentItem] = [:]
    private let cacheQueue = DispatchQueue(label: "com.hirundo.sitegen.cache", attributes: .concurrent)
    
    public init(config: HirundoConfig, fileManager: FileManager = .default) {
        self.config = config
        self.fileManager = fileManager
        
        // Initialize sub-components
        self.contentProcessor = ContentProcessor(limits: config.limits, fileManager: fileManager)
        self.staticFileHandler = StaticFileHandler(fileManager: fileManager)
        self.pageRenderer = PageRenderer(
            templatesDirectory: config.build.templatesDirectory,
            fileManager: fileManager
        )
        self.pluginManager = PluginManager()
        
        // Configure components
        self.pageRenderer.configure(with: config.site)
    }
    
    // MARK: - Public API
    
    /// Build the entire site
    public func build(clean: Bool = false) throws {
        print("🚀 Starting site build...")
        
        // Clean output directory if requested
        if clean {
            try cleanOutput()
        }
        
        // Initialize plugins
        try initializePlugins()
        
        // Process content
        let startTime = Date()
        let content = try processContent()
        print("📝 Processed \(content.count) content files")
        
        // Copy static files
        try copyStaticFiles()
        
        // Render pages
        try renderPages(content)
        
        // Execute post-build plugins
        try executePostBuildPlugins()
        
        let buildTime = Date().timeIntervalSince(startTime)
        print("✅ Build completed in \(String(format: "%.2f", buildTime))s")
    }
    
    /// Build incrementally (only changed files)
    public func buildIncremental(changedFiles: [String]) throws {
        print("🔄 Incremental build for \(changedFiles.count) files...")
        
        // Process only changed content files
        let contentFiles = changedFiles.filter { path in
            path.hasSuffix(".md") || path.hasSuffix(".markdown")
        }
        
        if !contentFiles.isEmpty {
            let items = try contentProcessor.processBatch(contentFiles)
            
            // Update cache
            cacheQueue.async(flags: .barrier) {
                for item in items {
                    self.contentCache[item.path] = item
                }
            }
            
            // Render updated pages
            try renderPages(items)
        }
        
        // Handle static file changes
        let staticFiles = changedFiles.filter { path in
            !contentFiles.contains(path)
        }
        
        if !staticFiles.isEmpty {
            try copyChangedStaticFiles(staticFiles)
        }
        
        print("✅ Incremental build completed")
    }
    
    // MARK: - Private Methods
    
    private func cleanOutput() throws {
        try staticFileHandler.cleanOutputDirectory(config.build.outputDirectory)
    }
    
    private func initializePlugins() throws {
        // Load and initialize plugins
        let pluginContext = PluginContext(
            projectPath: FileManager.default.currentDirectoryPath,
            config: config
        )
        
        try pluginManager.initializeAll(context: pluginContext)
    }
    
    private func processContent() throws -> [ContentItem] {
        // Check cache first
        let cachedItems = cacheQueue.sync { Array(contentCache.values) }
        if !cachedItems.isEmpty {
            return cachedItems
        }
        
        // Process content directory
        let items = try contentProcessor.processContentDirectory(
            at: config.build.contentDirectory
        )
        
        // Update cache
        cacheQueue.async(flags: .barrier) {
            for item in items {
                self.contentCache[item.path] = item
            }
        }
        
        return items
    }
    
    private func copyStaticFiles() throws {
        try staticFileHandler.copyStaticFiles(
            from: config.build.staticDirectory,
            to: config.build.outputDirectory
        )
    }
    
    private func renderPages(_ items: [ContentItem]) throws {
        // Build base context
        let baseContext: [String: Any] = [
            "site": [
                "title": config.site.title,
                "description": config.site.description,
                "url": config.site.url,
                "author": config.site.author?.name ?? "",
                "language": config.site.language
            ],
            "pages": items.filter { $0.type == .page },
            "posts": items.filter { $0.type == .post }
                .sorted { (lhs, rhs) in
                    let lhsDate = lhs.frontMatter["date"] as? Date ?? Date()
                    let rhsDate = rhs.frontMatter["date"] as? Date ?? Date()
                    return lhsDate > rhsDate
                }
        ]
        
        // Render pages concurrently
        let queue = DispatchQueue(label: "com.hirundo.render", attributes: .concurrent)
        let group = DispatchGroup()
        var errors: [Error] = []
        let errorLock = NSLock()
        
        for item in items {
            group.enter()
            queue.async { [weak self] in
                defer { group.leave() }
                
                guard let self = self else { return }
                
                do {
                    let outputPath = self.calculateOutputPath(for: item)
                    try self.pageRenderer.renderAndWritePage(
                        item,
                        to: outputPath,
                        with: baseContext
                    )
                } catch {
                    errorLock.lock()
                    errors.append(error)
                    errorLock.unlock()
                    print("⚠️ Failed to render \(item.path): \(error)")
                }
            }
        }
        
        group.wait()
        
        if !errors.isEmpty {
            throw BuildError.contentError("\(errors.count) pages failed to render")
        }
    }
    
    private func copyChangedStaticFiles(_ files: [String]) throws {
        for file in files {
            let sourceURL = URL(fileURLWithPath: file)
            let relativePath = sourceURL.relativePath(
                from: URL(fileURLWithPath: config.build.staticDirectory)
            )
            
            if let relativePath = relativePath {
                let destPath = URL(fileURLWithPath: config.build.outputDirectory)
                    .appendingPathComponent(relativePath)
                    .path
                
                try staticFileHandler.copyFile(from: file, to: destPath)
            }
        }
    }
    
    private func calculateOutputPath(for item: ContentItem) -> String {
        let outputURL = URL(fileURLWithPath: config.build.outputDirectory)
        let itemPath = item.path.replacingOccurrences(of: ".md", with: "").replacingOccurrences(of: ".markdown", with: "")
        let itemURL = URL(fileURLWithPath: itemPath)
        
        // Create pretty URLs (directory/index.html)
        if itemURL.lastPathComponent == "index" {
            return outputURL.appendingPathComponent("index.html").path
        } else {
            return outputURL
                .appendingPathComponent(itemURL.lastPathComponent)
                .appendingPathComponent("index.html")
                .path
        }
    }
    
    private func executePostBuildPlugins() throws {
        let buildContext = BuildContext(
            outputPath: config.build.outputDirectory,
            isDraft: false,
            isClean: false,
            pages: Array(contentCache.values),
            config: config
        )
        
        try pluginManager.executeAfterBuild(buildContext: buildContext)
    }
    
    // MARK: - Cache Management
    
    /// Clear all caches
    public func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.contentCache.removeAll()
        }
        pageRenderer.clearCache()
        PathSanitizer.clearCache()
    }
    
    /// Get cache statistics
    public func getCacheStatistics() -> (content: Int, paths: (hits: Int, misses: Int, size: Int)) {
        let contentCount = cacheQueue.sync { contentCache.count }
        let pathStats = PathSanitizer.getCacheStatistics()
        return (content: contentCount, paths: pathStats)
    }
}


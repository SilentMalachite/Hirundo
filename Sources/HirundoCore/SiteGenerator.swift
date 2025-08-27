import Foundation

// Refactored SiteGenerator following Single Responsibility Principle
public class SiteGenerator {
    private let projectPath: String
    private let config: HirundoConfig
    private let fileManager: FileManager
    
    // Delegated responsibilities
    private let securityValidator: SecurityValidator
    private let contentProcessor: ContentProcessor
    private let siteFileManager: SiteFileManager
    private let templateRenderer: SiteTemplateRenderer
    private let archiveGenerator: ArchiveGenerator
    private let pluginManager: PluginManager
    private let assetPipeline: AssetPipeline
    
    /// Designated initializer that accepts a resolved configuration
    /// - Parameters:
    ///   - projectPath: Root directory of the project (parent of the configuration file)
    ///   - config: Parsed Hirundo configuration to use
    ///   - fileManager: FileManager instance (for testing/injection)
    public init(projectPath: String, config: HirundoConfig, fileManager: FileManager = .default) throws {
        self.projectPath = projectPath
        self.fileManager = fileManager
        self.config = config

        // Initialize components with single responsibilities
        self.securityValidator = SecurityValidator(projectPath: projectPath, config: config)
        self.contentProcessor = ContentProcessor(config: config, securityValidator: securityValidator)
        self.siteFileManager = SiteFileManager(config: config, securityValidator: securityValidator, projectPath: projectPath, fileManager: fileManager)

        let templatesPath = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.templatesDirectory)
            .path
        self.templateRenderer = SiteTemplateRenderer(
            templatesDirectory: templatesPath,
            config: config,
            securityValidator: securityValidator
        )

        self.archiveGenerator = ArchiveGenerator(
            fileManager: siteFileManager,
            templateRenderer: templateRenderer,
            config: config,
            templateEngine: templateRenderer.templateEngine
        )

        // Initialize plugin system
        self.pluginManager = PluginManager()
        self.assetPipeline = AssetPipeline(pluginManager: pluginManager)

        // Load and configure plugins
        try loadPlugins()
    }

    /// Convenience initializer using default config filename (config.yaml) under the project path
    /// - Parameters:
    ///   - projectPath: Root directory containing config.yaml
    ///   - fileManager: FileManager instance (for testing/injection)
    public convenience init(projectPath: String, fileManager: FileManager = .default) throws {
        let configURL = URL(fileURLWithPath: projectPath).appendingPathComponent("config.yaml")
        let config = try HirundoConfig.load(from: configURL)
        try self.init(projectPath: projectPath, config: config, fileManager: fileManager)
    }

    /// Convenience initializer that loads configuration from an explicit URL
    /// - Parameters:
    ///   - configURL: Path to the configuration YAML file (arbitrary filename allowed)
    ///   - fileManager: FileManager instance (for testing/injection)
    public convenience init(configURL: URL, fileManager: FileManager = .default) throws {
        let projectPath = configURL.deletingLastPathComponent().path
        let config = try HirundoConfig.load(from: configURL)
        try self.init(projectPath: projectPath, config: config, fileManager: fileManager)
    }
    
    // Main build method - orchestrates the build process
    public func build(clean: Bool = false, includeDrafts: Bool = false) async throws {
        let buildStartTime = Date()
        
        let outputURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.outputDirectory)
        
        // Create build context
        let buildContext = BuildContext(
            outputPath: outputURL.path,
            isDraft: includeDrafts,
            isClean: clean,
            config: config
        )
        
        // Execute before build hook
        try pluginManager.executeBeforeBuild(buildContext: buildContext)
        
        // Prepare output directory
        try siteFileManager.prepareOutputDirectory(at: outputURL.path, clean: clean)
        
        // Process content
        let contentURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.contentDirectory)
        
        let (pages, posts) = try await processContent(
            contentDirectory: contentURL,
            outputDirectory: outputURL,
            includeDrafts: includeDrafts
        )
        
        // Generate archive pages
        try archiveGenerator.generateArchivePage(posts: posts, outputURL: outputURL)
        try archiveGenerator.generateCategoryPages(posts: posts, outputURL: outputURL)
        try archiveGenerator.generateTagPages(posts: posts, outputURL: outputURL)
        
        // Process static assets
        try processStaticAssets(outputURL: outputURL)
        
        // Execute after build hook
        try pluginManager.executeAfterBuild(buildContext: buildContext)
        
        // Print build summary
        let buildTime = Date().timeIntervalSince(buildStartTime)
        printBuildSummary(pages: pages.count, posts: posts.count, buildTime: buildTime)
    }
    
    // Build with error recovery
    public func buildWithRecovery(clean: Bool = false, includeDrafts: Bool = false) async throws -> BuildResult {
        var errors: [BuildErrorDetail] = []
        var successCount = 0
        var failCount = 0
        
        // Prepare directories
        let outputURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.outputDirectory)
        
        let contentURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.contentDirectory)
        
        // Clean output directory if needed
        if clean && FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Create output directory
        try FileManager.default.createDirectory(
            at: outputURL,
            withIntermediateDirectories: true
        )
        
        // Process content with error recovery
        let (processedContents, processingErrors) = try await contentProcessor.processDirectoryWithRecovery(
            at: contentURL,
            includeDrafts: includeDrafts
        )
        
        // Add processing errors to the error list
        for (fileURL, error) in processingErrors {
            failCount += 1
            errors.append(BuildErrorDetail(
                file: fileURL.path,
                stage: .parsing,
                error: error,
                recoverable: true
            ))
        }
        
        for content in processedContents {
            do {
                print("[SiteGenerator] Processing content: \(content.url.lastPathComponent)")
                _ = try await processIndividualContent(
                    content,
                    outputDirectory: outputURL,
                    allPages: [],
                    allPosts: []
                )
                successCount += 1
                print("[SiteGenerator] Successfully processed: \(content.url.lastPathComponent)")
            } catch {
                failCount += 1
                print("[SiteGenerator] Failed to process \(content.url.lastPathComponent): \(error)")
                errors.append(BuildErrorDetail(
                    file: content.url.path,
                    stage: .rendering,
                    error: error,
                    recoverable: true
                ))
            }
        }
        
        return BuildResult(
            success: failCount == 0,
            errors: errors,
            successCount: successCount,
            failCount: failCount
        )
    }
    
    // Private methods
    
    private func processContent(
        contentDirectory: URL,
        outputDirectory: URL,
        includeDrafts: Bool
    ) async throws -> (pages: [Page], posts: [Post]) {
        var pages: [Page] = []
        var posts: [Post] = []
        
        // Process all content files
        let processedContents = try await contentProcessor.processDirectory(
            at: contentDirectory,
            includeDrafts: includeDrafts
        )
        
        // Render and write each content
        for content in processedContents {
            let (page, post) = try await processIndividualContent(
                content,
                outputDirectory: outputDirectory,
                allPages: pages,
                allPosts: posts
            )
            
            if let page = page {
                pages.append(page)
            }
            if let post = post {
                posts.append(post)
            }
        }
        
        return (pages, posts)
    }
    
    private func processIndividualContent(
        _ content: ProcessedContent,
        outputDirectory: URL,
        allPages: [Page],
        allPosts: [Post]
    ) async throws -> (page: Page?, post: Post?) {
        // Render markdown to HTML
        let htmlContent = contentProcessor.renderMarkdownContent(content.markdown)
        
        // Render with template
        let renderedHTML = try await templateRenderer.renderContent(
            content,
            htmlContent: htmlContent,
            allPages: allPages,
            allPosts: allPosts
        )
        
        // Determine output path
        // Resolve both paths to handle system symlinks consistently
        let contentBasePath = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.contentDirectory)
            .resolvingSymlinksInPath()
            .path
        let resolvedContentPath = content.url.resolvingSymlinksInPath().path
        
        // Get the relative path from the content directory
        let relativePath: String
        if resolvedContentPath.hasPrefix(contentBasePath) {
            relativePath = String(resolvedContentPath.dropFirst(contentBasePath.count))
        } else {
            // Fallback to original calculation
            relativePath = content.url.path.replacingOccurrences(
                of: URL(fileURLWithPath: projectPath).appendingPathComponent(config.build.contentDirectory).path,
                with: ""
            )
        }
        
        // Remove leading slash if present
        let cleanRelativePath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        
        // Special handling for index.md files - they should become index.html in their directory
        let outputPath: URL
        if cleanRelativePath == "index.md" || cleanRelativePath.hasSuffix("/index.md") {
            // index.md becomes index.html in the same directory
            outputPath = outputDirectory.appendingPathComponent(cleanRelativePath)
                .deletingPathExtension()
                .appendingPathExtension("html")
        } else {
            // Other files become file/index.html
            outputPath = outputDirectory.appendingPathComponent(cleanRelativePath)
                .deletingPathExtension()
                .appendingPathComponent("index.html")
        }
        
        // Write output file
        try siteFileManager.writeFile(content: renderedHTML, to: outputPath)
        
        // Create page or post model
        switch content.type {
        case .page:
            let page = Page(
                title: content.metadata.title,
                slug: content.metadata.slug ?? content.url.deletingPathExtension().lastPathComponent,
                url: outputPath.path,
                description: content.metadata.description,
                content: htmlContent
            )
            return (page, nil)
            
        case .post:
            let post = Post(
                title: content.metadata.title,
                slug: content.metadata.slug ?? content.url.deletingPathExtension().lastPathComponent,
                url: outputPath.path,
                date: content.metadata.date,
                author: content.metadata.author,
                description: content.metadata.description,
                categories: content.metadata.categories,
                tags: content.metadata.tags,
                content: htmlContent
            )
            return (nil, post)
        }
    }
    
    private func processStaticAssets(outputURL: URL) throws {
        let staticURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.staticDirectory)
        
        guard siteFileManager.fileExists(at: staticURL.path) else {
            return
        }
        
        // Configure asset pipeline
        configureAssetPipeline()
        
        // Process assets through pipeline
        let manifest = try assetPipeline.processAssets(
            from: staticURL.path,
            to: outputURL.path
        )
        
        // Save manifest if generated
        if !manifest.isEmpty {
            let manifestPath = outputURL.appendingPathComponent("asset-manifest.json")
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: manifestPath)
        }
    }
    
    private func configureAssetPipeline() {
        // Asset pipeline configuration is handled through plugin system
        // Plugins modify the pipeline during their execution
    }
    
    private func loadPlugins() throws {
        let pluginContext = PluginContext(
            projectPath: projectPath,
            config: config
        )
        
        // Load built-in plugins based on configuration
        for pluginConfig in config.plugins {
            if pluginConfig.enabled {
                try loadPlugin(pluginConfig, context: pluginContext)
            }
        }
        
        // Initialize plugins after registration so hooks can run
        try pluginManager.initializeAll(context: pluginContext)
    }
    
    private func loadPlugin(_ pluginConfig: HirundoConfig.PluginConfiguration, context: PluginContext) throws {
        switch pluginConfig.name {
        case "sitemap":
            let plugin = SitemapPlugin()
            try configurePlugin(plugin, with: pluginConfig)
            try pluginManager.register(plugin)
            
        case "rss":
            let plugin = RSSPlugin()
            try configurePlugin(plugin, with: pluginConfig)
            try pluginManager.register(plugin)
            
        case "minify":
            let plugin = MinifyPlugin()
            try configurePlugin(plugin, with: pluginConfig)
            try pluginManager.register(plugin)
            
        default:
            print("Warning: Unknown plugin '\(pluginConfig.name)'")
        }
    }
    
    private func configurePlugin(_ plugin: Plugin, with config: HirundoConfig.PluginConfiguration) throws {
        if !config.settings.isEmpty {
            let pluginConfig = PluginConfig(name: config.name, enabled: config.enabled, settings: config.settings)
            try plugin.configure(with: pluginConfig)
        }
    }
    
    private func printBuildSummary(pages: Int, posts: Int, buildTime: TimeInterval) {
        print("\nBuild completed successfully!")
        print("========================")
        print("Pages: \(pages)")
        print("Posts: \(posts)")
        print("Build time: \(String(format: "%.2f", buildTime))s")
    }
}

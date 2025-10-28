import Foundation

// Refactored SiteGenerator following Single Responsibility Principle
public class SiteGenerator {
    private let projectPath: String
    private let config: HirundoConfig
    private let fileManager: FileManager
    
    // Delegated responsibilities
    private let contentProcessor: ContentProcessor
    private let siteFileManager: SiteFileManager
    private let templateRenderer: SiteTemplateRenderer
    private let archiveGenerator: ArchiveGenerator
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
        self.contentProcessor = ContentProcessor(config: config, projectPath: projectPath)
        self.siteFileManager = SiteFileManager(config: config, projectPath: projectPath, fileManager: fileManager)

        let templatesPath = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.templatesDirectory)
            .path
        self.templateRenderer = SiteTemplateRenderer(
            templatesDirectory: templatesPath,
            config: config
        )

        self.archiveGenerator = ArchiveGenerator(
            fileManager: siteFileManager,
            templateRenderer: templateRenderer,
            config: config,
            templateEngine: templateRenderer.templateEngine
        )

        // Initialize asset pipeline (no external plugins in Stage 2)
        self.assetPipeline = AssetPipeline()
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
    public func build(clean: Bool = false, includeDrafts: Bool = false, environment: String = "production") async throws {
        let buildStartTime = Date()
        
        let outputURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.outputDirectory)
        
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

        // Built-in features (Stage 2)
        if config.features.sitemap {
            try generateSitemap(outputURL: outputURL)
        }
        if config.features.rss {
            try generateRSS(posts: posts, outputURL: outputURL)
        }
        if config.features.searchIndex {
            try generateSearchIndex(pages: pages, posts: posts, outputURL: outputURL)
        }
        
        // Print build summary
        let buildTime = Date().timeIntervalSince(buildStartTime)
        printBuildSummary(pages: pages.count, posts: posts.count, buildTime: buildTime)
    }
    
    // Build with error recovery
    public func buildWithRecovery(clean: Bool = false, includeDrafts: Bool = false, environment: String = "production") async throws -> BuildResult {
        // Note: environment is reserved for future conditional behaviors
        var errors: [BuildErrorDetail] = []
        var successCount = 0
        var failCount = 0
        var processedPages: [Page] = []
        var processedPosts: [Post] = []
        
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
                try Task.checkCancellation()
                let (page, post) = try await processIndividualContent(
                    content,
                    outputDirectory: outputURL,
                    allPages: processedPages,
                    allPosts: processedPosts
                )
                successCount += 1
                if let page = page {
                    processedPages.append(page)
                }
                if let post = post {
                    processedPosts.append(post)
                }
            } catch {
                failCount += 1
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
            try Task.checkCancellation()
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
        // (debug removed)
        
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
        // Configure built-in options from features
        if config.features.minify {
            assetPipeline.cssOptions.minify = true
            assetPipeline.jsOptions.minify = true
        }
    }
    
    private func loadPlugins() throws {
        // Stage 2: No plugins to load.
    }

    // MARK: - Built-in feature generators (sitemap, RSS, search index)
    private func generateSitemap(outputURL: URL) throws {
        let fm = FileManager.default
        var urls: [(loc: String, lastmod: Date)] = []
        let base = config.site.url
        let enumerator = fm.enumerator(at: outputURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        while let fileURL = enumerator?.nextObject() as? URL {
            try Task.checkCancellation()
            guard fileURL.pathExtension == "html" else { continue }
            var rel = fileURL.path.replacingOccurrences(of: outputURL.path, with: "")
            rel = rel.replacingOccurrences(of: "/index.html", with: "/")
            let mod = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let loc = URLUtils.joinSiteURL(base: base, path: rel)
            urls.append((loc: loc, lastmod: mod))
        }
        let dateFormatter = ISO8601DateFormatter()
        var xml = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">

        """
        for u in urls {
            xml += """
            <url>
                <loc>\(escapeXML(u.loc))</loc>
                <lastmod>\(dateFormatter.string(from: u.lastmod))</lastmod>
                <changefreq>weekly</changefreq>
                <priority>0.5</priority>
            </url>

            """
        }
        xml += "</urlset>"
        try xml.write(to: outputURL.appendingPathComponent("sitemap.xml"), atomically: true, encoding: .utf8)
    }

    private func generateRSS(posts: [Post], outputURL: URL) throws {
        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())
        let selfHref = URLUtils.joinSiteURL(base: config.site.url, path: "/rss.xml")
        var rss = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n<channel>
            <title>\(escapeXML(config.site.title))</title>
            <link>\(escapeXML(config.site.url))</link>
            <description>\(escapeXML(config.site.description ?? ""))</description>
            <language>\(config.site.language ?? "en-US")</language>
            <lastBuildDate>\(now)</lastBuildDate>
            <atom:link href=\"\(escapeXML(selfHref))\" rel=\"self\" type=\"application/rss+xml\" />

        """
        let sorted = posts.sorted { $0.date > $1.date }.prefix(20)
        for p in sorted {
            let itemPath = "/posts/\(p.slug)/"
            let link = URLUtils.joinSiteURL(base: config.site.url, path: itemPath)
            let desc = p.description ?? String(p.content.prefix(200))
            rss += """
            <item>
                <title>\(escapeXML(p.title))</title>
                <link>\(escapeXML(link))</link>
                <guid>\(escapeXML(link))</guid>
                <pubDate>\(dateFormatter.string(from: p.date))</pubDate>
                <description>\(escapeXML(desc))</description>
            </item>

            """
        }
        rss += "</channel>\n</rss>\n"
        try rss.write(to: outputURL.appendingPathComponent("rss.xml"), atomically: true, encoding: .utf8)
    }

    private func generateSearchIndex(pages: [Page], posts: [Post], outputURL: URL) throws {
        struct Entry: Codable {
            let url: String
            let title: String
            let content: String
            let tags: [String]
            let date: Date?
        }
        struct Index: Codable {
            let version: String
            let generated: Date
            let entries: [Entry]
        }
        func stripHTML(_ s: String) -> String {
            return s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var entries: [Entry] = []
        for p in pages {
            let rel = siteRelativePath(forOutput: p.url)
            entries.append(Entry(url: rel, title: p.title, content: String(stripHTML(p.content).prefix(200)), tags: [], date: nil))
        }
        for p in posts {
            let rel = siteRelativePath(forOutput: p.url)
            let tags = p.categories + p.tags
            entries.append(Entry(url: rel, title: p.title, content: String(stripHTML(p.content).prefix(200)), tags: tags, date: p.date))
        }
        let index = Index(version: "1.0", generated: Date(), entries: entries)
        let data = try JSONEncoder().encode(index)
        try data.write(to: outputURL.appendingPathComponent("search-index.json"))
    }

    private func siteRelativePath(forOutput outputPath: String) -> String {
        var path = outputPath
        if let range = path.range(of: projectPath) { path.removeSubrange(range) }
        if path.hasSuffix("/index.html") { path = String(path.dropLast("/index.html".count)) + "/" }
        if !path.hasPrefix("/") { path = "/" + path }
        return path
    }

    private func escapeXML(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
              .replacingOccurrences(of: "<", with: "&lt;")
              .replacingOccurrences(of: ">", with: "&gt;")
              .replacingOccurrences(of: "\"", with: "&quot;")
              .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    private func printBuildSummary(pages: Int, posts: Int, buildTime: TimeInterval) {
        print("\nBuild completed successfully!")
        print("========================")
        print("Pages: \(pages)")
        print("Posts: \(posts)")
        print("Build time: \(String(format: "%.2f", buildTime))s")
    }
}

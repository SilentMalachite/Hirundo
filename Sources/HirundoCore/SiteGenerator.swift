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

    /// 直近の `processStaticAssets` が作ったマニフェスト。`asset references` ステップが読む。
    private var assetManifest = AssetManifest()

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
        
        for step in finalizationSteps(pages: pages, posts: posts, outputURL: outputURL) {
            try step.run()
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
        
        // The same finalization `build` runs, one step at a time so that a failing step is
        // reported rather than aborting the ones after it. Skipping this block is what used to
        // make `--continue-on-error` — and every `hirundo serve` rebuild — emit a site with no
        // static assets, no archive pages and none of the `features` output.
        for step in finalizationSteps(pages: processedPages, posts: processedPosts, outputURL: outputURL) {
            try Task.checkCancellation()
            do {
                try step.run()
            } catch is CancellationError {
                // A cancelled rebuild is not a build error to report; it is the caller giving up.
                throw CancellationError()
            } catch {
                failCount += 1
                errors.append(BuildErrorDetail(
                    file: step.name,
                    stage: .writing,
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
    
    private struct FinalizationStep {
        /// Names the output the step produces, so a failure reads like the build's other error
        /// lines rather than like a source file.
        let name: String
        let run: () throws -> Void
    }
    
    /// Everything that happens after the individual pages have been rendered: the blog index
    /// pages, the static asset pipeline, and the opt-in `features` outputs.
    ///
    /// Both build paths run this same list in this same order. `build` stops at the first
    /// failure; `buildWithRecovery` records it and moves on. Keeping the list in one place is
    /// what guarantees the two paths produce the same site.
    private func finalizationSteps(
        pages: [Page],
        posts: [Post],
        outputURL: URL
    ) -> [FinalizationStep] {
        var steps: [FinalizationStep] = [
            FinalizationStep(name: "archive") {
                try self.archiveGenerator.generateArchivePage(posts: posts, outputURL: outputURL)
            },
            FinalizationStep(name: "categories") {
                try self.archiveGenerator.generateCategoryPages(posts: posts, outputURL: outputURL)
            },
            FinalizationStep(name: "tags") {
                try self.archiveGenerator.generateTagPages(posts: posts, outputURL: outputURL)
            },
            FinalizationStep(name: "static assets") {
                try self.processStaticAssets(outputURL: outputURL)
            }
        ]
        if config.features.fingerprint {
            steps.append(FinalizationStep(name: "asset references") {
                try self.rewriteAssetReferences(outputURL: outputURL)
            })
        }
        if config.features.sitemap {
            steps.append(FinalizationStep(name: "sitemap.xml") {
                try self.generateSitemap(outputURL: outputURL)
            })
        }
        if config.features.rss {
            steps.append(FinalizationStep(name: "rss.xml") {
                try self.generateRSS(posts: posts, outputURL: outputURL)
            })
        }
        if config.features.searchIndex {
            steps.append(FinalizationStep(name: "search-index.json") {
                try self.generateSearchIndex(pages: pages, posts: posts, outputURL: outputURL)
            })
        }
        return steps
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
        
        // Determine output path from the *logical* path the content walk reported.
        //
        // Resolving symlinks here would throw that path away: a file found through
        // `content/shared -> ../elsewhere` would publish under `elsewhere`, and an alias to a
        // directory already inside `content/` would derive the very same output path as the
        // file it aliases, so one page would overwrite the other and both would carry the same
        // URL into the archive, the feed and the sitemap.
        let contentBase = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.contentDirectory)

        let cleanRelativePath: String
        if let relativePath = Self.pathRelative(content.url.path, to: contentBase.path) {
            // The walk reports every file it followed a symlink to at its logical path under
            // the content directory as configured, so this is the spelling that keeps a page
            // at the URL its path under `content/` implies.
            cleanRelativePath = relativePath
        } else if let relativePath = Self.pathRelative(
            content.url.resolvingSymlinksInPath().path,
            to: contentBase.resolvingSymlinksInPath().path
        ) {
            // Not a logical path, so it came straight from `FileManager`'s enumerator, which
            // hands out its own spelling of the directory it walked (`/private/var` where the
            // configured path says `/var`). Resolving both sides folds those together, and it
            // cannot move a page: a file found behind a symlink never reaches this branch.
            cleanRelativePath = relativePath
        } else {
            // Fallback for a file that is not under the content directory at all.
            let relativePath = content.url.path.replacingOccurrences(of: contentBase.path, with: "")
            cleanRelativePath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        }

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

        // 前の世代の目録。`static/images/` ごと、あるいは `static/` ごと消されたアセットは、
        // 今回の走査からは届かないので、これだけが古い出力の在り処を知っている。
        let manifestPath = outputURL.appendingPathComponent("asset-manifest.json").path
        let previous = (try? assetPipeline.loadManifest(from: manifestPath)) ?? AssetManifest()

        guard siteFileManager.fileExists(at: staticURL.path) else {
            assetManifest = AssetManifest()
            guard config.features.fingerprint else { return }
            try pruneAndRecord(AssetManifest(), previous: previous, outputURL: outputURL, staticURL: staticURL)
            return
        }

        configureAssetPipeline()

        // Cleared before the call, not just overwritten after: if `processAssets` throws below,
        // this generator must not be left holding a previous build's manifest for a later
        // finalization step (`asset references`) to read as if it described this build's output.
        assetManifest = AssetManifest()
        let manifest = try assetPipeline.processAssets(
            from: staticURL.path,
            to: outputURL.path
        )
        assetManifest = manifest

        guard config.features.fingerprint else { return }
        try pruneAndRecord(manifest, previous: previous, outputURL: outputURL, staticURL: staticURL)
    }

    /// 前の世代のハッシュ名の出力を落として、今回の目録を書き出す。serve は clean せずに
    /// 再ビルドするため、掃除が無いと世代ごとに出力が積み上がる。
    private func pruneAndRecord(
        _ manifest: AssetManifest,
        previous: AssetManifest,
        outputURL: URL,
        staticURL: URL
    ) throws {
        try AssetPruner.prune(
            outputDirectory: outputURL,
            staticDirectory: staticURL,
            keeping: manifest,
            previous: previous
        )

        try assetPipeline.saveManifest(
            manifest,
            to: outputURL.appendingPathComponent("asset-manifest.json").path
        )
    }

    private func configureAssetPipeline() {
        if config.features.minify {
            assetPipeline.cssOptions.minify = true
            assetPipeline.jsOptions.minify = true
        }
        assetPipeline.enableFingerprinting = config.features.fingerprint
    }

    /// 出力ツリーの HTML（と、パイプラインが作ったのではない CSS）の参照を、フィンガープリント
    /// 済みの名前に差し替える。
    ///
    /// アセットパイプライン自身が生成したファイルは**書き換えない**。書き換えるとパス2で確定した
    /// ハッシュがその中身を指さなくなる。具体的には、この時点ではマニフェストに全 CSS が載って
    /// いるため、パス2で解決を見送った `@import url("other.css")` がここで解決してしまう。
    private func rewriteAssetReferences(outputURL: URL) throws {
        let manifest = assetManifest
        guard !manifest.isEmpty else { return }
        let generated = manifest.outputPaths

        guard let walker = FileManager.default.enumerator(
            at: outputURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in walker {
            try Task.checkCancellation()
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }

            let ext = fileURL.pathExtension.lowercased()
            guard ext == "html" || ext == "htm" || ext == "css" else { continue }

            guard let relativePath = AssetPruner.relativePath(of: fileURL, under: outputURL),
                  !generated.contains(relativePath) else { continue }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let directory = AssetManifest.parentDirectory(of: relativePath)
            let rewritten = ext == "css"
                ? AssetReferenceRewriter.rewriteCSS(content, manifest: manifest, inDirectory: directory).content
                : AssetReferenceRewriter.rewriteHTML(content, manifest: manifest, inDirectory: directory)

            guard rewritten != content else { continue }
            try siteFileManager.writeFile(content: rewritten, to: fileURL)
        }
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

    /// Relative path of `path` under `base`, or `nil` when it is not under it.
    ///
    /// The boundary is a whole path component, never a bare string prefix: `content-extra`,
    /// `content-posts`, `contents` and `content2` are ordinary sibling names that all start with
    /// `content` without being anywhere inside it, and a prefix match would publish their pages
    /// at a URL made of whatever characters were left over.
    private static func pathRelative(_ path: String, to base: String) -> String? {
        let base = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard path != base else { return "" }
        guard path.hasPrefix(base + "/") else { return nil }
        return String(path.dropFirst(base.count + 1))
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

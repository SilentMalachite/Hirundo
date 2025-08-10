import Foundation

public class SiteGenerator {
    private let projectPath: String
    private let config: HirundoConfig
    private let markdownParser: MarkdownParser
    private let templateEngine: TemplateEngine
    private let fileManager: FileManager
    private let pluginManager: PluginManager
    private let assetPipeline: AssetPipeline
    
    public init(projectPath: String, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.projectPath = projectPath
        
        // Load configuration
        let configPath = URL(fileURLWithPath: projectPath).appendingPathComponent("config.yaml")
        self.config = try HirundoConfig.load(from: configPath)
        
        // Initialize components
        self.markdownParser = MarkdownParser()
        
        let templatesPath = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.templatesDirectory)
            .path
        self.templateEngine = TemplateEngine(templatesDirectory: templatesPath)
        
        // Configure template engine with site config
        templateEngine.configure(with: config.site)
        
        // Initialize plugin manager
        self.pluginManager = PluginManager()
        
        // Initialize asset pipeline
        self.assetPipeline = AssetPipeline(pluginManager: pluginManager)
        
        // Load and configure plugins
        try loadPlugins()
    }
    
    public func build(clean: Bool = false, includeDrafts: Bool = false) throws {
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
        
        // Clean output directory if requested
        if clean && fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        
        // Create output directory
        try TimeoutFileManager.createDirectory(at: outputURL.path, timeout: config.timeouts.directoryOperationTimeout)
        
        // Process content
        let contentURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.contentDirectory)
        
        var allPages: [Page] = []
        var allPosts: [Post] = []
        
        // Process all markdown files
        try processDirectory(
            contentURL,
            outputURL: outputURL,
            pages: &allPages,
            posts: &allPosts,
            includeDrafts: includeDrafts
        )
        
        // Generate archive, category, and tag pages if configured
        if config.blog.generateArchive {
            try generateArchivePage(posts: allPosts, outputURL: outputURL)
        }
        
        if config.blog.generateCategories {
            try generateCategoryPages(posts: allPosts, outputURL: outputURL)
        }
        
        if config.blog.generateTags {
            try generateTagPages(posts: allPosts, outputURL: outputURL)
        }
        
        // Process static files through asset pipeline
        let staticURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.staticDirectory)
        
        if fileManager.fileExists(atPath: staticURL.path) {
            // Configure asset pipeline based on config
            configureAssetPipeline()
            
            // Process assets through pipeline
            let manifest = try assetPipeline.processAssets(
                from: staticURL.path,
                to: outputURL.path
            )
            
            // Save manifest if fingerprinting is enabled
            if assetPipeline.enableFingerprinting {
                let manifestPath = outputURL.appendingPathComponent("asset-manifest.json").path
                try assetPipeline.saveManifest(manifest, to: manifestPath)
            }
        }
        
        // Execute after build hook
        try pluginManager.executeAfterBuild(buildContext: buildContext)
    }
    
    // New method for build with error recovery
    public func buildWithRecovery(clean: Bool = false, includeDrafts: Bool = false) throws -> BuildResult {
        let startTime = Date()
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
        
        // Clean output directory if requested
        if clean && fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        
        // Create output directory
        try TimeoutFileManager.createDirectory(at: outputURL.path, timeout: config.timeouts.directoryOperationTimeout)
        
        // Process content with error recovery
        let contentURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.contentDirectory)
        
        var allPages: [Page] = []
        var allPosts: [Post] = []
        var successfulPages: [SuccessfulPage] = []
        var failedPages: [FailedPage] = []
        
        // Process all markdown files with error recovery
        processDirectoryWithRecovery(
            contentURL,
            outputURL: outputURL,
            pages: &allPages,
            posts: &allPosts,
            successfulPages: &successfulPages,
            failedPages: &failedPages,
            includeDrafts: includeDrafts
        )
        
        // Generate archive, category, and tag pages if configured (with error recovery)
        if config.blog.generateArchive {
            do {
                try generateArchivePage(posts: allPosts, outputURL: outputURL)
            } catch {
                print("Warning: Failed to generate archive page: \(error.localizedDescription)")
            }
        }
        
        if config.blog.generateCategories {
            do {
                try generateCategoryPages(posts: allPosts, outputURL: outputURL)
            } catch {
                print("Warning: Failed to generate category pages: \(error.localizedDescription)")
            }
        }
        
        if config.blog.generateTags {
            do {
                try generateTagPages(posts: allPosts, outputURL: outputURL)
            } catch {
                print("Warning: Failed to generate tag pages: \(error.localizedDescription)")
            }
        }
        
        // Process static files through asset pipeline (with error recovery)
        let staticURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.staticDirectory)
        
        if fileManager.fileExists(atPath: staticURL.path) {
            do {
                // Configure asset pipeline based on config
                configureAssetPipeline()
                
                // Process assets through pipeline
                let manifest = try assetPipeline.processAssets(
                    from: staticURL.path,
                    to: outputURL.path
                )
                
                // Save manifest if fingerprinting is enabled
                if assetPipeline.enableFingerprinting {
                    let manifestPath = outputURL.appendingPathComponent("asset-manifest.json").path
                    try assetPipeline.saveManifest(manifest, to: manifestPath)
                }
            } catch {
                print("Warning: Failed to process static assets: \(error.localizedDescription)")
            }
        }
        
        // Execute after build hook
        try pluginManager.executeAfterBuild(buildContext: buildContext)
        
        let endTime = Date()
        
        // Create and return build result
        let result = BuildResult(
            successfulPages: successfulPages,
            failedPages: failedPages,
            totalProcessed: successfulPages.count + failedPages.count,
            startTime: startTime,
            endTime: endTime
        )
        
        // Print error summary if there were failures
        if !failedPages.isEmpty {
            print("\n\(result.errorSummary)")
        }
        
        return result
    }
    
    private func processDirectory(
        _ directoryURL: URL,
        outputURL: URL,
        pages: inout [Page],
        posts: inout [Post],
        includeDrafts: Bool
    ) throws {
        let contents = try TimeoutFileManager.listDirectory(
            at: directoryURL.path,
            timeout: config.timeouts.directoryOperationTimeout
        )
        
        for itemURL in contents {
            if itemURL.pathExtension == "md" {
                try processMarkdownFile(
                    itemURL,
                    outputURL: outputURL,
                    pages: &pages,
                    posts: &posts,
                    includeDrafts: includeDrafts
                )
            } else {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    try processDirectory(
                        itemURL,
                        outputURL: outputURL,
                        pages: &pages,
                        posts: &posts,
                        includeDrafts: includeDrafts
                    )
                }
            }
        }
    }
    
    private func processMarkdownFile(
        _ fileURL: URL,
        outputURL: URL,
        pages: inout [Page],
        posts: inout [Post],
        includeDrafts: Bool
    ) throws {
        let content = try TimeoutFileManager.readFile(at: fileURL.path, timeout: config.timeouts.fileReadTimeout)
        let result = try markdownParser.parse(content)
        
        // Skip drafts if not included
        if let draft = result.frontMatter?["draft"] as? Bool, draft, !includeDrafts {
            return
        }
        
        // Create content item for plugin processing
        let contentItem = ContentItem(
            path: fileURL.path,
            frontMatter: result.frontMatter ?? [:],
            content: content,
            type: fileURL.path.contains("/posts/") ? .post : .page
        )
        
        // Transform content through plugins
        let transformedContent = try pluginManager.transformContent(contentItem)
        
        // Determine if this is a post or page
        let isPost = fileURL.path.contains("/posts/")
        
        // Create output path
        let contentURL = URL(fileURLWithPath: projectPath).appendingPathComponent(config.build.contentDirectory)
        
        // Calculate relative path from content directory
        var relativePath: String
        
        // Get the standardized paths to handle /private prefix on macOS
        let standardizedFileURL = fileURL.standardizedFileURL
        let standardizedContentURL = contentURL.standardizedFileURL
        
        // Get the relative path from the content directory
        if let range = standardizedFileURL.path.range(of: standardizedContentURL.path) {
            relativePath = String(standardizedFileURL.path[range.upperBound...])
            if relativePath.hasPrefix("/") {
                relativePath = String(relativePath.dropFirst())
            }
        } else {
            // Fallback: use lastPathComponent
            relativePath = fileURL.deletingPathExtension().lastPathComponent
        }
        
        // Remove .md extension if still present
        if relativePath.hasSuffix(".md") {
            relativePath = String(relativePath.dropLast(3))
        }
        
        // Clean up any remaining path issues
        if relativePath.hasPrefix("/") {
            relativePath = String(relativePath.dropFirst())
        }
        
        // Sanitize the path to prevent path traversal attacks
        relativePath = sanitizePath(relativePath)
        
        let pageOutputURL: URL
        if relativePath == "index" {
            pageOutputURL = outputURL.appendingPathComponent("index.html")
        } else {
            pageOutputURL = outputURL
                .appendingPathComponent(relativePath)
                .appendingPathComponent("index.html")
        }
        
        // Create output directory
        try TimeoutFileManager.createDirectory(
            at: pageOutputURL.deletingLastPathComponent().path,
            timeout: config.timeouts.directoryOperationTimeout
        )
        
        // Prepare context with sanitized values to prevent XSS
        var context: [String: Any] = [
            "site": [
                "title": sanitizeForTemplate(config.site.title),
                "description": sanitizeForTemplate(config.site.description ?? ""),
                "url": sanitizeForTemplate(config.site.url),
                "language": sanitizeForTemplate(config.site.language ?? "en-US"),
                "author": [
                    "name": sanitizeForTemplate(config.site.author?.name ?? ""),
                    "email": sanitizeForTemplate(config.site.author?.email ?? "")
                ]
            ],
            "pages": pages.map { $0.context },
            "posts": posts.map { $0.context }
        ]
        
        // Parse and format content
        let renderedContent = renderMarkdownContent(result)
        
        if isPost {
            let post = try Post(
                url: relativePath,
                frontMatter: transformedContent.frontMatter,
                content: renderedContent
            )
            posts.append(post)
            
            context["page"] = post.context
            context["content"] = renderedContent
            
            // Add categories and tags to context
            if let categories = post.categories {
                context["categories"] = categories
            }
            if let tags = post.tags {
                context["tags"] = tags
            }
        } else {
            let page = Page(
                url: relativePath,
                frontMatter: transformedContent.frontMatter,
                content: renderedContent
            )
            pages.append(page)
            
            context["page"] = page.context
            context["content"] = renderedContent
        }
        
        // Enrich template data through plugins
        context = try pluginManager.enrichTemplateData(context)
        
        // Determine template
        let layout = result.frontMatter?["layout"] as? String ?? (isPost ? "post" : "default")
        let template = "\(layout).html"
        
        // Render and write
        do {
            let html = try templateEngine.render(template: template, context: context)
            try TimeoutFileManager.writeFile(content: html, to: pageOutputURL.path, timeout: config.timeouts.fileWriteTimeout)
        } catch let error as TemplateError {
            throw BuildError.templateError(error.localizedDescription)
        }
    }
    
    private func renderMarkdownContent(_ result: MarkdownParseResult) -> String {
        // Use the swift-markdown Document's built-in HTML rendering
        return result.document?.htmlString ?? ""
    }
    
    /// Sanitizes user input for safe inclusion in HTML templates
    /// Prevents XSS attacks by escaping dangerous HTML characters
    private func sanitizeForTemplate(_ text: String) -> String {
        var escaped = text
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&#39;")
        escaped = escaped.replacingOccurrences(of: "/", with: "&#47;")
        
        // Remove any null bytes which can bypass filters
        escaped = escaped.replacingOccurrences(of: "\0", with: "")
        
        // Remove any non-printable control characters except newlines and tabs
        let allowedControlChars = CharacterSet(charactersIn: "\n\r\t")
        let controlChars = CharacterSet.controlCharacters.subtracting(allowedControlChars)
        escaped = escaped.components(separatedBy: controlChars).joined()
        
        return escaped
    }
    
    private func escapeHtml(_ text: String) -> String {
        return sanitizeForTemplate(text)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#x27;")
            .replacingOccurrences(of: "/", with: "&#x2F;")
            .replacingOccurrences(of: "`", with: "&#x60;")
            .replacingOccurrences(of: "=", with: "&#x3D;")
    }
    
    private func escapeHtmlAttribute(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#x27;")
            .replacingOccurrences(of: "\n", with: "&#x0A;")
            .replacingOccurrences(of: "\r", with: "&#x0D;")
            .replacingOccurrences(of: "\t", with: "&#x09;")
    }
    
    private func generateArchivePage(posts: [Post], outputURL: URL) throws {
        let archiveURL = outputURL
            .appendingPathComponent("archive")
            .appendingPathComponent("index.html")
        
        try TimeoutFileManager.createDirectory(
            at: archiveURL.deletingLastPathComponent().path,
            timeout: config.timeouts.directoryOperationTimeout
        )
        
        let context: [String: Any] = [
            "site": siteContext,
            "page": [
                "title": "Archive",
                "url": "/archive"
            ],
            "posts": posts.sorted { $0.date ?? Date() > $1.date ?? Date() }.map { $0.context },
            "content": generateArchiveContent(posts: posts)
        ]
        
        do {
            let html = try templateEngine.render(template: "archive.html", context: context)
            try TimeoutFileManager.writeFile(content: html, to: archiveURL.path, timeout: config.timeouts.fileWriteTimeout)
        } catch {
            // If archive template doesn't exist, use default template
            let html = try templateEngine.render(template: "default.html", context: context)
            try TimeoutFileManager.writeFile(content: html, to: archiveURL.path, timeout: config.timeouts.fileWriteTimeout)
        }
    }
    
    private func generateCategoryPages(posts: [Post], outputURL: URL) throws {
        var categorizedPosts: [String: [Post]] = [:]
        
        for post in posts {
            if let categories = post.categories {
                for category in categories {
                    let slug = category.slugified
                    if categorizedPosts[slug] == nil {
                        categorizedPosts[slug] = []
                    }
                    categorizedPosts[slug]?.append(post)
                }
            }
        }
        
        for (categorySlug, categoryPosts) in categorizedPosts {
            let categoryURL = outputURL
                .appendingPathComponent("categories")
                .appendingPathComponent(categorySlug)
                .appendingPathComponent("index.html")
            
            try TimeoutFileManager.createDirectory(
                at: categoryURL.deletingLastPathComponent().path,
                timeout: config.timeouts.directoryOperationTimeout
            )
            
            let context: [String: Any] = [
                "site": siteContext,
                "page": [
                    "title": categoryPosts.first?.categories?.first(where: { $0.slugified == categorySlug }) ?? categorySlug,
                    "url": "/categories/\(categorySlug)"
                ],
                "posts": categoryPosts.sorted { $0.date ?? Date() > $1.date ?? Date() }.map { $0.context },
                "content": generateCategoryContent(category: categorySlug, posts: categoryPosts)
            ]
            
            do {
                let html = try templateEngine.render(template: "category.html", context: context)
                try TimeoutFileManager.writeFile(content: html, to: categoryURL.path, timeout: config.timeouts.fileWriteTimeout)
            } catch {
                // If category template doesn't exist, use default template
                let html = try templateEngine.render(template: "default.html", context: context)
                try TimeoutFileManager.writeFile(content: html, to: categoryURL.path, timeout: config.timeouts.fileWriteTimeout)
            }
        }
    }
    
    private func generateTagPages(posts: [Post], outputURL: URL) throws {
        var taggedPosts: [String: [Post]] = [:]
        
        for post in posts {
            if let tags = post.tags {
                for tag in tags {
                    let slug = tag.slugified
                    if taggedPosts[slug] == nil {
                        taggedPosts[slug] = []
                    }
                    taggedPosts[slug]?.append(post)
                }
            }
        }
        
        for (tagSlug, tagPosts) in taggedPosts {
            let tagURL = outputURL
                .appendingPathComponent("tags")
                .appendingPathComponent(tagSlug)
                .appendingPathComponent("index.html")
            
            try TimeoutFileManager.createDirectory(
                at: tagURL.deletingLastPathComponent().path,
                timeout: config.timeouts.directoryOperationTimeout
            )
            
            let context: [String: Any] = [
                "site": siteContext,
                "page": [
                    "title": tagPosts.first?.tags?.first(where: { $0.slugified == tagSlug }) ?? tagSlug,
                    "url": "/tags/\(tagSlug)"
                ],
                "posts": tagPosts.sorted { $0.date ?? Date() > $1.date ?? Date() }.map { $0.context },
                "content": generateTagContent(tag: tagSlug, posts: tagPosts)
            ]
            
            do {
                let html = try templateEngine.render(template: "tag.html", context: context)
                try TimeoutFileManager.writeFile(content: html, to: tagURL.path, timeout: config.timeouts.fileWriteTimeout)
            } catch {
                // If tag template doesn't exist, use default template
                let html = try templateEngine.render(template: "default.html", context: context)
                try TimeoutFileManager.writeFile(content: html, to: tagURL.path, timeout: config.timeouts.fileWriteTimeout)
            }
        }
    }
    
    private func configureAssetPipeline() {
        // Configure based on build configuration
        if let enableFingerprinting = config.build.enableAssetFingerprinting {
            assetPipeline.enableFingerprinting = enableFingerprinting
        }
        
        if let enableSourceMaps = config.build.enableSourceMaps {
            assetPipeline.enableSourceMaps = enableSourceMaps
        }
        
        // Set up default exclusion patterns
        assetPipeline.excludePatterns = [
            ".*",           // Hidden files
            "_*",           // Private files
            "*.tmp",        // Temporary files
            "*.log",        // Log files
            "Thumbs.db",    // Windows thumbnails
            ".DS_Store"     // macOS metadata
        ]
        
        // Add concatenation rules if needed
        if config.build.concatenateJS ?? false {
            assetPipeline.concatenationRules.append(
                AssetConcatenationRule(
                    pattern: "js/*.js",
                    output: "js/bundle.js",
                    separator: ";\n"
                )
            )
        }
        
        if config.build.concatenateCSS ?? false {
            assetPipeline.concatenationRules.append(
                AssetConcatenationRule(
                    pattern: "css/*.css",
                    output: "css/bundle.css",
                    separator: "\n"
                )
            )
        }
    }
    
    private var siteContext: [String: Any] {
        return [
            "title": config.site.title,
            "description": config.site.description ?? "",
            "url": config.site.url,
            "language": config.site.language ?? "en-US",
            "author": [
                "name": config.site.author?.name ?? "",
                "email": config.site.author?.email ?? ""
            ]
        ]
    }
    
    private func generateArchiveContent(posts: [Post]) -> String {
        // Simple implementation - in reality would use templates
        return "<ul>\n" +
            posts.map { "<li><a href=\"/posts/\($0.slug)\">\($0.title)</a> - \($0.formattedDate)</li>" }.joined(separator: "\n") +
            "\n</ul>"
    }
    
    private func generateCategoryContent(category: String, posts: [Post]) -> String {
        return "<h1>Category: \(category)</h1>\n<ul>\n" +
            posts.map { "<li><a href=\"/posts/\($0.slug)\">\($0.title)</a></li>" }.joined(separator: "\n") +
            "\n</ul>"
    }
    
    private func generateTagContent(tag: String, posts: [Post]) -> String {
        return "<h1>Tag: \(tag)</h1>\n<ul>\n" +
            posts.map { "<li><a href=\"/posts/\($0.slug)\">\($0.title)</a></li>" }.joined(separator: "\n") +
            "\n</ul>"
    }
}

// Helper models
struct Page {
    let url: String
    let title: String
    let content: String
    let frontMatter: [String: Any]
    
    init(url: String, frontMatter: [String: Any], content: String) {
        self.url = url
        self.frontMatter = frontMatter
        self.title = frontMatter["title"] as? String ?? "Untitled"
        self.content = content
    }
    
    var context: [String: Any] {
        var ctx: [String: Any] = [:]
        
        // Sanitize all frontMatter values to prevent XSS
        for (key, value) in frontMatter {
            if let stringValue = value as? String {
                ctx[key] = Page.sanitizeForTemplate(stringValue)
            } else if let arrayValue = value as? [String] {
                ctx[key] = arrayValue.map { Page.sanitizeForTemplate($0) }
            } else if let dictValue = value as? [String: String] {
                ctx[key] = dictValue.mapValues { Page.sanitizeForTemplate($0) }
            } else {
                ctx[key] = value
            }
        }
        
        ctx["url"] = "/" + url
        ctx["title"] = Page.sanitizeForTemplate(title)
        return ctx
    }
    
    private static func sanitizeForTemplate(_ text: String) -> String {
        var escaped = text
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&#39;")
        escaped = escaped.replacingOccurrences(of: "/", with: "&#47;")
        escaped = escaped.replacingOccurrences(of: "\0", with: "")
        
        let allowedControlChars = CharacterSet(charactersIn: "\n\r\t")
        let controlChars = CharacterSet.controlCharacters.subtracting(allowedControlChars)
        escaped = escaped.components(separatedBy: controlChars).joined()
        
        return escaped
    }
}

struct Post {
    let url: String
    let title: String
    let content: String
    let date: Date?
    let categories: [String]?
    let tags: [String]?
    let frontMatter: [String: Any]
    
    init(url: String, frontMatter: [String: Any], content: String) throws {
        self.url = url
        self.frontMatter = frontMatter
        self.title = frontMatter["title"] as? String ?? "Untitled"
        self.content = content
        
        // Parse date
        if let dateValue = frontMatter["date"] {
            if let date = dateValue as? Date {
                self.date = date
            } else if let dateString = dateValue as? String {
                let formatter = ISO8601DateFormatter()
                self.date = formatter.date(from: dateString)
            } else {
                self.date = nil
            }
        } else {
            self.date = nil
        }
        
        // Sanitize categories and tags to prevent XSS
        if let rawCategories = frontMatter["categories"] as? [String] {
            self.categories = rawCategories.map { Post.sanitizeForTemplate($0) }
        } else {
            self.categories = nil
        }
        
        if let rawTags = frontMatter["tags"] as? [String] {
            self.tags = rawTags.map { Post.sanitizeForTemplate($0) }
        } else {
            self.tags = nil
        }
    }
    
    private static func sanitizeForTemplate(_ text: String) -> String {
        var escaped = text
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&#39;")
        escaped = escaped.replacingOccurrences(of: "/", with: "&#47;")
        escaped = escaped.replacingOccurrences(of: "\0", with: "")
        
        let allowedControlChars = CharacterSet(charactersIn: "\n\r\t")
        let controlChars = CharacterSet.controlCharacters.subtracting(allowedControlChars)
        escaped = escaped.components(separatedBy: controlChars).joined()
        
        return escaped
    }
    
    var slug: String {
        return url.components(separatedBy: "/").last ?? "untitled"
    }
    
    var formattedDate: String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.string(from: date)
    }
    
    var context: [String: Any] {
        var ctx: [String: Any] = [:]
        
        // Sanitize all frontMatter values to prevent XSS
        for (key, value) in frontMatter {
            if let stringValue = value as? String {
                ctx[key] = Post.sanitizeForTemplate(stringValue)
            } else if let arrayValue = value as? [String] {
                ctx[key] = arrayValue.map { Post.sanitizeForTemplate($0) }
            } else if let dictValue = value as? [String: String] {
                ctx[key] = dictValue.mapValues { Post.sanitizeForTemplate($0) }
            } else {
                ctx[key] = value
            }
        }
        
        ctx["url"] = "/" + url
        ctx["title"] = Post.sanitizeForTemplate(title)
        if let date = date {
            ctx["date"] = date
        }
        if let categories = categories {
            ctx["categories"] = categories  // Already sanitized in init
        }
        if let tags = tags {
            ctx["tags"] = tags  // Already sanitized in init
        }
        return ctx
    }
}

extension String {
    var slugified: String {
        return slugify()
    }
}

// MARK: - Plugin Support

// MARK: - Build Result Types

public extension SiteGenerator {
    struct BuildResult {
        public let successfulPages: [SuccessfulPage]
        public let failedPages: [FailedPage]
        public let totalProcessed: Int
        public let startTime: Date
        public let endTime: Date
        
        public var isCompleteSuccess: Bool {
            return failedPages.isEmpty
        }
        
        public var errorSummary: String {
            var summary = "Build completed with errors\n"
            summary += "========================\n\n"
            summary += "Total files processed: \(totalProcessed)\n"
            summary += "Successful: \(successfulPages.count)\n"
            summary += "Failed: \(failedPages.count)\n"
            summary += "Build time: \(String(format: "%.2f", endTime.timeIntervalSince(startTime)))s\n"
            
            if !failedPages.isEmpty {
                summary += "\nErrors:\n"
                summary += "-------\n"
                for (index, failedPage) in failedPages.enumerated() {
                    let filename = URL(fileURLWithPath: failedPage.path).lastPathComponent
                    summary += "\n\(index + 1). \(filename)\n"
                    summary += "   Error: \(failedPage.error.localizedDescription)\n"
                    summary += "   Path: \(failedPage.path)\n"
                }
            }
            
            return summary
        }
    }
    
    struct SuccessfulPage {
        public let path: String
        public let outputPath: String
        public let title: String
    }
    
    struct FailedPage {
        public let path: String
        public let error: Error
        public let stage: BuildStage
    }
    
    enum BuildStage {
        case reading
        case parsing
        case transforming
        case rendering
        case writing
    }
}

extension SiteGenerator {
    private func processDirectoryWithRecovery(
        _ directoryURL: URL,
        outputURL: URL,
        pages: inout [Page],
        posts: inout [Post],
        successfulPages: inout [SuccessfulPage],
        failedPages: inout [FailedPage],
        includeDrafts: Bool
    ) {
        do {
            let contents = try TimeoutFileManager.listDirectory(
                at: directoryURL.path,
                timeout: config.timeouts.directoryOperationTimeout
            )
            
            for itemURL in contents {
                if itemURL.pathExtension == "md" {
                    processMarkdownFileWithRecovery(
                        itemURL,
                        outputURL: outputURL,
                        pages: &pages,
                        posts: &posts,
                        successfulPages: &successfulPages,
                        failedPages: &failedPages,
                        includeDrafts: includeDrafts
                    )
                } else {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                        processDirectoryWithRecovery(
                            itemURL,
                            outputURL: outputURL,
                            pages: &pages,
                            posts: &posts,
                            successfulPages: &successfulPages,
                            failedPages: &failedPages,
                            includeDrafts: includeDrafts
                        )
                    }
                }
            }
        } catch {
            // If we can't even read the directory, add a failure for the directory itself
            failedPages.append(FailedPage(
                path: directoryURL.path,
                error: error,
                stage: .reading
            ))
        }
    }
    
    private func processMarkdownFileWithRecovery(
        _ fileURL: URL,
        outputURL: URL,
        pages: inout [Page],
        posts: inout [Post],
        successfulPages: inout [SuccessfulPage],
        failedPages: inout [FailedPage],
        includeDrafts: Bool
    ) {
        var currentStage: BuildStage = .reading
        
        do {
            // Stage 1: Reading
            currentStage = .reading
            let content = try TimeoutFileManager.readFile(at: fileURL.path, timeout: config.timeouts.fileReadTimeout)
            
            // Stage 2: Parsing
            currentStage = .parsing
            let result = try markdownParser.parse(content)
            
            // Skip drafts if not included
            if let draft = result.frontMatter?["draft"] as? Bool, draft, !includeDrafts {
                return
            }
            
            // Stage 3: Transforming
            currentStage = .transforming
            
            // Create content item for plugin processing
            let contentItem = ContentItem(
                path: fileURL.path,
                frontMatter: result.frontMatter ?? [:],
                content: content,
                type: fileURL.path.contains("/posts/") ? .post : .page
            )
            
            // Transform content through plugins
            let transformedContent = try pluginManager.transformContent(contentItem)
            
            // Determine if this is a post or page
            let isPost = fileURL.path.contains("/posts/")
            
            // Create output path
            let contentURL = URL(fileURLWithPath: projectPath).appendingPathComponent(config.build.contentDirectory)
            
            // Calculate relative path from content directory
            var relativePath: String
            
            // Get the standardized paths to handle /private prefix on macOS
            let standardizedFileURL = fileURL.standardizedFileURL
            let standardizedContentURL = contentURL.standardizedFileURL
            
            // Get the relative path from the content directory
            if let range = standardizedFileURL.path.range(of: standardizedContentURL.path) {
                relativePath = String(standardizedFileURL.path[range.upperBound...])
                if relativePath.hasPrefix("/") {
                    relativePath = String(relativePath.dropFirst())
                }
            } else {
                // Fallback: use lastPathComponent
                relativePath = fileURL.deletingPathExtension().lastPathComponent
            }
            
            // Remove .md extension if still present
            if relativePath.hasSuffix(".md") {
                relativePath = String(relativePath.dropLast(3))
            }
            
            // Clean up any remaining path issues
            if relativePath.hasPrefix("/") {
                relativePath = String(relativePath.dropFirst())
            }
            
            // Sanitize the path to prevent path traversal attacks
            relativePath = sanitizePath(relativePath)
            
            let pageOutputURL: URL
            if relativePath == "index" {
                pageOutputURL = outputURL.appendingPathComponent("index.html")
            } else {
                pageOutputURL = outputURL
                    .appendingPathComponent(relativePath)
                    .appendingPathComponent("index.html")
            }
            
            // Create output directory
            try TimeoutFileManager.createDirectory(
                at: pageOutputURL.deletingLastPathComponent().path,
                timeout: config.timeouts.directoryOperationTimeout
            )
            
            // Stage 4: Rendering
            currentStage = .rendering
            
            // Prepare context
            var context: [String: Any] = [
                "site": [
                    "title": config.site.title,
                    "description": config.site.description ?? "",
                    "url": config.site.url,
                    "language": config.site.language ?? "en-US",
                    "author": [
                        "name": config.site.author?.name ?? "",
                        "email": config.site.author?.email ?? ""
                    ]
                ],
                "pages": pages.map { $0.context },
                "posts": posts.map { $0.context }
            ]
            
            // Parse and format content
            let renderedContent = renderMarkdownContent(result)
            
            var pageTitle = ""
            
            if isPost {
                let post = try Post(
                    url: relativePath,
                    frontMatter: transformedContent.frontMatter,
                    content: renderedContent
                )
                posts.append(post)
                pageTitle = post.title
                
                context["page"] = post.context
                context["content"] = renderedContent
                
                // Add categories and tags to context
                if let categories = post.categories {
                    context["categories"] = categories
                }
                if let tags = post.tags {
                    context["tags"] = tags
                }
            } else {
                let page = Page(
                    url: relativePath,
                    frontMatter: transformedContent.frontMatter,
                    content: renderedContent
                )
                pages.append(page)
                pageTitle = page.title
                
                context["page"] = page.context
                context["content"] = renderedContent
            }
            
            // Enrich template data through plugins
            context = try pluginManager.enrichTemplateData(context)
            
            // Determine template
            let layout = result.frontMatter?["layout"] as? String ?? (isPost ? "post" : "default")
            let template = "\(layout).html"
            
            // Render and write
            do {
                let html = try templateEngine.render(template: template, context: context)
                
                // Stage 5: Writing
                currentStage = .writing
                try TimeoutFileManager.writeFile(content: html, to: pageOutputURL.path, timeout: config.timeouts.fileWriteTimeout)
                
                // Success! Add to successful pages
                successfulPages.append(SuccessfulPage(
                    path: fileURL.path,
                    outputPath: pageOutputURL.path,
                    title: pageTitle
                ))
            } catch let error as TemplateError {
                throw BuildError.templateError(error.localizedDescription)
            }
        } catch {
            // Add to failed pages with the current stage
            failedPages.append(FailedPage(
                path: fileURL.path,
                error: error,
                stage: currentStage
            ))
            
            // Log the error for debugging
            print("Error processing \(fileURL.lastPathComponent) at stage \(currentStage): \(error.localizedDescription)")
        }
    }
}

extension SiteGenerator {
    private func loadPlugins() throws {
        // Initialize plugin context
        let context = PluginContext(
            projectPath: projectPath,
            config: config
        )
        
        // Load built-in plugins based on configuration
        if !config.plugins.isEmpty {
            for pluginConfig in config.plugins {
                if pluginConfig.enabled {
                    try loadPlugin(pluginConfig, context: context)
                }
            }
        }
        
        // Load plugins from plugins directory
        let pluginsDir = URL(fileURLWithPath: projectPath).appendingPathComponent("plugins").path
        try pluginManager.loadPlugins(from: pluginsDir)
        
        // Initialize all plugins
        try pluginManager.initializeAll(context: context)
    }
    
    private func loadPlugin(_ pluginConfig: HirundoConfig.PluginConfiguration, context: PluginContext) throws {
        let pluginName = pluginConfig.name.lowercased()
        
        switch pluginName {
        case "rss", "rssplugin":
            let plugin = RSSPlugin()
            try pluginManager.register(plugin)
            try configurePlugin(plugin, with: pluginConfig)
            
        case "sitemap", "sitemapplugin":
            let plugin = SitemapPlugin()
            try pluginManager.register(plugin)
            try configurePlugin(plugin, with: pluginConfig)
            
        case "minify", "minifyplugin":
            let plugin = MinifyPlugin()
            try pluginManager.register(plugin)
            try configurePlugin(plugin, with: pluginConfig)
            
        case "search", "searchindex", "searchindexplugin":
            let plugin = SearchIndexPlugin()
            try pluginManager.register(plugin)
            try configurePlugin(plugin, with: pluginConfig)
            
        default:
            // Try to load from built-in plugins
            if let plugin = PluginLoader.loadBuiltIn(named: pluginConfig.name) {
                try pluginManager.register(plugin)
                try configurePlugin(plugin, with: pluginConfig)
            }
        }
    }
    
    private func configurePlugin(_ plugin: Plugin, with config: HirundoConfig.PluginConfiguration) throws {
        let pluginConfig = PluginConfig(
            name: plugin.metadata.name,  // Use the plugin's actual name
            enabled: config.enabled,
            settings: config.settings
        )
        try pluginManager.configure(pluginNamed: plugin.metadata.name, with: pluginConfig)
    }
    
    // MARK: - Security Utilities
    
    /// Sanitizes a file path to prevent path traversal attacks
    /// - Parameter path: The path to sanitize
    /// - Returns: A sanitized path safe for file operations
    private func sanitizePath(_ path: String) -> String {
        // Use centralized path sanitizer with caching
        return PathSanitizer.sanitize(path)
    }
    
    /// Validates that a path is safe and within the expected directory
    /// - Parameters:
    ///   - path: The path to validate
    ///   - baseDirectory: The base directory that should contain the path
    /// - Returns: True if the path is safe, false otherwise
    private func isPathSafe(_ path: String, withinBaseDirectory baseDirectory: String) -> Bool {
        // Use centralized path validator
        return PathSanitizer.isPathSafe(path, withinBaseDirectory: baseDirectory)
    }
}
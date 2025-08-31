import Foundation

// Template rendering separated from SiteGenerator
public class SiteTemplateRenderer {
    public let templateEngine: TemplateEngine
    private let config: HirundoConfig
    
    // Component managers
    private let contextBuilder: TemplateContextBuilder
    private let cacheManager: TemplateCacheManager
    private let htmlGenerator: DefaultHTMLGenerator
    
    public init(
        templatesDirectory: String,
        config: HirundoConfig
    ) {
        self.config = config
        self.templateEngine = TemplateEngine(templatesDirectory: templatesDirectory)
        
        // Initialize component managers
        self.contextBuilder = TemplateContextBuilder(config: config)
        self.cacheManager = TemplateCacheManager()
        self.htmlGenerator = DefaultHTMLGenerator()
        
        // Configure template engine with site config
        templateEngine.configure(with: config.site)
    }
    
    // Render content with template
    public func renderContent(
        _ content: ProcessedContent,
        htmlContent: String,
        allPages: [Page],
        allPosts: [Post]
    ) async throws -> String {
        // Generate cache key based on content and dependencies
        let cacheKey = cacheManager.generateCacheKey(
            for: content,
            htmlContent: htmlContent,
            pagesCount: allPages.count,
            postsCount: allPosts.count
        )
        
        // Try to retrieve from cache first
        if let cachedResult = await cacheManager.retrieve(key: cacheKey) {
            return cachedResult
        }
        
        // Prepare template context
        let context = contextBuilder.buildContext(
            for: content,
            htmlContent: htmlContent,
            allPages: allPages,
            allPosts: allPosts
        )
        
        // Determine template to use
        let templateName = content.metadata.template ?? (content.type == .post ? "post.html" : "default.html")
        
        // Render with template
        let renderedContent = try templateEngine.render(template: templateName, context: context)
        
        // Cache the rendered result
        await cacheManager.store(
            key: cacheKey,
            value: renderedContent,
            content: content,
            pagesCount: allPages.count,
            postsCount: allPosts.count
        )
        
        return renderedContent
    }
    
    // Render archive page
    public func renderArchivePage(posts: [Post]) throws -> String {
        let context = contextBuilder.buildArchiveContext(posts: posts)
        do {
            return try templateEngine.render(template: "archive.html", context: context)
        } catch {
            // Fallback to a minimal built-in archive page if template not found
            return htmlGenerator.generateArchiveHTML(context: context)
        }
    }
    
    // Render category page
    public func renderCategoryPage(category: String, posts: [Post]) throws -> String {
        let context = contextBuilder.buildCategoryContext(category: category, posts: posts)
        do {
            return try templateEngine.render(template: "category.html", context: context)
        } catch {
            return htmlGenerator.generateCategoryHTML(context: context)
        }
    }
    
    // Render tag page
    public func renderTagPage(tag: String, posts: [Post]) throws -> String {
        let context = contextBuilder.buildTagContext(tag: tag, posts: posts)
        do {
            return try templateEngine.render(template: "tag.html", context: context)
        } catch {
            return htmlGenerator.generateTagHTML(context: context)
        }
    }
    
    // Clear template cache
    public func clearTemplateEngineCache() {
        templateEngine.clearCache()
    }
    
    // MARK: - Cache Management
    
    /// Invalidates cache for a specific content piece
    public func invalidateCache(for content: ProcessedContent) async {
        await cacheManager.invalidateCache(for: content)
    }
    
    /// Clears all template cache
    public func clearCache() async {
        await cacheManager.clearCache()
    }
    
    /// Gets cache statistics
    public func getCacheStatistics() async -> MemoryEfficientCacheManager.CacheStatistics {
        return await cacheManager.getCacheStatistics()
    }
}

// Extension to convert ContentMetadata to dictionary
extension ContentMetadata {
    func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "title": title,
            "date": date
        ]
        
        if let description = description {
            dict["description"] = description
        }
        
        if let author = author {
            dict["author"] = author
        }
        
        if !categories.isEmpty {
            dict["categories"] = categories
        }
        
        if !tags.isEmpty {
            dict["tags"] = tags
        }
        
        if let template = template {
            dict["template"] = template
        }
        
        if let slug = slug {
            dict["slug"] = slug
        }
        
        return dict
    }
}

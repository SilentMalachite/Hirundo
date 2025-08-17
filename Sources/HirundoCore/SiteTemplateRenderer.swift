import Foundation

// Template rendering separated from SiteGenerator
public class SiteTemplateRenderer {
    public let templateEngine: TemplateEngine
    private let config: HirundoConfig
    private let securityValidator: SecurityValidator
    private let cacheManager: MemoryEfficientCacheManager
    
    public init(
        templatesDirectory: String,
        config: HirundoConfig,
        securityValidator: SecurityValidator
    ) {
        self.config = config
        self.securityValidator = securityValidator
        self.templateEngine = TemplateEngine(templatesDirectory: templatesDirectory)
        
        // Initialize cache manager
        self.cacheManager = MemoryEfficientCacheManager()
        
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
        let cacheKey = generateCacheKey(
            for: content,
            htmlContent: htmlContent,
            pagesCount: allPages.count,
            postsCount: allPosts.count
        )
        
        // Try to retrieve from cache first
        if let cachedData = await cacheManager.retrieve(key: cacheKey),
           let cachedResult = String(data: cachedData, encoding: .utf8) {
            return cachedResult
        }
        // Prepare template context
        var context: [String: Any] = [
            "site": prepareSiteContext(),
            "content": securityValidator.sanitizeForTemplate(htmlContent),
            "pages": allPages.map { preparePageContext($0) },
            "posts": allPosts.map { preparePostContext($0) }
        ]
        
        // Add page/post specific context
        switch content.type {
        case .page:
            context["page"] = preparePageContext(from: content)
        case .post:
            context["post"] = preparePostContext(from: content)
            context["categories"] = prepareCategoriesContext(from: allPosts)
            context["tags"] = prepareTagsContext(from: allPosts)
        }
        
        // Add metadata to context
        for (key, value) in content.metadata.asDictionary() {
            if let stringValue = value as? String {
                context[key] = securityValidator.sanitizeForTemplate(stringValue)
            } else {
                context[key] = value
            }
        }
        
        // Determine template to use
        let templateName = content.metadata.template ?? (content.type == .post ? "post.html" : "default.html")
        
        // Render with template
        let renderedContent = try templateEngine.render(template: templateName, context: context)
        
        // Cache the rendered result
        if let renderedData = renderedContent.data(using: .utf8) {
            let dependencies = Set([
                content.url.path,
                templateName,
                "pages_\(allPages.count)",
                "posts_\(allPosts.count)"
            ])
            
            await cacheManager.store(
                key: cacheKey,
                value: renderedData,
                dependencies: dependencies
            )
        }
        
        return renderedContent
    }
    
    // Render archive page
    public func renderArchivePage(posts: [Post]) throws -> String {
        let context: [String: Any] = [
            "site": prepareSiteContext(),
            "posts": posts.map { preparePostContext($0) },
            "title": "Archive"
        ]
        
        return try templateEngine.render(template: "archive.html", context: context)
    }
    
    // Render category page
    public func renderCategoryPage(category: String, posts: [Post]) throws -> String {
        let context: [String: Any] = [
            "site": prepareSiteContext(),
            "category": securityValidator.sanitizeForTemplate(category),
            "posts": posts.map { preparePostContext($0) },
            "title": "Category: \(category)"
        ]
        
        return try templateEngine.render(template: "category.html", context: context)
    }
    
    // Render tag page
    public func renderTagPage(tag: String, posts: [Post]) throws -> String {
        let context: [String: Any] = [
            "site": prepareSiteContext(),
            "tag": securityValidator.sanitizeForTemplate(tag),
            "posts": posts.map { preparePostContext($0) },
            "title": "Tag: \(tag)"
        ]
        
        return try templateEngine.render(template: "tag.html", context: context)
    }
    
    // Clear template cache
    public func clearTemplateEngineCache() {
        templateEngine.clearCache()
    }
    
    // Prepare site context for templates
    private func prepareSiteContext() -> [String: Any] {
        return [
            "title": securityValidator.sanitizeForTemplate(config.site.title),
            "description": securityValidator.sanitizeForTemplate(config.site.description ?? ""),
            "url": config.site.url,
            "language": config.site.language ?? "en",
            "author": prepareAuthorContext()
        ]
    }
    
    // Prepare author context
    private func prepareAuthorContext() -> [String: Any] {
        guard let author = config.site.author else {
            return [:]
        }
        
        return [
            "name": securityValidator.sanitizeForTemplate(author.name),
            "email": securityValidator.sanitizeForTemplate(author.email ?? "")
        ]
    }
    
    // Prepare page context from processed content
    private func preparePageContext(from content: ProcessedContent) -> [String: Any] {
        return [
            "title": securityValidator.sanitizeForTemplate(content.metadata.title),
            "description": securityValidator.sanitizeForTemplate(content.metadata.description ?? ""),
            "url": content.url.path,
            "slug": content.metadata.slug ?? content.url.deletingPathExtension().lastPathComponent
        ]
    }
    
    // Prepare page context from Page model
    private func preparePageContext(_ page: Page) -> [String: Any] {
        return [
            "title": securityValidator.sanitizeForTemplate(page.title),
            "description": securityValidator.sanitizeForTemplate(page.description ?? ""),
            "url": page.url,
            "slug": page.slug
        ]
    }
    
    // Prepare post context from processed content
    private func preparePostContext(from content: ProcessedContent) -> [String: Any] {
        return [
            "title": securityValidator.sanitizeForTemplate(content.metadata.title),
            "description": securityValidator.sanitizeForTemplate(content.metadata.description ?? ""),
            "date": content.metadata.date,
            "author": securityValidator.sanitizeForTemplate(content.metadata.author ?? ""),
            "categories": content.metadata.categories.map { securityValidator.sanitizeForTemplate($0) },
            "tags": content.metadata.tags.map { securityValidator.sanitizeForTemplate($0) },
            "url": content.url.path,
            "slug": content.metadata.slug ?? content.url.deletingPathExtension().lastPathComponent
        ]
    }
    
    // Prepare post context from Post model
    private func preparePostContext(_ post: Post) -> [String: Any] {
        return [
            "title": securityValidator.sanitizeForTemplate(post.title),
            "description": securityValidator.sanitizeForTemplate(post.description ?? ""),
            "date": post.date,
            "author": securityValidator.sanitizeForTemplate(post.author ?? ""),
            "categories": post.categories.map { securityValidator.sanitizeForTemplate($0) },
            "tags": post.tags.map { securityValidator.sanitizeForTemplate($0) },
            "url": post.url,
            "slug": post.slug
        ]
    }
    
    // Prepare categories context
    private func prepareCategoriesContext(from posts: [Post]) -> [String: [Post]] {
        var categories: [String: [Post]] = [:]
        
        for post in posts {
            for category in post.categories {
                if categories[category] == nil {
                    categories[category] = []
                }
                categories[category]?.append(post)
            }
        }
        
        // Sort posts in each category by date
        for (category, _) in categories {
            categories[category]?.sort { $0.date > $1.date }
        }
        
        return categories
    }
    
    // Prepare tags context
    private func prepareTagsContext(from posts: [Post]) -> [String: [Post]] {
        var tags: [String: [Post]] = [:]
        
        for post in posts {
            for tag in post.tags {
                if tags[tag] == nil {
                    tags[tag] = []
                }
                tags[tag]?.append(post)
            }
        }
        
        // Sort posts in each tag by date
        for (tag, _) in tags {
            tags[tag]?.sort { $0.date > $1.date }
        }
        
        return tags
    }
    
    // MARK: - Cache Management
    
    /// Generates a cache key for template rendering
    private func generateCacheKey(
        for content: ProcessedContent,
        htmlContent: String,
        pagesCount: Int,
        postsCount: Int
    ) -> String {
        // Create a hash-based cache key to ensure consistency
        let keyComponents = [
            content.url.path,
            content.metadata.title,
            String(content.metadata.date.timeIntervalSince1970),
            content.metadata.template ?? "default",
            String(pagesCount),
            String(postsCount),
            String(htmlContent.count) // Use content length as a simple hash
        ]
        
        let combinedKey = keyComponents.joined(separator: "_")
        return "template_\(combinedKey.hashValue)"
    }
    
    /// Invalidates cache for a specific content piece
    public func invalidateCache(for content: ProcessedContent) async {
        let pattern = "template_*\(content.url.path)*"
        await cacheManager.invalidatePattern(pattern)
    }
    
    /// Clears all template cache
    public func clearCache() async {
        await cacheManager.clear()
    }
    
    /// Gets cache statistics
    public func getCacheStatistics() async -> MemoryEfficientCacheManager.CacheStatistics {
        return await cacheManager.getStatistics()
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
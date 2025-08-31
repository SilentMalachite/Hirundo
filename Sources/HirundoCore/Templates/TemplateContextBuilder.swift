import Foundation

/// Builds template context for rendering
public class TemplateContextBuilder {
    private let config: HirundoConfig
    
    public init(config: HirundoConfig) {
        self.config = config
    }
    
    /// Builds context for content rendering
    public func buildContext(
        for content: ProcessedContent,
        htmlContent: String,
        allPages: [Page],
        allPosts: [Post]
    ) -> [String: Any] {
        var context: [String: Any] = [
            "site": prepareSiteContext(),
            "content": htmlContent,
            "pages": allPages.map { preparePageContext($0) },
            "posts": allPosts.map { preparePostContext($0) }
        ]
        
        // Add page/post specific context
        switch content.type {
        case .page:
            context["page"] = preparePageContext(from: content)
        case .post:
            context["page"] = preparePostContext(from: content)
            context["categories"] = prepareCategoriesContext(from: allPosts)
            context["tags"] = prepareTagsContext(from: allPosts)
        }
        
        
        
        return context
    }
    
    /// Builds context for archive page
    public func buildArchiveContext(posts: [Post]) -> [String: Any] {
        return [
            "site": prepareSiteContext(),
            "posts": posts.map { preparePostContext($0) },
            "title": "Archive"
        ]
    }
    
    /// Builds context for category page
    public func buildCategoryContext(category: String, posts: [Post]) -> [String: Any] {
        return [
            "site": prepareSiteContext(),
            "category": category,
            "posts": posts.map { preparePostContext($0) },
            "title": "Category: \(category)"
        ]
    }
    
    /// Builds context for tag page
    public func buildTagContext(tag: String, posts: [Post]) -> [String: Any] {
        return [
            "site": prepareSiteContext(),
            "tag": tag,
            "posts": posts.map { preparePostContext($0) },
            "title": "Tag: \(tag)"
        ]
    }
    
    // MARK: - Private Methods
    
    /// Prepares site context for templates
    private func prepareSiteContext() -> [String: Any] {
        return [
            "title": config.site.title,
            "description": config.site.description ?? "",
            "url": config.site.url,
            "language": config.site.language ?? "en",
            "author": prepareAuthorContext()
        ]
    }
    
    /// Prepares author context
    private func prepareAuthorContext() -> [String: Any] {
        guard let author = config.site.author else {
            return [:]
        }
        
        return [
            "name": author.name,
            "email": author.email ?? ""
        ]
    }
    
    /// Prepares page context from processed content
    private func preparePageContext(from content: ProcessedContent) -> [String: Any] {
        return [
            "title": content.metadata.title,
            "description": content.metadata.description ?? "",
            "url": content.url.path,
            "slug": content.metadata.slug ?? content.url.deletingPathExtension().lastPathComponent
        ]
    }
    
    /// Prepares page context from Page model
    private func preparePageContext(_ page: Page) -> [String: Any] {
        return [
            "title": page.title,
            "description": page.description ?? "",
            "url": page.url,
            "slug": page.slug
        ]
    }
    
    /// Prepares post context from processed content
    private func preparePostContext(from content: ProcessedContent) -> [String: Any] {
        return [
            "title": content.metadata.title,
            "description": content.metadata.description ?? "",
            "date": content.metadata.date,
            "author": content.metadata.author ?? "",
            "categories": content.metadata.categories,
            "tags": content.metadata.tags,
            "url": content.url.path,
            "slug": content.metadata.slug ?? content.url.deletingPathExtension().lastPathComponent
        ]
    }
    
    /// Prepares post context from Post model
    private func preparePostContext(_ post: Post) -> [String: Any] {
        return [
            "title": post.title,
            "description": post.description ?? "",
            "date": post.date,
            "author": post.author ?? "",
            "categories": post.categories,
            "tags": post.tags,
            "url": post.url,
            "slug": post.slug
        ]
    }
    
    /// Prepares categories context
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
    
    /// Prepares tags context
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
}
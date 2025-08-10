import Foundation

// Archive, category, and tag page generation separated from SiteGenerator
public class ArchiveGenerator {
    private let fileManager: SiteFileManager
    private let templateRenderer: SiteTemplateRenderer
    private let config: HirundoConfig
    
    public init(
        fileManager: SiteFileManager,
        templateRenderer: SiteTemplateRenderer,
        config: HirundoConfig
    ) {
        self.fileManager = fileManager
        self.templateRenderer = templateRenderer
        self.config = config
    }
    
    // Generate archive page
    public func generateArchivePage(posts: [Post], outputURL: URL) throws {
        guard config.blog.generateArchive else { return }
        
        // Sort posts by date (newest first)
        let sortedPosts = posts.sorted { $0.date > $1.date }
        
        // Create archive directory
        let archiveDir = outputURL.appendingPathComponent("archive")
        try fileManager.createDirectory(at: archiveDir)
        
        // Render archive page
        let html = try templateRenderer.renderArchivePage(posts: sortedPosts)
        
        // Write archive index
        let archiveIndex = archiveDir.appendingPathComponent("index.html")
        try fileManager.writeFile(content: html, to: archiveIndex)
        
        // Generate paginated archive if needed
        if config.blog.postsPerPage > 0 && posts.count > config.blog.postsPerPage {
            try generatePaginatedArchive(posts: sortedPosts, archiveDir: archiveDir)
        }
    }
    
    // Generate category pages
    public func generateCategoryPages(posts: [Post], outputURL: URL) throws {
        guard config.blog.generateCategories else { return }
        
        // Group posts by category
        let categorizedPosts = groupPostsByCategory(posts)
        
        // Create categories directory
        let categoriesDir = outputURL.appendingPathComponent("categories")
        try fileManager.createDirectory(at: categoriesDir)
        
        // Generate a page for each category
        for (category, categoryPosts) in categorizedPosts {
            try generateCategoryPage(
                category: category,
                posts: categoryPosts,
                categoriesDir: categoriesDir
            )
        }
        
        // Generate categories index page
        try generateCategoriesIndex(categories: Array(categorizedPosts.keys), outputDir: categoriesDir)
    }
    
    // Generate tag pages
    public func generateTagPages(posts: [Post], outputURL: URL) throws {
        guard config.blog.generateTags else { return }
        
        // Group posts by tag
        let taggedPosts = groupPostsByTag(posts)
        
        // Create tags directory
        let tagsDir = outputURL.appendingPathComponent("tags")
        try fileManager.createDirectory(at: tagsDir)
        
        // Generate a page for each tag
        for (tag, tagPosts) in taggedPosts {
            try generateTagPage(
                tag: tag,
                posts: tagPosts,
                tagsDir: tagsDir
            )
        }
        
        // Generate tags index page
        try generateTagsIndex(tags: Array(taggedPosts.keys), outputDir: tagsDir)
    }
    
    // Private helper methods
    
    private func generatePaginatedArchive(posts: [Post], archiveDir: URL) throws {
        let postsPerPage = config.blog.postsPerPage
        let totalPages = (posts.count + postsPerPage - 1) / postsPerPage
        
        for page in 0..<totalPages {
            let startIndex = page * postsPerPage
            let endIndex = min(startIndex + postsPerPage, posts.count)
            let pagePosts = Array(posts[startIndex..<endIndex])
            
            // Create page directory
            let pageDir = archiveDir.appendingPathComponent("page/\(page + 1)")
            try fileManager.createDirectory(at: pageDir)
            
            // Render page
            let html = try templateRenderer.renderArchivePage(posts: pagePosts)
            
            // Write page index
            let pageIndex = pageDir.appendingPathComponent("index.html")
            try fileManager.writeFile(content: html, to: pageIndex)
        }
    }
    
    private func generateCategoryPage(category: String, posts: [Post], categoriesDir: URL) throws {
        // Create category directory (slugified)
        let categorySlug = slugify(category)
        let categoryDir = categoriesDir.appendingPathComponent(categorySlug)
        try fileManager.createDirectory(at: categoryDir)
        
        // Sort posts by date
        let sortedPosts = posts.sorted { $0.date > $1.date }
        
        // Render category page
        let html = try templateRenderer.renderCategoryPage(category: category, posts: sortedPosts)
        
        // Write category index
        let categoryIndex = categoryDir.appendingPathComponent("index.html")
        try fileManager.writeFile(content: html, to: categoryIndex)
    }
    
    private func generateTagPage(tag: String, posts: [Post], tagsDir: URL) throws {
        // Create tag directory (slugified)
        let tagSlug = slugify(tag)
        let tagDir = tagsDir.appendingPathComponent(tagSlug)
        try fileManager.createDirectory(at: tagDir)
        
        // Sort posts by date
        let sortedPosts = posts.sorted { $0.date > $1.date }
        
        // Render tag page
        let html = try templateRenderer.renderTagPage(tag: tag, posts: sortedPosts)
        
        // Write tag index
        let tagIndex = tagDir.appendingPathComponent("index.html")
        try fileManager.writeFile(content: html, to: tagIndex)
    }
    
    private func generateCategoriesIndex(categories: [String], outputDir: URL) throws {
        // Simple categories listing page
        var html = """
        <!DOCTYPE html>
        <html lang="\(config.site.language ?? "en")">
        <head>
            <meta charset="UTF-8">
            <title>Categories - \(config.site.title)</title>
        </head>
        <body>
            <h1>Categories</h1>
            <ul>
        """
        
        for category in categories.sorted() {
            let categorySlug = slugify(category)
            html += """
                <li><a href="/categories/\(categorySlug)/">\(category)</a></li>
            """
        }
        
        html += """
            </ul>
        </body>
        </html>
        """
        
        let indexPath = outputDir.appendingPathComponent("index.html")
        try fileManager.writeFile(content: html, to: indexPath)
    }
    
    private func generateTagsIndex(tags: [String], outputDir: URL) throws {
        // Simple tags listing page
        var html = """
        <!DOCTYPE html>
        <html lang="\(config.site.language ?? "en")">
        <head>
            <meta charset="UTF-8">
            <title>Tags - \(config.site.title)</title>
        </head>
        <body>
            <h1>Tags</h1>
            <ul>
        """
        
        for tag in tags.sorted() {
            let tagSlug = slugify(tag)
            html += """
                <li><a href="/tags/\(tagSlug)/">\(tag)</a></li>
            """
        }
        
        html += """
            </ul>
        </body>
        </html>
        """
        
        let indexPath = outputDir.appendingPathComponent("index.html")
        try fileManager.writeFile(content: html, to: indexPath)
    }
    
    private func groupPostsByCategory(_ posts: [Post]) -> [String: [Post]] {
        var categorizedPosts: [String: [Post]] = [:]
        
        for post in posts {
            for category in post.categories {
                if categorizedPosts[category] == nil {
                    categorizedPosts[category] = []
                }
                categorizedPosts[category]?.append(post)
            }
        }
        
        return categorizedPosts
    }
    
    private func groupPostsByTag(_ posts: [Post]) -> [String: [Post]] {
        var taggedPosts: [String: [Post]] = [:]
        
        for post in posts {
            for tag in post.tags {
                if taggedPosts[tag] == nil {
                    taggedPosts[tag] = []
                }
                taggedPosts[tag]?.append(post)
            }
        }
        
        return taggedPosts
    }
    
    private func slugify(_ text: String) -> String {
        // Convert to lowercase
        var slug = text.lowercased()
        
        // Replace spaces with hyphens
        slug = slug.replacingOccurrences(of: " ", with: "-")
        
        // Remove special characters
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        slug = slug.components(separatedBy: allowedCharacters.inverted).joined()
        
        // Remove multiple consecutive hyphens
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        
        // Remove leading/trailing hyphens
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        
        return slug.isEmpty ? "untitled" : slug
    }
}
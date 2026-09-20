import Foundation

// Archive, category, and tag page generation separated from SiteGenerator
public class ArchiveGenerator {
    private let fileManager: SiteFileManager
    private let templateRenderer: SiteTemplateRenderer
    private let config: HirundoConfig
    private let templateEngine: TemplateEngine
    
    public init(
        fileManager: SiteFileManager,
        templateRenderer: SiteTemplateRenderer,
        config: HirundoConfig,
        templateEngine: TemplateEngine
    ) {
        self.fileManager = fileManager
        self.templateRenderer = templateRenderer
        self.config = config
        self.templateEngine = templateEngine
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
    
    /// サイトが公開されるパス（`site.url` にパスがあるときの `/blog` など）。索引ページの
    /// リンクにだけ付く ── ディレクトリは出力ルートからの位置で作るので付けない。
    private var basePath: String { URLUtils.sitePathPrefix(of: config.site.url) }

    private func generateCategoryPage(category: String, posts: [Post], categoriesDir: URL) throws {
        // The bare slug, because this is a name on disk. The URL that links it is built from the
        // same slug in `generateCategoriesIndex`, where it goes through
        // `URLUtils.encodedComponent`. This is the point the two forms part company: hosting
        // decodes a request path before it looks for a file, so the directory must be the
        // decoded form and the link the encoded one.
        let categorySlug = category.slugify()
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
        // The bare slug. See `generateCategoryPage` for why this is not the encoded form.
        let tagSlug = tag.slugify()
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
        // Use template-based generation instead of string concatenation
        let context: [String: Any] = [
            "site": [
                "title": config.site.title,
                "language": config.site.language ?? "en"
            ],
            "categories": categories.sorted().map { category in
                [
                    "name": category,
                    // `slug` is the name on disk, `url` the encoded link to it. A template that
                    // builds its own href from `slug` wants the `url_encode` filter.
                    "slug": category.slugify(),
                    "url": basePath + "/categories/"
                        + URLUtils.encodedComponent(category.slugify()) + "/"
                ]
            },
            "page": [
                "title": "Categories",
                "type": "categories_index"
            ]
        ]
        
        let html = try renderCategoriesTemplate(context: context)
        let indexPath = outputDir.appendingPathComponent("index.html")
        try fileManager.writeFile(content: html, to: indexPath)
    }
    
    private func renderCategoriesTemplate(context: [String: Any]) throws -> String {
        // Try to use custom template if available, fallback to default
        let templateName = "categories.html"
        
        do {
            return try templateEngine.render(template: templateName, context: context)
        } catch {
            // `hirundo init` does not scaffold `categories.html`, so this is the path a site
            // takes until an author writes one — not an exceptional case.
            return generateDefaultCategoriesHTML(context: context)
        }
    }
    
    /// `internal` rather than `private` so the escaping below can be tested without standing up
    /// a whole site; see `ArchiveGeneratorFallbackTests`.
    func generateDefaultCategoriesHTML(context: [String: Any]) -> String {
        guard let site = context["site"] as? [String: Any],
              let categories = context["categories"] as? [[String: Any]],
              let page = context["page"] as? [String: Any] else {
            return "<html><body><h1>Error: Invalid context</h1></body></html>"
        }
        
        let title = HTMLEscaping.escaped(site["title"] as? String ?? "Site")
        let language = HTMLEscaping.escaped(site["language"] as? String ?? "en")
        let pageTitle = HTMLEscaping.escaped(page["title"] as? String ?? "Categories")
        
        var categoriesHTML = ""
        for category in categories {
            if let name = category["name"] as? String,
               let url = category["url"] as? String {
                categoriesHTML += "<li><a href=\"\(HTMLEscaping.escaped(url))\">"
                    + "\(HTMLEscaping.escaped(name))</a></li>\n"
            }
        }
        
        return """
        <!DOCTYPE html>
        <html lang="\(language)">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(pageTitle) - \(title)</title>
        </head>
        <body>
            <h1>\(pageTitle)</h1>
            <ul>
        \(categoriesHTML)
            </ul>
        </body>
        </html>
        """
    }
    
    private func generateTagsIndex(tags: [String], outputDir: URL) throws {
        // Use template-based generation instead of string concatenation
        let context: [String: Any] = [
            "site": [
                "title": config.site.title,
                "language": config.site.language ?? "en"
            ],
            "tags": tags.sorted().map { tag in
                [
                    "name": tag,
                    // See `generateCategoriesIndex` for why these two differ.
                    "slug": tag.slugify(),
                    "url": basePath + "/tags/" + URLUtils.encodedComponent(tag.slugify()) + "/"
                ]
            },
            "page": [
                "title": "Tags",
                "type": "tags_index"
            ]
        ]
        
        let html = try renderTagsTemplate(context: context)
        let indexPath = outputDir.appendingPathComponent("index.html")
        try fileManager.writeFile(content: html, to: indexPath)
    }
    
    private func renderTagsTemplate(context: [String: Any]) throws -> String {
        // Try to use custom template if available, fallback to default
        let templateName = "tags.html"
        
        do {
            return try templateEngine.render(template: templateName, context: context)
        } catch {
            // `hirundo init` does not scaffold `tags.html`, so this is the path a site takes
            // until an author writes one — not an exceptional case.
            return generateDefaultTagsHTML(context: context)
        }
    }
    
    /// `internal` rather than `private` so the escaping below can be tested without standing up
    /// a whole site; see `ArchiveGeneratorFallbackTests`.
    func generateDefaultTagsHTML(context: [String: Any]) -> String {
        guard let site = context["site"] as? [String: Any],
              let tags = context["tags"] as? [[String: Any]],
              let page = context["page"] as? [String: Any] else {
            return "<html><body><h1>Error: Invalid context</h1></body></html>"
        }
        
        let title = HTMLEscaping.escaped(site["title"] as? String ?? "Site")
        let language = HTMLEscaping.escaped(site["language"] as? String ?? "en")
        let pageTitle = HTMLEscaping.escaped(page["title"] as? String ?? "Tags")
        
        var tagsHTML = ""
        for tag in tags {
            if let name = tag["name"] as? String,
               let url = tag["url"] as? String {
                tagsHTML += "<li><a href=\"\(HTMLEscaping.escaped(url))\">"
                    + "\(HTMLEscaping.escaped(name))</a></li>\n"
            }
        }
        
        return """
        <!DOCTYPE html>
        <html lang="\(language)">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(pageTitle) - \(title)</title>
        </head>
        <body>
            <h1>\(pageTitle)</h1>
            <ul>
        \(tagsHTML)
            </ul>
        </body>
        </html>
        """
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
    
    
}
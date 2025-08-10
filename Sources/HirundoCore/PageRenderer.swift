import Foundation

/// Responsible for rendering pages using templates
public final class PageRenderer {
    private let templateEngine: TemplateEngine
    private let fileManager: FileManager
    
    public init(templatesDirectory: String, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.templateEngine = TemplateEngine(templatesDirectory: templatesDirectory)
    }
    
    /// Configure the renderer with site configuration
    public func configure(with siteConfig: Site) {
        templateEngine.configure(with: siteConfig)
    }
    
    /// Render a content item to HTML
    public func renderContentItem(
        _ item: ContentItem,
        with context: [String: Any],
        template: String? = nil
    ) throws -> String {
        // Determine template to use
        let templateName = template ?? (item.frontMatter["template"]?.value as? String) ?? {
            switch item.type {
            case .post:
                return "post.html"
            case .page:
                return "page.html"
            }
        }()
        
        // Build rendering context
        var renderContext = context
        let title = (item.frontMatter["title"]?.value as? String) ?? URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent
        let url = "/" + URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent
        
        renderContext["page"] = [
            "title": title,
            "content": item.content,
            "excerpt": String(item.content.prefix(200)),
            "url": url,
            "date": AnyCodable(item.frontMatter["date"]?.value ?? Date()),
            "tags": item.frontMatter["tags"]?.value ?? [],
            "categories": item.frontMatter["categories"]?.value ?? []
        ]
        renderContext["content"] = item.content
        
        // Render with template
        return try templateEngine.render(template: templateName, context: renderContext)
    }
    
    /// Render multiple pages in batch
    public func renderBatch(
        _ items: [ContentItem],
        with baseContext: [String: Any]
    ) throws -> [(item: ContentItem, html: String)] {
        var results: [(ContentItem, String)] = []
        
        for item in items {
            let html = try renderContentItem(item, with: baseContext)
            results.append((item, html))
        }
        
        return results
    }
    
    /// Write rendered HTML to file
    public func writeHTML(
        _ html: String,
        to path: String
    ) throws {
        let url = URL(fileURLWithPath: path)
        
        // Create parent directory if needed
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Write HTML file
        try html.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Render and write a page
    public func renderAndWritePage(
        _ item: ContentItem,
        to outputPath: String,
        with context: [String: Any]
    ) throws {
        let html = try renderContentItem(item, with: context)
        try writeHTML(html, to: outputPath)
    }
    
    /// Clear template cache
    public func clearCache() {
        templateEngine.clearCache()
    }
}
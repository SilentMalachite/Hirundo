import Foundation

// RSS feed generation plugin
public class RSSPlugin: Plugin {
    public let metadata = PluginMetadata(
        name: "RSSPlugin",
        version: "1.0.0",
        author: "Hirundo",
        description: "Generates RSS feeds for blog posts"
    )
    
    private var context: PluginContext?
    private var feedPath: String = "rss.xml"
    private var itemLimit: Int = 20
    
    public init() {}
    
    public func initialize(context: PluginContext) throws {
        self.context = context
    }
    
    public func cleanup() throws {
        context = nil
    }
    
    public func configure(with config: PluginConfig) throws {
        if let path = config.settings["feedPath"] as? String {
            feedPath = path
        }
        if let limit = config.settings["itemLimit"] as? Int {
            itemLimit = limit
        }
    }
    
    public func afterBuild(context: BuildContext) throws {
        guard let pluginContext = self.context else { return }
        
        // Generate RSS feed
        let outputURL = URL(fileURLWithPath: context.outputPath)
            .appendingPathComponent(feedPath)
        
        let rssContent = try generateRSSFeed(
            config: pluginContext.config,
            posts: gatherPosts(from: context)
        )
        
        try rssContent.write(to: outputURL, atomically: true, encoding: .utf8)
    }
    
    private func gatherPosts(from context: BuildContext) -> [RSSItem] {
        // Extract posts from build context
        return context.pages.compactMap { page in
            // Only include posts (pages with dates)
            guard let dateString = page.frontMatter["date"] as? String,
                  let date = parseDate(dateString),
                  let title = page.frontMatter["title"] as? String else {
                return nil
            }
            
            let description = page.frontMatter["excerpt"] as? String 
                           ?? page.frontMatter["description"] as? String 
                           ?? String(page.content.prefix(200))
            
            // Generate URL for the post
            let slug = page.frontMatter["slug"] as? String ?? slugify(title)
            let link = "\(context.config.site.url)/posts/\(slug)/"
            
            return RSSItem(
                title: title,
                link: link,
                description: description,
                pubDate: date
            )
        }
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
    
    private func slugify(_ text: String) -> String {
        return text
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
    }
    
    private func generateRSSFeed(config: HirundoConfig, posts: [RSSItem]) throws -> String {
        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())
        
        var rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
        <channel>
            <title>\(escapeXML(config.site.title))</title>
            <link>\(escapeXML(config.site.url))</link>
            <description>\(escapeXML(config.site.description ?? ""))</description>
            <language>\(config.site.language ?? "en-US")</language>
            <lastBuildDate>\(now)</lastBuildDate>
            <atom:link href="\(config.site.url)/\(feedPath)" rel="self" type="application/rss+xml" />
        
        """
        
        let sortedPosts = posts
            .sorted { $0.pubDate > $1.pubDate }
            .prefix(itemLimit)
        
        for post in sortedPosts {
            rss += """
            <item>
                <title>\(escapeXML(post.title))</title>
                <link>\(escapeXML(post.link))</link>
                <guid>\(escapeXML(post.link))</guid>
                <pubDate>\(dateFormatter.string(from: post.pubDate))</pubDate>
                <description>\(escapeXML(post.description))</description>
            </item>
            
            """
        }
        
        rss += """
        </channel>
        </rss>
        """
        
        return rss
    }
    
    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    struct RSSItem {
        let title: String
        let link: String
        let description: String
        let pubDate: Date
    }
}
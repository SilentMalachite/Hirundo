import Foundation

// Sitemap generation plugin
public final class SitemapPlugin: @unchecked Sendable, Plugin {
    public let metadata = PluginMetadata(
        name: "SitemapPlugin",
        version: "1.0.0",
        author: "Hirundo",
        description: "Generates XML sitemap for SEO"
    )
    
    private let lock = NSLock()
    private var _context: PluginContext?
    private var _excludePatterns: [String] = []
    private var _changeFrequency: String = "weekly"
    private var _priority: Double = 0.5
    
    private var context: PluginContext? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _context
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _context = newValue
        }
    }
    
    private var excludePatterns: [String] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _excludePatterns
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _excludePatterns = newValue
        }
    }
    
    private var changeFrequency: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _changeFrequency
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _changeFrequency = newValue
        }
    }
    
    private var priority: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _priority
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _priority = newValue
        }
    }
    
    public init() {}
    
    public func initialize(context: PluginContext) throws {
        self.context = context
    }
    
    public func cleanup() throws {
        context = nil
    }
    
    public func configure(with config: PluginConfig) throws {
        if let patterns = config.settings["exclude"]?.value as? [String] {
            excludePatterns = patterns
        }
        if let freq = config.settings["changefreq"]?.value as? String {
            changeFrequency = freq
        }
        if let prio = config.settings["priority"]?.value as? Double {
            priority = prio
        }
    }
    
    public func afterBuild(context: BuildContext) throws {
        guard let pluginContext = self.context else { return }
        
        let outputURL = URL(fileURLWithPath: context.outputPath)
        let sitemapURL = outputURL.appendingPathComponent("sitemap.xml")
        
        let urls = try gatherURLs(from: outputURL, baseURL: pluginContext.config.site.url)
        let sitemap = generateSitemap(urls: urls)
        
        try sitemap.write(to: sitemapURL, atomically: true, encoding: .utf8)
    }
    
    private func gatherURLs(from directory: URL, baseURL: String) throws -> [SitemapURL] {
        let fileManager = FileManager.default
        var urls: [SitemapURL] = []
        
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "html" else { continue }
            
            let relativePath = fileURL.path
                .replacingOccurrences(of: directory.path, with: "")
                .replacingOccurrences(of: "/index.html", with: "/")
            
            // Skip if matches exclude pattern
            if shouldExclude(path: relativePath) {
                continue
            }
            
            let modDate = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate ?? Date()
            
            urls.append(SitemapURL(
                loc: baseURL + relativePath,
                lastmod: modDate,
                changefreq: changeFrequency,
                priority: priority
            ))
        }
        
        return urls
    }
    
    private func shouldExclude(path: String) -> Bool {
        for pattern in excludePatterns {
            if matchesPattern(path, pattern: pattern) {
                return true
            }
        }
        return false
    }
    
    private func matchesPattern(_ path: String, pattern: String) -> Bool {
        // Simple glob pattern matching
        if pattern.contains("*") {
            let regex = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            return path.range(of: regex, options: .regularExpression) != nil
        }
        return path.contains(pattern)
    }
    
    private func generateSitemap(urls: [SitemapURL]) -> String {
        let dateFormatter = ISO8601DateFormatter()
        
        var sitemap = """
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        
        """
        
        for url in urls {
            sitemap += """
            <url>
                <loc>\(escapeXML(url.loc))</loc>
                <lastmod>\(dateFormatter.string(from: url.lastmod))</lastmod>
                <changefreq>\(url.changefreq)</changefreq>
                <priority>\(url.priority)</priority>
            </url>
            
            """
        }
        
        sitemap += "</urlset>"
        
        return sitemap
    }
    
    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    struct SitemapURL {
        let loc: String
        let lastmod: Date
        let changefreq: String
        let priority: Double
    }
}
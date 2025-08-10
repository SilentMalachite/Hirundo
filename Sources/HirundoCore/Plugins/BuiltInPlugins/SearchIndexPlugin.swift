import Foundation

// Search index generation plugin
public final class SearchIndexPlugin: @unchecked Sendable, Plugin {
    public let metadata = PluginMetadata(
        name: "SearchIndexPlugin",
        version: "1.0.0",
        author: "Hirundo",
        description: "Generates search index for client-side search"
    )
    
    private let lock = NSLock()
    private var _context: PluginContext?
    private var _indexPath: String = "search-index.json"
    private var _includeContent: Bool = true
    private var _contentLength: Int = 200
    
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
    
    private var indexPath: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _indexPath
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _indexPath = newValue
        }
    }
    
    private var includeContent: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _includeContent
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _includeContent = newValue
        }
    }
    
    private var contentLength: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _contentLength
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _contentLength = newValue
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
        if let path = config.settings["indexPath"]?.value as? String {
            indexPath = path
        }
        if let include = config.settings["includeContent"]?.value as? Bool {
            includeContent = include
        }
        if let length = config.settings["contentLength"]?.value as? Int {
            contentLength = length
        }
    }
    
    private var _searchEntries: [SearchEntry] = []
    
    private var searchEntries: [SearchEntry] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _searchEntries
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _searchEntries = newValue
        }
    }
    
    public func transformContent(_ content: ContentItem) throws -> ContentItem {
        // Collect search entries during content transformation
        // All content types are searchable
        if content.type == .post || content.type == .page {
            let entry = SearchEntry(
                url: "/" + content.path.replacingOccurrences(of: ".md", with: ""),
                title: content.frontMatter["title"]?.value as? String ?? "Untitled",
                content: includeContent ? extractText(from: content.content).prefix(contentLength) : "",
                tags: extractTags(from: content.frontMatter),
                date: content.frontMatter["date"]?.value as? Date
            )
            lock.lock()
            _searchEntries.append(entry)
            lock.unlock()
        }
        
        return content
    }
    
    public func afterBuild(context: BuildContext) throws {
        // Generate search index
        let outputURL = URL(fileURLWithPath: context.outputPath)
            .appendingPathComponent(indexPath)
        
        let indexData = try generateSearchIndex(entries: searchEntries)
        try indexData.write(to: outputURL)
        
        // Clear entries for next build
        lock.lock()
        _searchEntries.removeAll()
        lock.unlock()
    }
    
    private func extractText(from content: String) -> String {
        // Remove HTML tags and markdown formatting
        var text = content
        
        // Remove HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        
        // Remove markdown formatting
        text = text
            .replacingOccurrences(of: "#+ ", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "__", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "```[^`]*```", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "`", with: "", options: .regularExpression)
        
        // Clean up whitespace
        text = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return text
    }
    
    private func extractTags(from frontMatter: [String: AnyCodable]) -> [String] {
        var tags: [String] = []
        
        if let categories = frontMatter["categories"]?.value as? [String] {
            tags.append(contentsOf: categories)
        }
        
        if let blogTags = frontMatter["tags"]?.value as? [String] {
            tags.append(contentsOf: blogTags)
        }
        
        return tags
    }
    
    private func generateSearchIndex(entries: [SearchEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let index = SearchIndex(
            version: "1.0",
            generated: Date(),
            entries: entries
        )
        
        return try encoder.encode(index)
    }
    
    private func extractText(from content: String, length: Int) -> String {
        let text = extractText(from: content)
        if text.count <= length {
            return text
        }
        
        let index = text.index(text.startIndex, offsetBy: length)
        return String(text[..<index]) + "..."
    }
    
    struct SearchEntry: Codable {
        let url: String
        let title: String
        let content: String
        let tags: [String]
        let date: Date?
    }
    
    struct SearchIndex: Codable {
        let version: String
        let generated: Date
        let entries: [SearchEntry]
    }
}

extension String {
    func prefix(_ maxLength: Int) -> String {
        if count <= maxLength {
            return self
        }
        let index = self.index(startIndex, offsetBy: maxLength)
        return String(self[..<index])
    }
}
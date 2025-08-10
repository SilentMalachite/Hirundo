import Foundation
import Markdown

/// Type alias for ContentItem.ContentType for convenience
public typealias ContentType = ContentItem.ContentType

/// Responsible for processing content files (markdown, HTML, etc.)
public final class ContentProcessor {
    private let markdownParser: MarkdownParser
    private let fileManager: FileManager
    private let limits: Limits
    
    public init(limits: Limits = Limits(), fileManager: FileManager = .default) {
        self.limits = limits
        self.fileManager = fileManager
        self.markdownParser = MarkdownParser(limits: limits, enableStreaming: true)
    }
    
    /// Process all content files in a directory
    public func processContentDirectory(at path: String) throws -> [ContentItem] {
        let contentURL = URL(fileURLWithPath: path)
        var items: [ContentItem] = []
        
        guard fileManager.fileExists(atPath: path) else {
            throw MarkdownError.fileNotFound(path)
        }
        
        let enumerator = fileManager.enumerator(
            at: contentURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        guard let enumerator = enumerator else {
            throw MarkdownError.fileNotFound(path)
        }
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "md" || fileURL.pathExtension == "markdown" {
                do {
                    let item = try processMarkdownFile(at: fileURL.path)
                    items.append(item)
                } catch {
                    print("⚠️ Failed to process \(fileURL.path): \(error)")
                }
            }
        }
        
        return items
    }
    
    /// Process a single markdown file
    public func processMarkdownFile(at path: String) throws -> ContentItem {
        return try markdownParser.parseFile(at: path, extractOnly: false)
    }
    
    /// Process markdown files in batches for better performance
    public func processBatch(_ paths: [String], extractOnly: Bool = false) throws -> [ContentItem] {
        var items: [ContentItem] = []
        
        // Process files concurrently
        let queue = DispatchQueue(label: "com.hirundo.content.batch", attributes: .concurrent)
        let group = DispatchGroup()
        let lock = NSLock()
        var errors: [Error] = []
        
        for path in paths {
            group.enter()
            queue.async { [weak self] in
                defer { group.leave() }
                
                guard let self = self else { return }
                
                do {
                    let item = try self.markdownParser.parseFile(at: path, extractOnly: extractOnly)
                    lock.lock()
                    items.append(item)
                    lock.unlock()
                } catch {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                }
            }
        }
        
        group.wait()
        
        if !errors.isEmpty {
            print("⚠️ \(errors.count) files failed to process")
        }
        
        return items
    }
    
    /// Extract metadata from content files without full parsing
    public func extractMetadata(from paths: [String]) throws -> [ContentMetadata] {
        let items = try processBatch(paths, extractOnly: true)
        return items.map { item in
            ContentMetadata(
                title: item.frontMatter["title"] as? String ?? URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent,
                path: item.path,
                url: "/" + URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent,
                excerpt: String(item.content.prefix(200)),
                metadata: item.frontMatter,
                type: item.type
            )
        }
    }
}

/// Lightweight metadata structure
public struct ContentMetadata {
    public let title: String
    public let path: String
    public let url: String
    public let excerpt: String?
    public let metadata: [String: Any]
    public let type: ContentType
}
import Foundation
import Markdown

// Content processing responsibility separated from SiteGenerator
public class ContentProcessor {
    private let markdownParser: MarkdownParser
    private let config: HirundoConfig
    private let securityValidator: SecurityValidator
    
    public init(config: HirundoConfig, securityValidator: SecurityValidator) {
        self.config = config
        self.markdownParser = MarkdownParser()
        self.securityValidator = securityValidator
    }
    
    // Process a markdown file and return parsed content
    public func processMarkdownFile(
        at fileURL: URL,
        projectPath: String,
        includeDrafts: Bool
    ) throws -> ProcessedContent? {
        // Validate file path
        try securityValidator.validatePath(fileURL.path, withinBaseDirectory: projectPath)
        
        // Read file content with timeout
        let content = try TimeoutFileManager.readFile(
            at: fileURL.path,
            timeout: config.timeouts.fileReadTimeout
        )
        
        // Parse markdown
        let result = try markdownParser.parse(content)
        
        // Check if it's a draft
        if let isDraft = result.frontMatter?["draft"] as? Bool, isDraft && !includeDrafts {
            return nil
        }
        
        // Determine content type
        let contentType = determineContentType(from: fileURL, metadata: result.frontMatter ?? [:])
        
        // Create processed content
        return ProcessedContent(
            url: fileURL,
            markdown: result,
            type: contentType,
            metadata: extractMetadata(from: result.frontMatter ?? [:])
        )
    }
    
    // Process all content in a directory
    public func processDirectory(
        at directoryURL: URL,
        includeDrafts: Bool
    ) throws -> [ProcessedContent] {
        var processedContents: [ProcessedContent] = []
        
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ContentProcessorError.cannotEnumerateDirectory(directoryURL.path)
        }
        
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "md" || fileURL.pathExtension == "markdown" else {
                continue
            }
            
            if let processed = try processMarkdownFile(
                at: fileURL,
                projectPath: directoryURL.deletingLastPathComponent().path,
                includeDrafts: includeDrafts
            ) {
                processedContents.append(processed)
            }
        }
        
        return processedContents
    }
    
    // Process directory with error recovery - returns both successes and failures
    public func processDirectoryWithRecovery(
        at directoryURL: URL,
        includeDrafts: Bool
    ) throws -> (contents: [ProcessedContent], errors: [(url: URL, error: Error)]) {
        var processedContents: [ProcessedContent] = []
        var errors: [(url: URL, error: Error)] = []
        
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ContentProcessorError.cannotEnumerateDirectory(directoryURL.path)
        }
        
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "md" || fileURL.pathExtension == "markdown" else {
                continue
            }
            
            do {
                if let processed = try processMarkdownFile(
                    at: fileURL,
                    projectPath: directoryURL.deletingLastPathComponent().path,
                    includeDrafts: includeDrafts
                ) {
                    processedContents.append(processed)
                    print("[ContentProcessor] Successfully processed: \(fileURL.lastPathComponent)")
                }
            } catch {
                // Collect error information
                print("[ContentProcessor] Error processing \(fileURL.lastPathComponent): \(error)")
                errors.append((url: fileURL, error: error))
                // Continue to next file
                continue
            }
        }
        
        return (contents: processedContents, errors: errors)
    }
    
    // Render markdown content to HTML
    public func renderMarkdownContent(_ result: MarkdownParseResult) -> String {
        // Use the built-in HTML formatter from swift-markdown
        var html = ""
        for element in result.content {
            html += renderElement(element)
        }
        return html
    }
    
    private func renderElement(_ element: MarkdownElement) -> String {
        switch element {
        case .heading(let heading):
            return "<h\(heading.level)>\(securityValidator.sanitizeForTemplate(heading.text))</h\(heading.level)>\n"
        case .paragraph(let text):
            return "<p>\(securityValidator.sanitizeForTemplate(text))</p>\n"
        case .codeBlock(let codeBlock):
            let lang = codeBlock.language ?? ""
            return "<pre><code class=\"language-\(lang)\">\(securityValidator.sanitizeForTemplate(codeBlock.content))</code></pre>\n"
        case .list(let list):
            let tag = list.isOrdered ? "ol" : "ul"
            var html = "<\(tag)>\n"
            for item in list.items {
                html += "<li>\(securityValidator.sanitizeForTemplate(item))</li>\n"
            }
            html += "</\(tag)>\n"
            return html
        case .link(let link):
            return "<a href=\"\(link.url)\">\(securityValidator.sanitizeForTemplate(link.text))</a>"
        case .image(let image):
            return "<img src=\"\(image.url)\" alt=\"\(securityValidator.sanitizeForTemplate(image.alt ?? ""))\" />"
        case .table(let table):
            var html = "<table>\n<thead>\n<tr>\n"
            for header in table.headers {
                html += "<th>\(securityValidator.sanitizeForTemplate(header))</th>\n"
            }
            html += "</tr>\n</thead>\n<tbody>\n"
            for row in table.rows {
                html += "<tr>\n"
                for cell in row {
                    html += "<td>\(securityValidator.sanitizeForTemplate(cell))</td>\n"
                }
                html += "</tr>\n"
            }
            html += "</tbody>\n</table>\n"
            return html
        case .other:
            return ""
        }
    }
    
    private func determineContentType(from url: URL, metadata: [String: Any]) -> ProcessedContentType {
        // Check if explicitly specified in metadata
        if let typeString = metadata["type"] as? String {
            switch typeString.lowercased() {
            case "post", "blog":
                return .post
            case "page":
                return .page
            default:
                break
            }
        }
        
        // Determine by path
        let path = url.path.lowercased()
        if path.contains("/posts/") || path.contains("/blog/") {
            return .post
        }
        
        return .page
    }
    
    private func extractMetadata(from metadata: [String: Any]) -> ContentMetadata {
        return ContentMetadata(
            title: metadata["title"] as? String ?? "Untitled",
            description: metadata["description"] as? String,
            date: metadata["date"] as? Date ?? Date(),
            author: metadata["author"] as? String,
            categories: extractStringArray(from: metadata["categories"]),
            tags: extractStringArray(from: metadata["tags"]),
            template: metadata["template"] as? String,
            slug: metadata["slug"] as? String
        )
    }
    
    private func extractStringArray(from value: Any?) -> [String] {
        if let array = value as? [String] {
            return array
        } else if let string = value as? String {
            return [string]
        }
        return []
    }
}

// Processed content model
public struct ProcessedContent {
    public let url: URL
    public let markdown: MarkdownParseResult
    public let type: ProcessedContentType
    public let metadata: ContentMetadata
}

// Content metadata
public struct ContentMetadata {
    public let title: String
    public let description: String?
    public let date: Date
    public let author: String?
    public let categories: [String]
    public let tags: [String]
    public let template: String?
    public let slug: String?
}

// Content type enum
public enum ProcessedContentType {
    case page
    case post
}

// Content processor errors
public enum ContentProcessorError: LocalizedError {
    case cannotEnumerateDirectory(String)
    case invalidContent(String)
    
    public var errorDescription: String? {
        switch self {
        case .cannotEnumerateDirectory(let path):
            return "Cannot enumerate directory: \(path)"
        case .invalidContent(let reason):
            return "Invalid content: \(reason)"
        }
    }
}
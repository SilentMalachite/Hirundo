import Foundation
import Markdown
import Yams

/// A streaming markdown parser that processes large files efficiently
public final class StreamingMarkdownParser {
    private let chunkSize: Int
    private let maxMetadataSize: Int
    
    public init(chunkSize: Int = 65536, maxMetadataSize: Int = 102400) { // 64KB chunks, 100KB max metadata
        self.chunkSize = chunkSize
        self.maxMetadataSize = maxMetadataSize
    }
    
    /// Parses a markdown file using streaming to minimize memory usage
    /// - Parameters:
    ///   - path: Path to the markdown file
    ///   - extractOnly: If true, only extracts front matter and excerpt
    /// - Returns: Parsed content item
    public func parseFile(at path: String, extractOnly: Bool = false) throws -> ContentItem {
        let url = URL(fileURLWithPath: path)
        
        // Open file for reading
        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            throw MarkdownError.fileNotFound(path)
        }
        
        defer {
            fileHandle.closeFile()
        }
        
        // First, extract front matter efficiently
        let (frontMatter, contentStart) = try extractFrontMatter(from: fileHandle)
        
        // Parse front matter
        let metadata = try parseFrontMatter(frontMatter)
        
        // If only extracting metadata, create minimal content item
        if extractOnly {
            let excerpt = try extractExcerpt(from: fileHandle, startingAt: contentStart)
            return ContentItem(
                path: path,
                frontMatter: metadata,
                content: excerpt,
                type: .page
            )
        }
        
        // For full parsing, stream the content
        fileHandle.seek(toFileOffset: UInt64(contentStart))
        let content = try streamParseContent(from: fileHandle)
        
        // Create content item
        let type: ContentType = url.pathComponents.contains("posts") ? .post : .page
        
        return ContentItem(
            path: path,
            frontMatter: metadata,
            content: content,
            type: type
        )
    }
    
    /// Extracts front matter from the beginning of a file
    private func extractFrontMatter(from fileHandle: FileHandle) throws -> (String?, Int) {
        fileHandle.seek(toFileOffset: 0)
        
        var frontMatter = ""
        var contentStart = 0
        var foundStart = false
        var foundEnd = false
        var totalRead = 0
        
        while totalRead < maxMetadataSize {
            guard let data = fileHandle.readData(ofLength: 1024) as Data?,
                  !data.isEmpty else {
                break
            }
            
            guard let chunk = String(data: data, encoding: .utf8) else {
                throw MarkdownError.invalidEncoding
            }
            
            let lines = chunk.components(separatedBy: .newlines)
            
            for (index, line) in lines.enumerated() {
                if !foundStart {
                    if line.trimmingCharacters(in: .whitespaces) == "---" {
                        foundStart = true
                        contentStart = totalRead + line.count + 1
                    }
                } else if !foundEnd {
                    if line.trimmingCharacters(in: .whitespaces) == "---" {
                        foundEnd = true
                        contentStart = totalRead + chunk.components(separatedBy: "\n")
                            .prefix(index + 1)
                            .map { $0.count + 1 }
                            .reduce(0, +)
                        break
                    } else {
                        frontMatter += line + "\n"
                    }
                }
            }
            
            if foundEnd {
                break
            }
            
            totalRead += data.count
        }
        
        return (foundStart && foundEnd ? frontMatter : nil, contentStart)
    }
    
    /// Parses front matter YAML
    private func parseFrontMatter(_ frontMatter: String?) throws -> [String: Any] {
        guard let frontMatter = frontMatter else {
            return [:]
        }
        
        do {
            let decoded = try Yams.load(yaml: frontMatter) as? [String: Any] ?? [:]
            return decoded
        } catch {
            throw MarkdownError.invalidFrontMatter(error.localizedDescription)
        }
    }
    
    /// Extracts an excerpt from the content
    private func extractExcerpt(from fileHandle: FileHandle, startingAt offset: Int, maxLength: Int = 500) throws -> String {
        fileHandle.seek(toFileOffset: UInt64(offset))
        
        guard let data = fileHandle.readData(ofLength: maxLength * 2) as Data? else {
            return ""
        }
        
        guard let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        
        // Parse just the excerpt portion
        let document = Document(parsing: text)
        var visitor = PlainTextExtractor()
        let plainText = visitor.visit(document)
        
        if plainText.count <= maxLength {
            return plainText
        }
        
        // Find a good break point (end of sentence or word)
        let truncated = String(plainText.prefix(maxLength))
        if let lastPeriod = truncated.lastIndex(of: ".") {
            return String(truncated[...lastPeriod])
        } else if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        } else {
            return truncated + "..."
        }
    }
    
    /// Stream parses the markdown content
    private func streamParseContent(from fileHandle: FileHandle) throws -> String {
        var markdownBuffer = ""
        var htmlOutput = ""
        
        while true {
            guard let data = fileHandle.readData(ofLength: chunkSize) as Data?,
                  !data.isEmpty else {
                break
            }
            
            guard let chunk = String(data: data, encoding: .utf8) else {
                throw MarkdownError.invalidEncoding
            }
            
            markdownBuffer += chunk
            
            // Process complete paragraphs/blocks
            if let lastDoubleNewline = markdownBuffer.range(of: "\n\n", options: .backwards)?.lowerBound {
                let completeContent = String(markdownBuffer[..<lastDoubleNewline])
                markdownBuffer = String(markdownBuffer[markdownBuffer.index(after: lastDoubleNewline)...])
                
                // Parse and convert the complete blocks
                let document = Document(parsing: completeContent)
                let html = SimpleHTMLRenderer.render(document)
                htmlOutput += html
            }
            
            // Prevent buffer from growing too large
            if markdownBuffer.count > chunkSize * 2 {
                // Force process the buffer
                let document = Document(parsing: markdownBuffer)
                let html = SimpleHTMLRenderer.render(document)
                htmlOutput += html
                markdownBuffer = ""
            }
        }
        
        // Process any remaining content
        if !markdownBuffer.isEmpty {
            let document = Document(parsing: markdownBuffer)
            let html = SimpleHTMLRenderer.render(document)
            htmlOutput += html
        }
        
        return htmlOutput
    }
    
    /// Extracts excerpt from HTML content
    private func extractExcerptFromContent(_ html: String, maxLength: Int = 200) -> String {
        // Simple HTML tag removal for excerpt
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if stripped.count <= maxLength {
            return stripped
        }
        
        let truncated = String(stripped.prefix(maxLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        
        return truncated + "..."
    }
}

/// Plain text extractor for markdown documents
private struct PlainTextExtractor: MarkupVisitor {
    typealias Result = String
    
    mutating func defaultVisit(_ markup: any Markup) -> String {
        var result = ""
        for child in markup.children {
            let text = visit(child)
            result += text
        }
        return result
    }
    
    mutating func visitText(_ text: Text) -> String {
        return text.string
    }
    
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        return "" // Skip code blocks in excerpts
    }
    
    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        return "" // Skip HTML blocks in excerpts
    }
}
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
        let type: ContentItem.ContentType = url.pathComponents.contains("posts") ? .post : .page
        
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
        
        // Read up to maxMetadataSize bytes to locate front matter boundaries by byte offset
        let head = fileHandle.readData(ofLength: maxMetadataSize)
        if head.count == 0 {
            return (nil, 0)
        }
        
        // Check start marker at beginning of file (--- followed by newline)
        let startLineLF = Data("---\n".utf8)
        let startLineCRLF = Data("---\r\n".utf8)
        var contentStartOffset = 0
        var searchStartIndex = 0
        
        if head.starts(with: startLineLF) {
            searchStartIndex = startLineLF.count
        } else if head.starts(with: startLineCRLF) {
            searchStartIndex = startLineCRLF.count
        } else {
            // No front matter
            return (nil, 0)
        }
        
        // Find end marker on its own line: \n---\n or \r\n---\r\n
        let endLF = Data("\n---\n".utf8)
        let endCRLF = Data("\r\n---\r\n".utf8)
        
        // Search for LF pattern first
        var endRange = head.range(of: endLF, options: [], in: searchStartIndex..<head.count)
        var endLen = endLF.count
        if endRange == nil {
            endRange = head.range(of: endCRLF, options: [], in: searchStartIndex..<head.count)
            endLen = endCRLF.count
        }
        
        guard let end = endRange else {
            // End marker not found within the metadata size limit
            return (nil, 0)
        }
        
        // front matter bytes lie between searchStartIndex and end.lowerBound
        let fmData = head.subdata(in: searchStartIndex..<end.lowerBound)
        guard let fmString = String(data: fmData, encoding: .utf8) else {
            throw MarkdownError.invalidEncoding
        }
        
        // content starts right after end marker
        contentStartOffset = end.lowerBound + endLen
        
        return (fmString, contentStartOffset)
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
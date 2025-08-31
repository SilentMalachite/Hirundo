import Foundation
import Markdown
import Yams

/// Simplified parser stub that maintains the same API but parses in-memory.
public final class StreamingMarkdownParser {
    private let chunkSize: Int // kept for API compatibility (unused)
    private let maxMetadataSize: Int // kept for API compatibility (unused)

    public init(chunkSize: Int = 65536, maxMetadataSize: Int = 102400) {
        self.chunkSize = chunkSize
        self.maxMetadataSize = maxMetadataSize
    }

    /// Parses a markdown file; simplified to load whole file and render.
    /// - Parameters:
    ///   - path: Path to the markdown file.
    ///   - extractOnly: If true, only extracts front matter and returns a short excerpt.
    public func parseFile(at path: String, extractOnly: Bool = false) throws -> ContentItem {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw MarkdownError.fileNotFound("File not found: \(path)")
        }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let (metadata, body) = try extractFrontMatter(from: content)

        let type: ContentItem.ContentType = url.pathComponents.contains("posts") ? .post : .page
        if extractOnly {
            let excerpt = makeExcerpt(from: body, maxLength: 200)
            return ContentItem(path: path, frontMatter: metadata, content: excerpt, type: type)
        }

        let document = Document(parsing: body)
        let html = SimpleHTMLRenderer.render(document)
        return ContentItem(path: path, frontMatter: metadata, content: html, type: type)
    }

    // MARK: - Helpers
    private func extractFrontMatter(from content: String) throws -> ([String: Any], String) {
        var metadata: [String: Any] = [:]
        var body = content

        if content.hasPrefix("---\r\n") || content.hasPrefix("---\n") {
            let usesCRLF = content.hasPrefix("---\r\n")
            let startOffset = usesCRLF ? 5 : 4 // length of "---\r\n" or "---\n"
            let endMarker = usesCRLF ? "\r\n---\r\n" : "\n---\n"

            let start = content.index(content.startIndex, offsetBy: startOffset)
            if let range = content.range(of: endMarker, range: start..<content.endIndex) {
                let fm = String(content[start..<range.lowerBound])
                body = String(content[range.upperBound...])
                do {
                    metadata = try Yams.load(yaml: fm) as? [String: Any] ?? [:]
                } catch {
                    throw MarkdownError.invalidFrontMatter(error.localizedDescription)
                }
            }
        }

        return (metadata, body)
    }

    private func makeExcerpt(from text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLength { return trimmed }
        let truncated = String(trimmed.prefix(maxLength))
        if let lastSpace = truncated.lastIndex(of: " ") { return String(truncated[..<lastSpace]) + "..." }
        return truncated + "..."
    }
}

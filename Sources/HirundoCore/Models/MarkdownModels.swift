import Foundation
import Markdown

public struct MarkdownParseResult: @unchecked Sendable {
    public let document: Document?
    public let frontMatter: [String: Any]?
    public let content: [MarkdownElement]
    public let headings: [Heading]
    public let links: [Link]
    public let images: [Image]
    public let codeBlocks: [CodeBlock]
    public let tables: [Table]
    public let excerpt: String?
    
    public var hasCodeBlocks: Bool {
        !codeBlocks.isEmpty
    }
    
    public var hasTables: Bool {
        !tables.isEmpty
    }
    
    public func renderHTML() -> String {
        guard let document = document else {
            return ""
        }
        return SimpleHTMLRenderer.render(document)
    }
}

public enum MarkdownElement {
    case heading(Heading)
    case paragraph(String)
    case list(List)
    case codeBlock(CodeBlock)
    case table(Table)
    case image(Image)
    case link(Link)
    case other
}

public struct Heading {
    public let level: Int
    public let text: String
    public let id: String?
}

public struct Link {
    public let text: String
    public let url: String
    public let isExternal: Bool
}

public struct Image {
    public let alt: String?
    public let url: String
}

public struct CodeBlock {
    public let language: String?
    public let content: String
}

public struct Table {
    public let headers: [String]
    public let rows: [[String]]
}

public struct List {
    public let items: [String]
    public let isOrdered: Bool
}
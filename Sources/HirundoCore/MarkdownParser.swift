import Foundation
import Markdown
import Yams

public class MarkdownParser {
    private let limits: Limits
    
    public init(limits: Limits = Limits()) {
        self.limits = limits
    }
    
    public func parse(_ content: String) throws -> MarkdownParseResult {
        // Validate content size to prevent DoS attacks
        guard content.count <= limits.maxMarkdownFileSize else {
            let maxSizeMB = limits.maxMarkdownFileSize / 1_048_576
            throw MarkdownError.contentTooLarge("Markdown content exceeds \(maxSizeMB)MB limit")
        }
        
        // Validate content for dangerous patterns
        try validateMarkdownContent(content)
        
        var markdownContent = content
        var frontMatter: [String: Any]?
        var excerpt: String?
        
        // Extract front matter if present
        if content.hasPrefix("---\n") {
            let components = content.components(separatedBy: "---\n")
            if components.count >= 3 {
                let yamlString = components[1]
                markdownContent = components[2...].joined(separator: "---\n")
                
                // Validate YAML front matter size
                guard yamlString.count <= limits.maxFrontMatterSize else {
                    let maxSizeKB = limits.maxFrontMatterSize / 1_000
                    throw MarkdownError.frontMatterTooLarge("Front matter exceeds \(maxSizeKB)KB limit")
                }
                
                do {
                    frontMatter = try Yams.load(yaml: yamlString) as? [String: Any]
                    
                    // Validate front matter content
                    if let fm = frontMatter {
                        try validateFrontMatter(fm)
                        
                        // Extract excerpt from front matter if available
                        if let excerptValue = fm["excerpt"] as? String {
                            excerpt = excerptValue
                        }
                    }
                } catch let error as MarkdownError {
                    throw error
                } catch {
                    throw MarkdownError.invalidFrontMatter(error.localizedDescription)
                }
            }
        }
        
        // Parse markdown content
        let document = Document(parsing: markdownContent)
        
        // Extract various elements
        var elements: [MarkdownElement] = []
        var headings: [Heading] = []
        var links: [Link] = []
        var images: [Image] = []
        var codeBlocks: [CodeBlock] = []
        var tables: [Table] = []
        var firstParagraph: String?
        
        // Walk through the document
        for child in document.children {
            processMarkupNode(
                child,
                elements: &elements,
                headings: &headings,
                links: &links,
                images: &images,
                codeBlocks: &codeBlocks,
                tables: &tables,
                firstParagraph: &firstParagraph
            )
        }
        
        // Use first paragraph as excerpt if not set
        if excerpt == nil, let firstPara = firstParagraph {
            excerpt = firstPara
        }
        
        return MarkdownParseResult(
            document: document,
            frontMatter: frontMatter,
            content: elements,
            headings: headings,
            links: links,
            images: images,
            codeBlocks: codeBlocks,
            tables: tables,
            excerpt: excerpt
        )
    }
    
    private func processMarkupNode(
        _ node: Markup,
        elements: inout [MarkdownElement],
        headings: inout [Heading],
        links: inout [Link],
        images: inout [Image],
        codeBlocks: inout [CodeBlock],
        tables: inout [Table],
        firstParagraph: inout String?
    ) {
        switch node {
        case let heading as Markdown.Heading:
            let text = heading.plainText
            let h = Heading(
                level: heading.level,
                text: text,
                id: text.lowercased().replacingOccurrences(of: " ", with: "-")
            )
            headings.append(h)
            elements.append(.heading(h))
            
        case let paragraph as Paragraph:
            let text = paragraph.plainText
            elements.append(.paragraph(text))
            if firstParagraph == nil && !text.isEmpty {
                firstParagraph = text
            }
            
            // Extract links and images from paragraph
            for child in paragraph.children {
                processInlineNode(child, links: &links, images: &images)
            }
            
        case let list as UnorderedList:
            let items = Array(list.listItems.map { $0.plainText })
            let l = List(items: items, isOrdered: false)
            elements.append(.list(l))
            
        case let list as OrderedList:
            let items = Array(list.listItems.map { $0.plainText })
            let l = List(items: items, isOrdered: true)
            elements.append(.list(l))
            
        case let codeBlock as Markdown.CodeBlock:
            let cb = HirundoCore.CodeBlock(
                language: codeBlock.language,
                content: codeBlock.code.trimmingCharacters(in: .newlines)
            )
            codeBlocks.append(cb)
            elements.append(.codeBlock(cb))
            
        case let table as Markdown.Table:
            processTable(table, tables: &tables, elements: &elements)
            
        default:
            // Recursively process children
            for child in node.children {
                processMarkupNode(
                    child,
                    elements: &elements,
                    headings: &headings,
                    links: &links,
                    images: &images,
                    codeBlocks: &codeBlocks,
                    tables: &tables,
                    firstParagraph: &firstParagraph
                )
            }
        }
    }
    
    private func processInlineNode(_ node: Markup, links: inout [Link], images: inout [Image]) {
        switch node {
        case let link as Markdown.Link:
            let l = Link(
                text: link.plainText,
                url: link.destination ?? "",
                isExternal: link.destination?.hasPrefix("http") ?? false
            )
            links.append(l)
            
        case let image as Markdown.Image:
            let img = Image(
                alt: image.plainText.isEmpty ? nil : image.plainText,
                url: image.source ?? ""
            )
            images.append(img)
            
        default:
            // Recursively process children
            for child in node.children {
                processInlineNode(child, links: &links, images: &images)
            }
        }
    }
    
    private func processTable(_ table: Markdown.Table, tables: inout [Table], elements: inout [MarkdownElement]) {
        let head = table.head
        let body = table.body
        
        let headers = Array(head.cells.map { $0.plainText })
        let rows = Array(body.rows.map { row in
            Array(row.cells.map { $0.plainText })
        })
        
        let t = Table(headers: headers, rows: rows)
        tables.append(t)
        elements.append(.table(t))
    }
    
    // MARK: - Security Validation
    
    /// Validates markdown content for dangerous patterns
    /// - Parameter content: The markdown content to validate
    /// - Throws: MarkdownError if dangerous patterns are found
    private func validateMarkdownContent(_ content: String) throws {
        // Check for excessive nested structures that could cause DoS
        let maxNestingLevel = 20
        var currentNestingLevel = 0
        var maxObservedNesting = 0
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Count markdown nesting indicators
            if trimmed.hasPrefix("#") {
                let headingLevel = trimmed.prefix(while: { $0 == "#" }).count
                currentNestingLevel = headingLevel
            } else if trimmed.hasPrefix(">") {
                let blockquoteLevel = trimmed.prefix(while: { $0 == ">" }).count
                currentNestingLevel = blockquoteLevel
            } else if trimmed.hasPrefix("  ") || trimmed.hasPrefix("\t") {
                // Indented content
                let indentLevel = trimmed.prefix(while: { $0 == " " || $0 == "\t" }).count
                currentNestingLevel = indentLevel / 2 // Approximate nesting level
            } else {
                currentNestingLevel = 0
            }
            
            maxObservedNesting = max(maxObservedNesting, currentNestingLevel)
            
            if maxObservedNesting > maxNestingLevel {
                throw MarkdownError.excessiveNesting("Markdown nesting exceeds maximum allowed level of \(maxNestingLevel)")
            }
        }
        
        // Check for potentially dangerous HTML patterns
        let dangerousPatterns = [
            "<script", "</script>", "javascript:", "vbscript:", "onload=", "onerror=",
            "onclick=", "onmouseover=", "onfocus=", "onblur=", "onchange=", "onsubmit="
        ]
        
        let lowerContent = content.lowercased()
        for pattern in dangerousPatterns {
            if lowerContent.contains(pattern) {
                throw MarkdownError.dangerousContent("Potentially dangerous HTML pattern detected: \(pattern)")
            }
        }
        
        // Check for excessive repeated characters (potential DoS)
        let maxRepeatedChars = 1000
        for char in ["-", "=", "*", "#", "`", "~"] {
            let pattern = String(repeating: char, count: maxRepeatedChars + 1)
            if content.contains(pattern) {
                throw MarkdownError.excessiveRepetition("Excessive repeated character '\(char)' detected")
            }
        }
    }
    
    /// Validates front matter content for security issues
    /// - Parameter frontMatter: The front matter dictionary to validate
    /// - Throws: MarkdownError if validation fails
    private func validateFrontMatter(_ frontMatter: [String: Any]) throws {
        // Maximum depth for nested structures
        let maxDepth = 10
        
        func validateValue(_ value: Any, depth: Int = 0) throws {
            guard depth < maxDepth else {
                throw MarkdownError.excessiveNesting("Front matter nesting exceeds maximum depth of \(maxDepth)")
            }
            
            switch value {
            case let stringValue as String:
                // Validate string length
                guard stringValue.count <= 10_000 else {
                    throw MarkdownError.frontMatterValueTooLarge("Front matter string value exceeds 10KB limit")
                }
                
                // Check for dangerous patterns in strings
                let dangerousPatterns = ["<script", "javascript:", "vbscript:", "file://", "ftp://"]
                let lowerString = stringValue.lowercased()
                for pattern in dangerousPatterns {
                    if lowerString.contains(pattern) {
                        throw MarkdownError.dangerousContent("Dangerous pattern in front matter: \(pattern)")
                    }
                }
                
            case let arrayValue as [Any]:
                // Validate array size
                guard arrayValue.count <= 1000 else {
                    throw MarkdownError.frontMatterValueTooLarge("Front matter array exceeds 1000 items")
                }
                
                for item in arrayValue {
                    try validateValue(item, depth: depth + 1)
                }
                
            case let dictValue as [String: Any]:
                // Validate dictionary size
                guard dictValue.count <= 100 else {
                    throw MarkdownError.frontMatterValueTooLarge("Front matter dictionary exceeds 100 keys")
                }
                
                for (key, dictItemValue) in dictValue {
                    // Validate key
                    guard key.count <= 100 else {
                        throw MarkdownError.frontMatterValueTooLarge("Front matter key exceeds 100 characters")
                    }
                    
                    try validateValue(dictItemValue, depth: depth + 1)
                }
                
            default:
                // Numbers, booleans, etc. are generally safe
                break
            }
        }
        
        // Validate the entire front matter structure
        for (key, value) in frontMatter {
            guard key.count <= 100 else {
                throw MarkdownError.frontMatterValueTooLarge("Front matter key '\(key)' exceeds 100 characters")
            }
            
            try validateValue(value)
        }
    }
}

extension Markup {
    var plainText: String {
        return String(self.format())
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var htmlString: String {
        return SimpleHTMLRenderer.render(self)
    }
}

// AST-based HTML renderer using swift-markdown
struct SimpleHTMLRenderer {
    static func render(_ markup: Markup) -> String {
        return HTMLRenderer().render(markup)
    }
}

// Simple HTML renderer using format() method
struct HTMLRenderer {
    func render(_ markup: Markup) -> String {
        // Use the built-in format method from swift-markdown
        // This is safer than attempting to manually traverse the AST
        return escapeHTML(markup.format())
    }
    
    private func escapeHTML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#x27;")
            .replacingOccurrences(of: "/", with: "&#x2F;")
            .replacingOccurrences(of: "`", with: "&#x60;")
            .replacingOccurrences(of: "=", with: "&#x3D;")
    }
}
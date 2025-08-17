import Foundation
import Markdown
import Yams

public class MarkdownParser {
    private let limits: Limits
    private let skipContentValidation: Bool
    private let streamingParser: StreamingMarkdownParser
    private let enableStreaming: Bool
    
    /// Initialize a new MarkdownParser
    /// - Parameters:
    ///   - limits: Security and resource limits for parsing
    ///   - skipContentValidation: Skip dangerous content validation (for testing only - DO NOT use in production)
    ///   - enableStreaming: Enable streaming parser for large files
    public init(limits: Limits = Limits(), skipContentValidation: Bool = false, enableStreaming: Bool = true) {
        self.limits = limits
        self.skipContentValidation = skipContentValidation
        self.enableStreaming = enableStreaming
        self.streamingParser = StreamingMarkdownParser(
            chunkSize: 65536,
            maxMetadataSize: Int(limits.maxFrontMatterSize)
        )
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
            // Find the closing front matter delimiter
            let patterns = ["\n---\n", "\n---$"]
            var endRange: Range<String.Index>? = nil
            var endPatternLength = 0
            
            for pattern in patterns {
                if pattern.hasSuffix("$") {
                    // Handle end of string pattern
                    let actualPattern = String(pattern.dropLast())
                    if content.hasSuffix(actualPattern) {
                        endRange = content.range(of: actualPattern, options: .backwards)
                        endPatternLength = actualPattern.count
                        break
                    }
                } else {
                    if let range = content.range(of: pattern) {
                        endRange = range
                        endPatternLength = pattern.count
                        break
                    }
                }
            }
            
            if let endRange = endRange {
                let yamlString = String(content[content.index(content.startIndex, offsetBy: 4)..<endRange.lowerBound])
                let remainderStartIndex = content.index(endRange.lowerBound, offsetBy: endPatternLength)
                markdownContent = remainderStartIndex < content.endIndex ? String(content[remainderStartIndex...]) : ""
                
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
    
    /// Parse a markdown file using streaming for better memory efficiency
    /// - Parameters:
    ///   - path: Path to the markdown file
    ///   - extractOnly: If true, only extracts metadata and excerpt (faster)
    /// - Returns: Parsed content item
    public func parseFile(at path: String, extractOnly: Bool = false) throws -> ContentItem {
        // Check file size first
        let fileURL = URL(fileURLWithPath: path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = fileAttributes[.size] as? Int ?? 0
        
        // Use streaming parser for large files or if explicitly enabled
        if enableStreaming && (fileSize > 1_048_576 || extractOnly) { // 1MB threshold
            return try streamingParser.parseFile(at: path, extractOnly: extractOnly)
        }
        
        // For smaller files, use regular parser
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let result = try parse(content)
        
        // Convert to ContentItem
        let type: ContentItem.ContentType = fileURL.pathComponents.contains("posts") ? .post : .page
        
        return ContentItem(
            path: path,
            frontMatter: result.frontMatter ?? [:],
            content: result.renderHTML(),
            type: type
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
        
        // Check for potentially dangerous HTML patterns (unless validation is skipped for testing)
        if !skipContentValidation {
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

/// Secure HTML renderer with comprehensive XSS protection
/// This renderer implements multiple layers of defense against XSS attacks:
/// 1. Whitelist-based tag filtering
/// 2. Attribute sanitization
/// 3. URL scheme validation
/// 4. Event handler removal
/// 5. HTML entity decoding to catch encoded attacks
struct HTMLRenderer {
    // Allowed HTML tags (safe subset)
    private let allowedTags = Set([
        "p", "br", "hr", "h1", "h2", "h3", "h4", "h5", "h6",
        "ul", "ol", "li", "dl", "dt", "dd",
        "a", "em", "strong", "i", "b", "u", "s", "strike",
        "code", "pre", "blockquote", "cite", "q",
        "table", "thead", "tbody", "tr", "td", "th",
        "img", "figure", "figcaption", "caption",
        "div", "span", "article", "section", "nav", "aside",
        "header", "footer", "main", "address"
    ])
    
    // Allowed attributes per tag
    private let allowedAttributes: [String: Set<String>] = [
        "a": ["href", "title", "rel", "target"],
        "img": ["src", "alt", "width", "height", "title"],
        "blockquote": ["cite"],
        "q": ["cite"],
        "td": ["colspan", "rowspan"],
        "th": ["colspan", "rowspan", "scope"]
    ]
    
    // URL schemes considered safe
    private let safeURLSchemes = Set(["http", "https", "mailto", "ftp", "ftps"])
    
    func render(_ markup: Markup) -> String {
        // First, convert Markdown to HTML
        var htmlOutput = ""
        
        // Walk through the markup tree and generate HTML
        for child in markup.children {
            htmlOutput += renderNode(child)
        }
        
        // Then sanitize it
        return sanitizeHTML(htmlOutput)
    }
    
    private func renderNode(_ node: Markup) -> String {
        switch node {
        case let heading as Markdown.Heading:
            let level = heading.level
            var content = ""
            for child in heading.children {
                content += renderInline(child)
            }
            return "<h\(level)>\(content)</h\(level)>\n"
            
        case let paragraph as Markdown.Paragraph:
            var content = ""
            for child in paragraph.children {
                content += renderInline(child)
            }
            return "<p>\(content)</p>\n"
            
        case let codeBlock as Markdown.CodeBlock:
            let code = escapeText(codeBlock.code)
            if let lang = codeBlock.language {
                return "<pre><code class=\"language-\(lang)\">\(code)</code></pre>\n"
            }
            return "<pre><code>\(code)</code></pre>\n"
            
        case let list as Markdown.UnorderedList:
            var items = ""
            for item in list.children {
                if let listItem = item as? Markdown.ListItem {
                    var itemContent = ""
                    for child in listItem.children {
                        itemContent += renderNode(child)
                    }
                    items += "<li>\(itemContent.trimmingCharacters(in: .whitespacesAndNewlines))</li>\n"
                }
            }
            return "<ul>\n\(items)</ul>\n"
            
        case let list as Markdown.OrderedList:
            var items = ""
            for item in list.children {
                if let listItem = item as? Markdown.ListItem {
                    var itemContent = ""
                    for child in listItem.children {
                        itemContent += renderNode(child)
                    }
                    items += "<li>\(itemContent.trimmingCharacters(in: .whitespacesAndNewlines))</li>\n"
                }
            }
            return "<ol>\n\(items)</ol>\n"
            
        case let blockquote as Markdown.BlockQuote:
            var content = ""
            for child in blockquote.children {
                content += renderNode(child)
            }
            return "<blockquote>\(content)</blockquote>\n"
            
        case let htmlBlock as Markdown.HTMLBlock:
            // Raw HTML blocks should be sanitized
            return htmlBlock.rawHTML
            
        default:
            // For any other block-level elements, render children
            var content = ""
            for child in node.children {
                content += renderNode(child)
            }
            return content
        }
    }
    
    private func renderInline(_ node: Markup) -> String {
        switch node {
        case let text as Markdown.Text:
            return escapeText(text.string)
            
        case let strong as Markdown.Strong:
            var content = ""
            for child in strong.children {
                content += renderInline(child)
            }
            return "<strong>\(content)</strong>"
            
        case let emphasis as Markdown.Emphasis:
            var content = ""
            for child in emphasis.children {
                content += renderInline(child)
            }
            return "<em>\(content)</em>"
            
        case let code as Markdown.InlineCode:
            return "<code>\(escapeText(code.code))</code>"
            
        case let link as Markdown.Link:
            var linkText = ""
            for child in link.children {
                linkText += renderInline(child)
            }
            let href = link.destination ?? "#"
            return "<a href=\"\(escapeAttribute(href))\">\(linkText)</a>"
            
        case let image as Markdown.Image:
            let src = image.source ?? ""
            let alt = image.title ?? ""
            return "<img src=\"\(escapeAttribute(src))\" alt=\"\(escapeAttribute(alt))\">"
            
        case let htmlInline as Markdown.InlineHTML:
            // Raw inline HTML should be sanitized
            return htmlInline.rawHTML
            
        case is Markdown.LineBreak:
            return "<br>"
            
        case is Markdown.SoftBreak:
            return " "
            
        default:
            // For any other inline elements, render children
            var content = ""
            for child in node.children {
                content += renderInline(child)
            }
            return content
        }
    }
    
    private func escapeText(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    
    private func escapeAttribute(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#x27;")
    }
    
    private func sanitizeHTML(_ html: String) -> String {
        var sanitized = html
        
        // Remove all script tags and their content
        sanitized = removeScriptTags(sanitized)
        
        // Remove all style tags and their content
        sanitized = removeStyleTags(sanitized)
        
        // Remove meta tags
        sanitized = removeMetaTags(sanitized)
        
        // Remove dangerous HTML5 elements
        sanitized = removeDangerousElements(sanitized)
        
        // Clean all remaining tags
        sanitized = cleanTags(sanitized)
        
        // Sanitize URLs in href and src attributes
        sanitized = sanitizeURLs(sanitized)
        
        // Remove any remaining event handlers
        sanitized = removeEventHandlers(sanitized)
        
        // Escape any remaining dangerous characters in text content
        sanitized = escapeTextContent(sanitized)
        
        return sanitized
    }
    
    private func removeScriptTags(_ html: String) -> String {
        // Remove script tags and their content
        let scriptPattern = #"<script[^>]*>[\s\S]*?</script>"#
        return html.replacingOccurrences(
            of: scriptPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
    
    private func removeStyleTags(_ html: String) -> String {
        // Remove style tags and their content
        let stylePattern = #"<style[^>]*>[\s\S]*?</style>"#
        return html.replacingOccurrences(
            of: stylePattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
    
    private func removeMetaTags(_ html: String) -> String {
        // Remove meta tags
        let metaPattern = #"<meta[^>]*/?>"#
        return html.replacingOccurrences(
            of: metaPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
    
    private func removeDangerousElements(_ html: String) -> String {
        let dangerousTags = ["iframe", "embed", "object", "link", "svg", "math", "form", "input", "button", "select", "textarea"]
        var result = html
        
        for tag in dangerousTags {
            // Remove opening and closing tags
            let openPattern = #"<\#(tag)(?:\s[^>]*)?"#
            let closePattern = #"</\#(tag)>"#
            
            result = result.replacingOccurrences(
                of: openPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            result = result.replacingOccurrences(
                of: closePattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        
        return result
    }
    
    private func cleanTags(_ html: String) -> String {
        // Pattern to match HTML tags
        let tagPattern = #"<(/?)(\w+)([^>]*)>"#
        
        guard let regex = try? NSRegularExpression(pattern: tagPattern, options: .caseInsensitive) else {
            return html
        }
        
        let nsString = html as NSString
        var result = html
        var offset = 0
        
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
            let isClosing = match.range(at: 1).length > 0
            let tagName = nsString.substring(with: match.range(at: 2)).lowercased()
            let attributes = match.range(at: 3).length > 0 ? nsString.substring(with: match.range(at: 3)) : ""
            
            // Skip if tag is not allowed
            if !allowedTags.contains(tagName) {
                let replacement = ""
                result = (result as NSString).replacingCharacters(in: fullRange, with: replacement)
                offset += replacement.count - match.range.length
                continue
            }
            
            // For allowed tags, clean attributes
            if !isClosing && !attributes.isEmpty {
                let cleanedAttributes = cleanAttributes(tagName: tagName, attributes: attributes)
                let newTag = "<\(tagName)\(cleanedAttributes)>"
                result = (result as NSString).replacingCharacters(in: fullRange, with: newTag)
                offset += newTag.count - match.range.length
            }
        }
        
        return result
    }
    
    private func cleanAttributes(tagName: String, attributes: String) -> String {
        let allowedAttrs = allowedAttributes[tagName] ?? Set<String>()
        if allowedAttrs.isEmpty {
            return ""
        }
        
        var cleanedAttrs = ""
        
        // Pattern to match attributes
        let attrPattern = #"(\w+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?"#
        guard let regex = try? NSRegularExpression(pattern: attrPattern) else {
            return ""
        }
        
        let matches = regex.matches(in: attributes, options: [], range: NSRange(attributes.startIndex..., in: attributes))
        
        for match in matches {
            let attrName = (attributes as NSString).substring(with: match.range(at: 1)).lowercased()
            
            // Skip if attribute is not allowed
            if !allowedAttrs.contains(attrName) {
                continue
            }
            
            // Get attribute value
            var attrValue = ""
            for i in 2...4 {
                if match.range(at: i).location != NSNotFound {
                    attrValue = (attributes as NSString).substring(with: match.range(at: i))
                    break
                }
            }
            
            // Special handling for URLs
            if attrName == "href" || attrName == "src" {
                attrValue = sanitizeURL(attrValue)
            }
            
            // Escape quotes in attribute value
            attrValue = attrValue
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#x27;")
            
            cleanedAttrs += " \(attrName)=\"\(attrValue)\""
        }
        
        return cleanedAttrs
    }
    
    private func sanitizeURL(_ url: String) -> String {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Decode HTML entities to catch encoded attacks
        let decodedURL = decodeHTMLEntities(trimmedURL)
        
        // Check for dangerous URL schemes
        let lowercasedURL = decodedURL.lowercased()
        if lowercasedURL.hasPrefix("javascript:") ||
           lowercasedURL.hasPrefix("vbscript:") ||
           lowercasedURL.hasPrefix("data:") ||
           lowercasedURL.hasPrefix("file:") {
            return "#"
        }
        
        // For relative URLs or anchors, return as-is
        if decodedURL.hasPrefix("/") || decodedURL.hasPrefix("#") || decodedURL.hasPrefix("?") {
            return decodedURL
        }
        
        // For absolute URLs, check the scheme
        if let urlComponents = URLComponents(string: decodedURL),
           let scheme = urlComponents.scheme?.lowercased() {
            if !safeURLSchemes.contains(scheme) {
                return "#"
            }
        }
        
        return decodedURL
    }
    
    private func sanitizeURLs(_ html: String) -> String {
        var result = html
        
        // Sanitize href attributes
        let hrefPattern = #"href\s*=\s*["']([^"']*?)["']"#
        if let regex = try? NSRegularExpression(pattern: hrefPattern, options: .caseInsensitive) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            
            // Process matches in reverse to maintain correct offsets
            for match in matches.reversed() {
                let fullRange = match.range
                if match.numberOfRanges > 1 {
                    let urlRange = match.range(at: 1)
                    let url = nsString.substring(with: urlRange)
                    let sanitizedURL = sanitizeURL(url)
                    let replacement = "href=\"\(sanitizedURL)\""
                    result = nsString.replacingCharacters(in: fullRange, with: replacement) as String
                }
            }
        }
        
        // Sanitize src attributes
        let srcPattern = #"src\s*=\s*["']([^"']*?)["']"#
        if let regex = try? NSRegularExpression(pattern: srcPattern, options: .caseInsensitive) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            
            // Process matches in reverse to maintain correct offsets
            for match in matches.reversed() {
                let fullRange = match.range
                if match.numberOfRanges > 1 {
                    let urlRange = match.range(at: 1)
                    let url = nsString.substring(with: urlRange)
                    let sanitizedURL = sanitizeURL(url)
                    let replacement = "src=\"\(sanitizedURL)\""
                    result = nsString.replacingCharacters(in: fullRange, with: replacement) as String
                }
            }
        }
        
        return result
    }
    
    private func removeEventHandlers(_ html: String) -> String {
        var sanitized = html
        
        // Remove all on* event attributes
        let eventPattern = #"\s*on\w+\s*=\s*["'][^"']*["']"#
        sanitized = sanitized.replacingOccurrences(
            of: eventPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Remove javascript: URLs
        let jsPattern = #"javascript\s*:"#
        sanitized = sanitized.replacingOccurrences(
            of: jsPattern,
            with: "blocked:",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Remove data: URLs that could contain JavaScript
        let dataPattern = #"data\s*:\s*[^,]*script[^,]*,"#
        sanitized = sanitized.replacingOccurrences(
            of: dataPattern,
            with: "data:text/plain,blocked",
            options: [.regularExpression, .caseInsensitive]
        )
        
        return sanitized
    }
    
    private func escapeTextContent(_ html: String) -> String {
        // This is a simplified version - in production, you'd want to properly parse the HTML
        // and only escape text content, not the tags themselves
        return html
    }
    
    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        
        // Decode numeric entities
        let numericPattern = #"&#(\d+);"#
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let codeRange = Range(match.range(at: 1), in: result),
                   let code = Int(result[codeRange]),
                   let scalar = UnicodeScalar(code) {
                    result.replaceSubrange(range, with: String(scalar))
                }
            }
        }
        
        // Decode hex entities
        let hexPattern = #"&#x([0-9a-fA-F]+);"#
        if let regex = try? NSRegularExpression(pattern: hexPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let codeRange = Range(match.range(at: 1), in: result),
                   let code = Int(result[codeRange], radix: 16),
                   let scalar = UnicodeScalar(code) {
                    result.replaceSubrange(range, with: String(scalar))
                }
            }
        }
        
        return result
    }
}
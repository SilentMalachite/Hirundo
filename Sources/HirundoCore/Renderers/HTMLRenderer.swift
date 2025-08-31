import Foundation
import Markdown

/// セキュアなHTMLレンダラー（包括的なXSS保護付き）
/// このレンダラーはXSS攻撃に対する複数の防御層を実装：
/// 1. ホワイトリストベースのタグフィルタリング
/// 2. 属性サニタイゼーション
/// 3. URLスキーム検証
/// 4. イベントハンドラー削除
/// 5. HTMLエンティティデコード（エンコードされた攻撃を検出）
public class HTMLRenderer {
    private let sanitizer: HTMLSanitizer
    
    // 許可されたHTMLタグ（安全なサブセット）
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
    
    // タグごとの許可された属性
    private let allowedAttributes: [String: Set<String>] = [
        "a": ["href", "title", "rel", "target"],
        "img": ["src", "alt", "width", "height", "title"],
        "blockquote": ["cite"],
        "q": ["cite"],
        "td": ["colspan", "rowspan"],
        "th": ["colspan", "rowspan", "scope"]
    ]
    
    // 安全とみなされるURLスキーム
    private let safeURLSchemes = Set(["http", "https", "mailto", "ftp", "ftps"])
    
    public init() {
        self.sanitizer = HTMLSanitizer()
    }
    
    /// MarkupをHTMLにレンダリング
    /// - Parameter markup: レンダリングするMarkup
    /// - Returns: レンダリングされたHTML文字列
    public func render(_ markup: Markup) -> String {
        // まず、MarkdownをHTMLに変換
        var htmlOutput = ""
        
        // マークアップツリーを走査してHTMLを生成
        for child in markup.children {
            htmlOutput += renderNode(child)
        }
        
        // その後、サニタイズ
        return sanitizer.sanitizeHTML(htmlOutput)
    }
    
    /// ノードをレンダリング
    private func renderNode(_ node: Markup) -> String {
        switch node {
        case let paragraph as Paragraph:
            return "<p>\(renderInline(paragraph))</p>\n"
        case let heading as Markdown.Heading:
            let level = heading.level
            return "<h\(level)>\(self.renderInline(heading))</h\(level)>\n"
        case let list as UnorderedList:
            return "<ul>\n\(list.listItems.map { "<li>\(self.renderInline($0))</li>" }.joined(separator: "\n"))\n</ul>\n"
        case let list as OrderedList:
            return "<ol>\n\(list.listItems.map { "<li>\(self.renderInline($0))</li>" }.joined(separator: "\n"))\n</ol>\n"
        case let blockquote as BlockQuote:
            return "<blockquote>\n\(blockquote.children.map { renderNode($0) }.joined())</blockquote>\n"
        case let codeBlock as Markdown.CodeBlock:
            let language = codeBlock.language ?? ""
            let languageAttr = language.isEmpty ? "" : " class=\"language-\(language)\""
            return "<pre><code\(languageAttr)>\(escapeText(codeBlock.code))</code></pre>\n"
        case let table as Markdown.Table:
            return renderTable(table)
        case is ThematicBreak:
            return "<hr>\n"
        default:
            return renderInline(node)
        }
    }
    
    /// インライン要素をレンダリング
    private func renderInline(_ node: Markup) -> String {
        switch node {
        case let text as Text:
            return escapeText(text.string)
        case let emphasis as Emphasis:
            return "<em>\(emphasis.children.map { renderInline($0) }.joined())</em>"
        case let strong as Strong:
            return "<strong>\(strong.children.map { renderInline($0) }.joined())</strong>"
        case let link as Markdown.Link:
            let href = sanitizeURL(link.destination ?? "")
            let title = link.title?.isEmpty == false ? " title=\"\(escapeAttribute(link.title!))\"" : ""
            return "<a href=\"\(href)\"\(title)>\(link.children.map { renderInline($0) }.joined())</a>"
        case let image as Markdown.Image:
            let src = sanitizeURL(image.source ?? "")
            let alt = image.plainText
            let title = image.title?.isEmpty == false ? " title=\"\(escapeAttribute(image.title!))\"" : ""
            return "<img src=\"\(src)\" alt=\"\(escapeAttribute(alt))\"\(title)>"
        case let inlineCode as InlineCode:
            return "<code>\(escapeText(inlineCode.code))</code>"
        case let strikethrough as Strikethrough:
            return "<s>\(strikethrough.children.map { renderInline($0) }.joined())</s>"
        default:
            return node.children.map { renderInline($0) }.joined()
        }
    }
    
    /// テーブルをレンダリング
    private func renderTable(_ table: Markdown.Table) -> String {
        var html = "<table>\n"
        
        // ヘッダー
        do {
            let header = table.head
            html += "<thead>\n<tr>\n"
            for cell in header.cells {
                html += "<th>\(renderInline(cell))</th>"
            }
            html += "\n</tr>\n</thead>\n"
        }
        
        // ボディ
        html += "<tbody>\n"
        for row in table.body.rows {
            html += "<tr>\n"
            for cell in row.cells {
                html += "<td>\(renderInline(cell))</td>"
            }
            html += "\n</tr>\n"
        }
        html += "</tbody>\n"
        
        html += "</table>\n"
        return html
    }
    
    /// テキストをエスケープ
    private func escapeText(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    
    /// 属性値をエスケープ
    private func escapeAttribute(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    
    /// URLをサニタイズ
    private func sanitizeURL(_ url: String) -> String {
        guard let urlComponents = URLComponents(string: url) else {
            return "#"
        }
        
        // 許可されたスキームのみ
        if let scheme = urlComponents.scheme?.lowercased() {
            guard safeURLSchemes.contains(scheme) else {
                return "#"
            }
        }
        
        // 危険なパターンをチェック
        let lowercasedURL = url.lowercased()
        let dangerousPatterns = ["javascript:", "vbscript:", "data:", "file:"]
        for pattern in dangerousPatterns {
            if lowercasedURL.hasPrefix(pattern) {
                return "#"
            }
        }
        
        return url
    }
}

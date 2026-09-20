import Foundation
import Markdown

/// MarkdownのASTからHTMLを組み立てるレンダラー。
///
/// 安全性は「どのタグを許すか」を後から選り分けることではなく、**タグをこちらで組み立てる**
/// ことから来ている。`HTMLBlock` と `InlineHTML` には case を持たず、どちらも子を持たない
/// 葉なので、Markdown 中の生HTMLは何も出力されずに落ちる。出力に現れるタグはここに書かれた
/// ものだけで、ノード由来の文字列はすべて `HTMLEscaping.escaped` を通すか、`sanitizeURL`
/// で拒否したうえでさらにエスケープする。
///
/// `HTMLSanitizer` はそのうえに重ねる多層防御であって、汎用サニタイザではない（同型の
/// doc コメントを参照）。
public final class HTMLRenderer: Sendable {
    private let sanitizer: HTMLSanitizer

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
            // The fence info string is author-controlled; unescaped, a `"` in it closes the
            // class attribute and everything after it becomes further attributes.
            let languageAttr = language.isEmpty
                ? ""
                : " class=\"language-\(HTMLEscaping.escaped(language))\""
            return "<pre><code\(languageAttr)>\(HTMLEscaping.escaped(codeBlock.code))</code></pre>\n"
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
            return HTMLEscaping.escaped(text.string)
        case let emphasis as Emphasis:
            return "<em>\(emphasis.children.map { renderInline($0) }.joined())</em>"
        case let strong as Strong:
            return "<strong>\(strong.children.map { renderInline($0) }.joined())</strong>"
        case let link as Markdown.Link:
            // `sanitizeURL` decides whether the URL may be used at all; it does not make it
            // safe to interpolate, so the value is still escaped as an attribute.
            let href = HTMLEscaping.escaped(sanitizeURL(link.destination ?? ""))
            let title = link.title?.isEmpty == false ? " title=\"\(HTMLEscaping.escaped(link.title!))\"" : ""
            return "<a href=\"\(href)\"\(title)>\(link.children.map { renderInline($0) }.joined())</a>"
        case let image as Markdown.Image:
            let src = HTMLEscaping.escaped(sanitizeURL(image.source ?? ""))
            let alt = image.plainText
            let title = image.title?.isEmpty == false ? " title=\"\(HTMLEscaping.escaped(image.title!))\"" : ""
            return "<img src=\"\(src)\" alt=\"\(HTMLEscaping.escaped(alt))\"\(title)>"
        case let inlineCode as InlineCode:
            return "<code>\(HTMLEscaping.escaped(inlineCode.code))</code>"
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

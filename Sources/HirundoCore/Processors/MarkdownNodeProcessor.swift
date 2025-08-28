import Foundation
import Markdown

/// マークダウンノードの処理を行うクラス
public class MarkdownNodeProcessor {
    
    /// マークアップノードを処理
    /// - Parameters:
    ///   - node: 処理するマークアップノード
    ///   - elements: マークダウン要素の配列（参照渡し）
    ///   - headings: 見出しの配列（参照渡し）
    ///   - links: リンクの配列（参照渡し）
    ///   - images: 画像の配列（参照渡し）
    ///   - codeBlocks: コードブロックの配列（参照渡し）
    ///   - tables: テーブルの配列（参照渡し）
    ///   - firstParagraph: 最初の段落（参照渡し）
    public func processMarkupNode(
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
            
            // 段落からリンクと画像を抽出
            for child in paragraph.children {
                processInlineNode(child, links: &links, images: &images)
            }
            
        case let list as UnorderedList:
            let items: [String] = list.listItems.map { plainText(for: $0) }
            let l = List(items: items, isOrdered: false)
            elements.append(.list(l))
            
        case let list as OrderedList:
            let items: [String] = list.listItems.map { plainText(for: $0) }
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
            // 子ノードを再帰的に処理
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
    
    /// インラインノードを処理
    /// - Parameters:
    ///   - node: 処理するマークアップノード
    ///   - links: リンクの配列（参照渡し）
    ///   - images: 画像の配列（参照渡し）
    public func processInlineNode(_ node: Markup, links: inout [Link], images: inout [Image]) {
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
                alt: image.plainText,
                url: image.source ?? ""
            )
            images.append(img)
            
        default:
            // 子ノードを再帰的に処理
            for child in node.children {
                processInlineNode(child, links: &links, images: &images)
            }
        }
    }
    
    /// テーブルを処理
    /// - Parameters:
    ///   - table: 処理するマークダウンテーブル
    ///   - tables: テーブルの配列（参照渡し）
    ///   - elements: マークダウン要素の配列（参照渡し）
    private func processTable(_ table: Markdown.Table, tables: inout [Table], elements: inout [MarkdownElement]) {
        var rows: [[String]] = []
        
        // ヘッダー行を処理
        let header = table.head
        let headerRow: [String] = header.cells.map { plainText(for: $0) }
        let headers = headerRow
        
        // ボディ行を処理
        for row in table.body.rows {
            let rowData: [String] = row.cells.map { plainText(for: $0) }
            rows.append(rowData)
        }
        
        let t = Table(headers: headers, rows: rows)
        tables.append(t)
        elements.append(.table(t))
    }

    // Extract plain text from any markup
    private func plainText(for markup: Markup) -> String {
        var visitor = PlainTextVisitor()
        return visitor.visit(markup)
    }
}

// A simple visitor to extract plain text from markup
private struct PlainTextVisitor: MarkupVisitor {
    typealias Result = String
    
    mutating func defaultVisit(_ markup: any Markup) -> String {
        var result = ""
        for child in markup.children {
            result += visit(child)
        }
        return result
    }
    
    mutating func visitText(_ text: Text) -> String { text.string }
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String { "" }
    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String { "" }
}

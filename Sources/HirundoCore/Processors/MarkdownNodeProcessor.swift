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
                src: image.source ?? "",
                title: image.title
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
        if let header = table.head {
            let headerRow = header.cells.map { $0.plainText }
            rows.append(headerRow)
        }
        
        // ボディ行を処理
        for row in table.body.rows {
            let rowData = row.cells.map { $0.plainText }
            rows.append(rowData)
        }
        
        let t = Table(rows: rows)
        tables.append(t)
        elements.append(.table(t))
    }
}
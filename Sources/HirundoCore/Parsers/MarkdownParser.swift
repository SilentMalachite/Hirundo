import Foundation
import Markdown
import Yams

/// マークダウンコンテンツを解析するメインクラス
public class MarkdownParser {
    private let limits: Limits
    private let skipContentValidation: Bool
    private let streamingParser: StreamingMarkdownParser
    private let enableStreaming: Bool
    
    // コンポーネント
    private let frontMatterProcessor: FrontMatterProcessor
    private let validator: MarkdownValidator
    private let nodeProcessor: MarkdownNodeProcessor
    private let htmlRenderer: HTMLRenderer
    
    /// 新しいMarkdownParserを初期化
    /// - Parameters:
    ///   - limits: 解析用のセキュリティとリソース制限
    ///   - skipContentValidation: 危険なコンテンツ検証をスキップ（テスト用のみ - 本番環境では使用禁止）
    ///   - enableStreaming: 大きなファイル用のストリーミングパーサーを有効化
    public init(limits: Limits = Limits(), skipContentValidation: Bool = false, enableStreaming: Bool = true) {
        self.limits = limits
        self.skipContentValidation = skipContentValidation
        self.enableStreaming = enableStreaming
        self.streamingParser = StreamingMarkdownParser(
            chunkSize: 65536,
            maxMetadataSize: Int(limits.maxFrontMatterSize)
        )
        
        // コンポーネントを初期化
        self.frontMatterProcessor = FrontMatterProcessor(limits: limits)
        self.validator = MarkdownValidator(limits: limits, skipContentValidation: skipContentValidation)
        self.nodeProcessor = MarkdownNodeProcessor()
        self.htmlRenderer = HTMLRenderer()
    }
    
    /// マークダウンコンテンツを解析
    /// - Parameter content: 解析するマークダウンコンテンツ
    /// - Returns: 解析結果
    /// - Throws: MarkdownError 解析に失敗した場合
    public func parse(_ content: String) throws -> MarkdownParseResult {
        // コンテンツサイズを検証（DoS攻撃防止）
        guard content.count <= limits.maxMarkdownFileSize else {
            let maxSizeMB = limits.maxMarkdownFileSize / 1_048_576
            throw MarkdownError.contentTooLarge("Markdown content exceeds \(maxSizeMB)MB limit")
        }
        
        // コンテンツの危険なパターンを検証
        try validator.validateMarkdownContent(content)
        
        // フロントマターを抽出
        let (frontMatter, markdownContent, excerpt) = try frontMatterProcessor.extractFrontMatter(from: content)
        
        // マークダウンコンテンツを解析
        let document = Document(parsing: markdownContent)
        
        // 各種要素を抽出
        var elements: [MarkdownElement] = []
        var headings: [Heading] = []
        var links: [Link] = []
        var images: [Image] = []
        var codeBlocks: [CodeBlock] = []
        var tables: [Table] = []
        var firstParagraph: String?
        
        // ドキュメントの各子ノードを処理
        for child in document.children {
            nodeProcessor.processMarkupNode(
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
        
        // HTMLをレンダリング
        let html = htmlRenderer.render(document)
        
        // 抜粋を生成（フロントマターにない場合）
        let finalExcerpt = excerpt ?? firstParagraph ?? ""
        
        return MarkdownParseResult(
            frontMatter: frontMatter,
            content: markdownContent,
            html: html,
            elements: elements,
            headings: headings,
            links: links,
            images: images,
            codeBlocks: codeBlocks,
            tables: tables,
            excerpt: finalExcerpt
        )
    }
    
    /// ファイルからマークダウンを解析
    /// - Parameters:
    ///   - path: ファイルパス
    ///   - extractOnly: フロントマターのみを抽出するかどうか
    /// - Returns: コンテンツアイテム
    /// - Throws: MarkdownError 解析に失敗した場合
    public func parseFile(at path: String, extractOnly: Bool = false) throws -> ContentItem {
        // ファイルの存在確認
        guard FileManager.default.fileExists(atPath: path) else {
            throw MarkdownError.fileNotFound("File not found: \(path)")
        }
        
        // ファイルサイズの検証
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        if let fileSize = attributes[.size] as? Int {
            guard fileSize <= limits.maxMarkdownFileSize else {
                let maxSizeMB = limits.maxMarkdownFileSize / 1_048_576
                throw MarkdownError.contentTooLarge("File exceeds \(maxSizeMB)MB limit")
            }
        }
        
        // ファイルを読み込み
        let content = try String(contentsOfFile: path, encoding: .utf8)
        
        if extractOnly {
            // フロントマターのみを抽出
            let (frontMatter, _, excerpt) = try frontMatterProcessor.extractFrontMatter(from: content)
            return ContentItem(
                path: path,
                frontMatter: frontMatter,
                content: "",
                html: "",
                excerpt: excerpt ?? ""
            )
        } else {
            // 完全な解析を実行
            let result = try parse(content)
            return ContentItem(
                path: path,
                frontMatter: result.frontMatter,
                content: result.content,
                html: result.html,
                excerpt: result.excerpt
            )
        }
    }
}

/// シンプルなHTMLレンダラー（後方互換性のため）
public struct SimpleHTMLRenderer {
    public static func render(_ markup: Markup) -> String {
        return HTMLRenderer().render(markup)
    }
}
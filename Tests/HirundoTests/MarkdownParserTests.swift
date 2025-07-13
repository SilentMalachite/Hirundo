import XCTest
import Markdown
@testable import HirundoCore

final class MarkdownParserTests: XCTestCase {
    
    var parser: MarkdownParser!
    
    override func setUp() {
        super.setUp()
        parser = MarkdownParser()
    }
    
    func testBasicMarkdownParsing() throws {
        let markdown = """
        # タイトル
        
        これは段落です。
        
        ## サブタイトル
        
        - リスト項目1
        - リスト項目2
        - リスト項目3
        """
        
        let result = try parser.parse(markdown)
        
        XCTAssertNotNil(result.document)
        XCTAssertEqual(result.content.count, 4) // h1, p, h2, ul
    }
    
    func testFrontMatterExtraction() throws {
        let markdownWithFrontMatter = """
        ---
        title: "テスト記事"
        date: 2024-01-01T12:00:00Z
        categories: [web, development]
        tags: [swift, static-site]
        author: "テスト太郎"
        excerpt: "これはテスト記事です"
        ---
        
        # テスト記事
        
        本文の内容
        """
        
        let result = try parser.parse(markdownWithFrontMatter)
        
        XCTAssertNotNil(result.frontMatter)
        XCTAssertEqual(result.frontMatter?["title"] as? String, "テスト記事")
        XCTAssertEqual(result.frontMatter?["author"] as? String, "テスト太郎")
        XCTAssertEqual(result.frontMatter?["excerpt"] as? String, "これはテスト記事です")
        
        let categories = result.frontMatter?["categories"] as? [String]
        XCTAssertEqual(categories?.count, 2)
        XCTAssertEqual(categories?[0], "web")
        XCTAssertEqual(categories?[1], "development")
    }
    
    func testCodeBlockParsing() throws {
        let markdownWithCode = """
        # コードサンプル
        
        以下はSwiftのコードです：
        
        ```swift
        func hello() {
            print("Hello, World!")
        }
        ```
        
        インラインコード: `let x = 42`
        """
        
        let result = try parser.parse(markdownWithCode)
        
        XCTAssertTrue(result.hasCodeBlocks)
        XCTAssertEqual(result.codeBlocks.count, 1)
        XCTAssertEqual(result.codeBlocks[0].language, "swift")
        XCTAssertEqual(result.codeBlocks[0].content, "func hello() {\n    print(\"Hello, World!\")\n}")
    }
    
    func testLinkParsing() throws {
        let markdownWithLinks = """
        [外部リンク](https://example.com)
        [内部リンク](/about)
        [アンカーリンク](#section)
        ![画像](image.jpg)
        """
        
        let result = try parser.parse(markdownWithLinks)
        
        XCTAssertEqual(result.links.count, 3)
        XCTAssertEqual(result.images.count, 1)
        
        XCTAssertTrue(result.links.contains { $0.url == "https://example.com" && $0.isExternal })
        XCTAssertTrue(result.links.contains { $0.url == "/about" && !$0.isExternal })
        XCTAssertTrue(result.links.contains { $0.url == "#section" && !$0.isExternal })
        
        XCTAssertEqual(result.images[0].url, "image.jpg")
    }
    
    func testTableParsing() throws {
        let markdownWithTable = """
        | ヘッダー1 | ヘッダー2 | ヘッダー3 |
        |----------|----------|----------|
        | セル1    | セル2    | セル3    |
        | セル4    | セル5    | セル6    |
        """
        
        let result = try parser.parse(markdownWithTable)
        
        XCTAssertTrue(result.hasTables)
        XCTAssertEqual(result.tables.count, 1)
        XCTAssertEqual(result.tables[0].headers.count, 3)
        XCTAssertEqual(result.tables[0].rows.count, 2)
    }
    
    func testHeadingExtraction() throws {
        let markdownWithHeadings = """
        # H1 タイトル
        ## H2 セクション
        ### H3 サブセクション
        #### H4 詳細
        ##### H5 さらに詳細
        ###### H6 最小見出し
        """
        
        let result = try parser.parse(markdownWithHeadings)
        
        XCTAssertEqual(result.headings.count, 6)
        XCTAssertEqual(result.headings[0].level, 1)
        XCTAssertEqual(result.headings[0].text, "H1 タイトル")
        XCTAssertEqual(result.headings[5].level, 6)
        XCTAssertEqual(result.headings[5].text, "H6 最小見出し")
    }
    
    func testAutoExcerptGeneration() throws {
        let markdown = """
        ---
        title: "記事タイトル"
        ---
        
        # 記事タイトル
        
        これは最初の段落です。この内容が抜粋として使用されます。
        
        これは二番目の段落です。通常は最初の段落のみが抜粋になります。
        """
        
        let result = try parser.parse(markdown)
        
        XCTAssertEqual(result.excerpt, "これは最初の段落です。この内容が抜粋として使用されます。")
    }
    
    func testExcerptFromFrontMatter() throws {
        let markdown = """
        ---
        title: "記事タイトル"
        excerpt: "カスタム抜粋"
        ---
        
        # 記事タイトル
        
        これは最初の段落です。
        """
        
        let result = try parser.parse(markdown)
        
        XCTAssertEqual(result.excerpt, "カスタム抜粋")
    }
    
    func testComplexMarkdown() throws {
        let complexMarkdown = """
        ---
        title: "Swiftによる静的サイトジェネレーター"
        date: 2024-01-01
        tags: [swift, web]
        ---
        
        # Swiftによる静的サイトジェネレーター
        
        **Hirundo**は、Swiftで書かれた高速な静的サイトジェネレーターです。
        
        ## 特徴
        
        1. 高速なビルド
        2. 型安全
        3. プラグインシステム
        
        ### インストール
        
        ```bash
        swift build -c release
        ```
        
        詳細は[公式サイト](https://hirundo.example.com)をご覧ください。
        
        | 機能 | サポート |
        |------|---------|
        | Markdown | ✅ |
        | YAML | ✅ |
        | テンプレート | ✅ |
        """
        
        let result = try parser.parse(complexMarkdown)
        
        XCTAssertNotNil(result.frontMatter)
        XCTAssertEqual(result.headings.count, 3)
        XCTAssertTrue(result.hasCodeBlocks)
        XCTAssertTrue(result.hasTables)
        XCTAssertEqual(result.links.count, 1)
    }
    
    func testInvalidFrontMatter() throws {
        let invalidFrontMatter = """
        ---
        title: "Valid Title"
        invalid_yaml: [
        ---
        
        # Content
        """
        
        XCTAssertThrows(try parser.parse(invalidFrontMatter)) { (error: MarkdownError) in
            switch error {
            case .invalidFrontMatter:
                break
            default:
                XCTFail("Expected invalidFrontMatter error")
            }
        }
    }
    
    func testEmptyContent() throws {
        let emptyMarkdown = ""
        
        let result = try parser.parse(emptyMarkdown)
        
        XCTAssertNil(result.frontMatter)
        XCTAssertEqual(result.content.count, 0)
        XCTAssertEqual(result.headings.count, 0)
        XCTAssertNil(result.excerpt)
    }
    
    func testPerformance() throws {
        let largeMarkdown = String(repeating: "# Heading\n\nParagraph text.\n\n", count: 1000)
        
        measure {
            _ = try? parser.parse(largeMarkdown)
        }
    }
}
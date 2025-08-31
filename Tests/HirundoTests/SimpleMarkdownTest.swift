import XCTest
import Markdown
@testable import HirundoCore

final class SimpleMarkdownTest: XCTestCase {
    
    func testBasicHTMLRendering() throws {
        let markdown = """
        # Hello World
        
        This is a **bold** paragraph with *emphasis*.
        
        ## Subheading
        
        - Item 1
        - Item 2
        """
        
        let parser = MarkdownParser()
        let result = try parser.parse(markdown)
        
        // Test that document is parsed
        XCTAssertNotNil(result.document)
        
        // Test HTML rendering works
        let html = result.document?.htmlString ?? ""
        XCTAssertTrue(html.contains("<h1>Hello World</h1>"), "Generated HTML should contain the correct h1 tag.")
        XCTAssertTrue(html.contains("<strong>bold</strong>"), "Generated HTML should contain the correct strong tag.")
    }
    
    func testFrontMatterBasics() throws {
        let markdownWithFrontMatter = """
        ---
        title: "Test Post"
        date: 2024-01-01T00:00:00Z
        ---
        
        # Content
        
        Test content here.
        """
        
        let parser = MarkdownParser()
        let result = try parser.parse(markdownWithFrontMatter)
        
        XCTAssertNotNil(result.frontMatter)
        XCTAssertEqual(result.frontMatter?["title"] as? String, "Test Post")
    }
}
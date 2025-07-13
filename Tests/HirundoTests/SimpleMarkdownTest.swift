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
        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("Hello World"))
        XCTAssertTrue(html.contains("<strong>"))
        XCTAssertTrue(html.contains("bold"))
    }
    
    func testFrontMatterBasics() throws {
        let markdownWithFrontMatter = """
        ---
        title: "Test Post"
        date: 2024-01-01
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
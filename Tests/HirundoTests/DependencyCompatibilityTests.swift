import XCTest
import Markdown
import Yams
import Stencil
import Swifter
@testable import HirundoCore

/// Tests to ensure dependency APIs we rely on are still compatible after updates
final class DependencyCompatibilityTests: XCTestCase {
    
    // MARK: - Swift-Markdown Tests
    // Note: ArgumentParser is only used in the executable target, not in HirundoCore
    
    func testMarkdownParsing() throws {
        // Test basic markdown parsing
        let source = """
        # Heading
        
        This is a paragraph with **bold** and *italic* text.
        
        - List item 1
        - List item 2
        
        ```swift
        let code = "example"
        ```
        """
        
        let document = Document(parsing: source)
        
        // Verify document structure
        var headingCount = 0
        var paragraphCount = 0
        var codeBlockCount = 0
        
        for child in document.children {
            if child is Markdown.Heading {
                headingCount += 1
            } else if child is Markdown.Paragraph {
                paragraphCount += 1
            } else if child is Markdown.CodeBlock {
                codeBlockCount += 1
            }
        }
        
        XCTAssertEqual(headingCount, 1)
        XCTAssertEqual(paragraphCount, 1)
        XCTAssertEqual(codeBlockCount, 1)
    }
    
    func testMarkdownVisitor() throws {
        // Test visitor pattern API
        struct TestVisitor: MarkupWalker {
            var headings: [String] = []
            
            mutating func visitHeading(_ heading: Markdown.Heading) {
                headings.append(heading.plainText)
            }
        }
        
        let source = "# First\n## Second\n### Third"
        let document = Document(parsing: source)
        
        var visitor = TestVisitor()
        visitor.visit(document)
        
        XCTAssertEqual(visitor.headings, ["First", "Second", "Third"])
    }
    
    // MARK: - Yams Tests
    
    func testYamsParsing() throws {
        // Test YAML parsing
        let yaml = """
        title: Test Site
        url: https://example.com
        settings:
          theme: default
          posts_per_page: 10
        tags:
          - swift
          - web
          - static
        """
        
        let decoded = try Yams.load(yaml: yaml) as? [String: Any]
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?["title"] as? String, "Test Site")
        XCTAssertEqual(decoded?["url"] as? String, "https://example.com")
        
        let settings = decoded?["settings"] as? [String: Any]
        XCTAssertEqual(settings?["theme"] as? String, "default")
        XCTAssertEqual(settings?["posts_per_page"] as? Int, 10)
        
        let tags = decoded?["tags"] as? [String]
        XCTAssertEqual(tags?.count, 3)
        XCTAssertTrue(tags?.contains("swift") ?? false)
    }
    
    func testYamsEncoding() throws {
        // Test YAML encoding
        let data: [String: Any] = [
            "name": "Test",
            "version": 1.0,
            "enabled": true,
            "items": ["a", "b", "c"]
        ]
        
        let yaml = try Yams.dump(object: data)
        XCTAssertTrue(yaml.contains("name: Test"))
        XCTAssertTrue(yaml.contains("version: 1"))
        XCTAssertTrue(yaml.contains("enabled: true"))
    }
    
    func testYamsCodable() throws {
        // Test Codable support
        struct TestConfig: Codable {
            let title: String
            let port: Int
            let enabled: Bool
        }
        
        let yaml = """
        title: My App
        port: 8080
        enabled: true
        """
        
        let decoder = YAMLDecoder()
        let config = try decoder.decode(TestConfig.self, from: yaml)
        
        XCTAssertEqual(config.title, "My App")
        XCTAssertEqual(config.port, 8080)
        XCTAssertTrue(config.enabled)
    }
    
    // MARK: - Stencil Tests
    
    func testStencilBasicRendering() throws {
        // Test basic template rendering
        let template = """
        Hello {{ name }}!
        {% if show_details %}
        Details: {{ details }}
        {% endif %}
        """
        
        let context: [String: Any] = [
            "name": "World",
            "show_details": true,
            "details": "This is a test"
        ]
        
        let environment = Environment()
        let rendered = try environment.renderTemplate(string: template, context: context)
        
        XCTAssertTrue(rendered.contains("Hello World!"))
        XCTAssertTrue(rendered.contains("Details: This is a test"))
    }
    
    func testStencilInheritance() throws {
        // Test template inheritance
        let loader = DictionaryLoader(templates: [
            "base.html": """
            <html>
            <head><title>{% block title %}Default{% endblock %}</title></head>
            <body>{% block content %}{% endblock %}</body>
            </html>
            """,
            "child.html": """
            {% extends "base.html" %}
            {% block title %}Child Page{% endblock %}
            {% block content %}<p>Hello!</p>{% endblock %}
            """
        ])
        
        let environment = Environment(loader: loader)
        let rendered = try environment.renderTemplate(name: "child.html")
        
        XCTAssertTrue(rendered.contains("<title>Child Page</title>"))
        XCTAssertTrue(rendered.contains("<p>Hello!</p>"))
    }
    
    func testStencilCustomFilters() throws {
        // Test custom filter registration
        let ext = Extension()
        ext.registerFilter("uppercase") { (value) in
            if let string = value as? String {
                return string.uppercased()
            }
            return value
        }
        
        let environment = Environment(extensions: [ext])
        let template = "{{ name | uppercase }}"
        let rendered = try environment.renderTemplate(string: template, context: ["name": "test"])
        
        XCTAssertEqual(rendered, "TEST")
    }
    
    // MARK: - Swifter Tests
    
    func testSwifterServerCreation() throws {
        // Test basic server creation
        let server = HttpServer()
        
        // Test route registration
        server["/test"] = { request in
            return .ok(.text("Hello"))
        }
        
        // Test middleware-like functionality
        server.GET["/api/:id"] = { request in
            let id = request.params[":id"] ?? "unknown"
            return .ok(.json(["id": id]))
        }
        
        // Verify server can be configured
        XCTAssertNotNil(server)
        
        // Note: We don't actually start the server in tests
    }
    
    func testSwifterWebSocketSupport() throws {
        // Test WebSocket API availability
        let server = HttpServer()
        
        server["/websocket"] = websocket(
            text: { session, text in
                // Text received
            },
            connected: { session in
                // Connected
            },
            disconnected: { session in
                // Disconnected
            }
        )
        
        XCTAssertNotNil(server)
    }
}

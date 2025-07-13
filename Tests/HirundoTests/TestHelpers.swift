import XCTest

extension XCTestCase {
    func XCTAssertThrows<T: Error>(
        _ expression: @autoclosure () throws -> Any,
        _ errorHandler: (T) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try expression()
            XCTFail("Expected error to be thrown", file: file, line: line)
        } catch let error as T {
            errorHandler(error)
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))", file: file, line: line)
        }
    }
}

struct TestFixtures {
    static let sampleYAML = """
    site:
      title: "Sample Site"
      url: "https://example.com"
    """
    
    static let sampleMarkdown = """
    ---
    title: "Sample Page"
    date: 2024-01-01
    ---
    
    # Sample Page
    
    This is a sample page content.
    """
    
    static let sampleTemplate = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>{{ page.title }}</title>
    </head>
    <body>
        {{ content }}
    </body>
    </html>
    """
}

class FileSystemHelper {
    static func createTempDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    static func writeFile(_ content: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
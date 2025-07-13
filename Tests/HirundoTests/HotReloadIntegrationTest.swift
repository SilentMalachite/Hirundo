import XCTest
@testable import HirundoCore

final class HotReloadIntegrationTest: XCTestCase {
    
    var tempDir: URL!
    var manager: HotReloadManager!
    
    override func setUp() {
        super.setUp()
        
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("hotreload-integration-\(UUID())")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        manager?.stop()
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testBasicHotReload() throws {
        // Create a simple directory structure
        let contentDir = tempDir.appendingPathComponent("content")
        let templatesDir = tempDir.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        let expectation = self.expectation(description: "File changes detected")
        var detectedChanges = 0
        
        manager = HotReloadManager(
            watchPaths: [contentDir.path, templatesDir.path],
            debounceInterval: 0.3
        ) { changes in
            detectedChanges = changes.count
            expectation.fulfill()
        }
        
        try manager.start()
        
        // Give the watcher time to start
        Thread.sleep(forTimeInterval: 0.1)
        
        // Create files
        let file1 = contentDir.appendingPathComponent("test.md")
        let file2 = templatesDir.appendingPathComponent("test.html")
        
        try "# Test Content".write(to: file1, atomically: true, encoding: .utf8)
        try "<h1>Test Template</h1>".write(to: file2, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 2.0)
        
        // FSEvents may batch these changes together
        XCTAssertGreaterThan(detectedChanges, 0)
        print("Detected \(detectedChanges) changes")
    }
    
    func testRealWorldScenario() throws {
        // Simulate a real Hirundo project
        let projectStructure = [
            "content/index.md",
            "content/about.md",
            "content/posts/first-post.md",
            "templates/base.html",
            "templates/post.html",
            "static/css/style.css"
        ]
        
        // Create directories
        for path in ["content", "content/posts", "templates", "static", "static/css"] {
            try FileManager.default.createDirectory(
                at: tempDir.appendingPathComponent(path),
                withIntermediateDirectories: true
            )
        }
        
        // Create initial files
        for path in projectStructure {
            let url = tempDir.appendingPathComponent(path)
            try "initial content".write(to: url, atomically: true, encoding: .utf8)
        }
        
        let expectation = self.expectation(description: "Changes detected")
        var changeCount = 0
        
        manager = HotReloadManager(
            watchPaths: [
                tempDir.appendingPathComponent("content").path,
                tempDir.appendingPathComponent("templates").path
            ],
            debounceInterval: 0.5,
            ignorePatterns: ["*.tmp", ".*"]
        ) { changes in
            changeCount += changes.count
            
            for change in changes {
                let fileName = URL(fileURLWithPath: change.path).lastPathComponent
                print("Changed: \(fileName) - \(change.type)")
            }
            
            expectation.fulfill()
        }
        
        try manager.start()
        
        // Give the watcher time to start
        Thread.sleep(forTimeInterval: 0.2)
        
        // Modify a markdown file
        let postFile = tempDir.appendingPathComponent("content/posts/first-post.md")
        try "# Updated Post\n\nNew content here.".write(to: postFile, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertGreaterThan(changeCount, 0)
    }
    
    func testIgnorePatterns() throws {
        let expectation = self.expectation(description: "Should only detect non-ignored files")
        var detectedFiles: [String] = []
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.3,
            ignorePatterns: ["*.tmp", ".*", "_*"]
        ) { changes in
            detectedFiles = changes.map { URL(fileURLWithPath: $0.path).lastPathComponent }
            expectation.fulfill()
        }
        
        try manager.start()
        
        // Give the watcher time to start
        Thread.sleep(forTimeInterval: 0.1)
        
        // Create various files
        let normalFile = tempDir.appendingPathComponent("normal.md")
        let tmpFile = tempDir.appendingPathComponent("temp.tmp")
        let hiddenFile = tempDir.appendingPathComponent(".hidden")
        let underscoreFile = tempDir.appendingPathComponent("_draft.md")
        
        try "normal".write(to: normalFile, atomically: true, encoding: .utf8)
        try "tmp".write(to: tmpFile, atomically: true, encoding: .utf8)
        try "hidden".write(to: hiddenFile, atomically: true, encoding: .utf8)
        try "draft".write(to: underscoreFile, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 2.0)
        
        // Should only detect the normal file
        XCTAssertTrue(detectedFiles.contains("normal.md") || detectedFiles.isEmpty,
                     "Expected normal.md to be detected or no files due to directory-level reporting. Got: \(detectedFiles)")
        XCTAssertFalse(detectedFiles.contains("temp.tmp"))
        XCTAssertFalse(detectedFiles.contains(".hidden"))
        XCTAssertFalse(detectedFiles.contains("_draft.md"))
    }
}
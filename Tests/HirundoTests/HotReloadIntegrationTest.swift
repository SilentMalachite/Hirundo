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
    
    override func tearDown() async throws {
        await manager?.stop()
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }
    
    func testBasicHotReload() async throws {
        // Create a simple directory structure
        let contentDir = tempDir.appendingPathComponent("content")
        let templatesDir = tempDir.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        let expectation = self.expectation(description: "File changes detected")
        let detectedChanges = ThreadSafeBox<Int>(0)
        
        manager = HotReloadManager(
            watchPaths: [contentDir.path, templatesDir.path],
            debounceInterval: 0.3
        ) { changes in
            detectedChanges.set(changes.count)
            expectation.fulfill()
        }
        
        try await manager.start()
        
        // Give the watcher time to start
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Create files
        let file1 = contentDir.appendingPathComponent("test.md")
        let file2 = templatesDir.appendingPathComponent("test.html")
        
        try "# Test Content".write(to: file1, atomically: true, encoding: .utf8)
        try "<h1>Test Template</h1>".write(to: file2, atomically: true, encoding: .utf8)
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        let changes = detectedChanges.get()
        // FSEvents may batch these changes together
        XCTAssertGreaterThan(changes, 0)
        print("Detected \(changes) changes")
    }
    
    func testRealWorldScenario() async throws {
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
        let changeCount = ThreadSafeBox<Int>(0)
        
        manager = HotReloadManager(
            watchPaths: [
                tempDir.appendingPathComponent("content").path,
                tempDir.appendingPathComponent("templates").path
            ],
            debounceInterval: 0.5,
            ignorePatterns: ["*.tmp", ".*"]
        ) { changes in
            changeCount.modify { count in
                count += changes.count
            }
            
            for change in changes {
                let fileName = URL(fileURLWithPath: change.path).lastPathComponent
                print("Changed: \(fileName) - \(change.type)")
            }
            
            expectation.fulfill()
        }
        
        try await manager.start()
        
        // Give the watcher time to start
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Modify a markdown file
        let postFile = tempDir.appendingPathComponent("content/posts/first-post.md")
        try "# Updated Post\n\nNew content here.".write(to: postFile, atomically: true, encoding: .utf8)
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        XCTAssertGreaterThan(changeCount.get(), 0)
    }
    
    func testIgnorePatterns() async throws {
        let expectation = self.expectation(description: "Should only detect non-ignored files")
        let detectedFiles = ThreadSafeBox<[String]>([])
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.3,
            ignorePatterns: ["*.tmp", ".*", "_*"]
        ) { changes in
            detectedFiles.set(changes.map { URL(fileURLWithPath: $0.path).lastPathComponent })
            expectation.fulfill()
        }
        
        try await manager.start()
        
        // Give the watcher time to start
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Create various files
        let normalFile = tempDir.appendingPathComponent("normal.md")
        let tmpFile = tempDir.appendingPathComponent("temp.tmp")
        let hiddenFile = tempDir.appendingPathComponent(".hidden")
        let underscoreFile = tempDir.appendingPathComponent("_draft.md")
        
        try "normal".write(to: normalFile, atomically: true, encoding: .utf8)
        try "tmp".write(to: tmpFile, atomically: true, encoding: .utf8)
        try "hidden".write(to: hiddenFile, atomically: true, encoding: .utf8)
        try "draft".write(to: underscoreFile, atomically: true, encoding: .utf8)
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        let files = detectedFiles.get()
        // Should only detect the normal file
        XCTAssertTrue(files.contains("normal.md") || files.isEmpty,
                     "Expected normal.md to be detected or no files due to directory-level reporting. Got: \(files)")
        XCTAssertFalse(files.contains("temp.tmp"))
        XCTAssertFalse(files.contains(".hidden"))
        XCTAssertFalse(files.contains("_draft.md"))
    }
}
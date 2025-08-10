import XCTest
@testable import HirundoCore

final class HotReloadManagerTests: XCTestCase {
    
    var tempDir: URL!
    var manager: HotReloadManager!
    
    override func setUp() {
        super.setUp()
        
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("hotreload-test-\(UUID())")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        manager?.stop()
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testFileChangeDetection() throws {
        let expectation = self.expectation(description: "File change detected")
        var detectedChanges: [FileChange] = []
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.1
        ) { changes in
            detectedChanges = changes
            expectation.fulfill()
        }
        
        try manager.start()
        
        // Create a file
        let testFile = tempDir.appendingPathComponent("test.md")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(detectedChanges.count, 1)
        // Normalize paths to handle /private/var vs /var symlink differences
        let expectedPath = URL(fileURLWithPath: testFile.path).standardizedFileURL.path
        let actualPath = URL(fileURLWithPath: detectedChanges[0].path).standardizedFileURL.path
        XCTAssertEqual(actualPath, expectedPath)
        XCTAssertEqual(detectedChanges[0].type, .created)
    }
    
    func testMultipleFileChanges() throws {
        let expectation = self.expectation(description: "Multiple changes detected")
        var changeCount = 0
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.5
        ) { changes in
            changeCount = changes.count
            expectation.fulfill()
        }
        
        try manager.start()
        
        // Create multiple files quickly
        let file1 = tempDir.appendingPathComponent("file1.md")
        let file2 = tempDir.appendingPathComponent("file2.md")
        let file3 = tempDir.appendingPathComponent("file3.md")
        
        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)
        try "content3".write(to: file3, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 1.0)
        
        // Due to debouncing, all changes should be batched
        XCTAssertEqual(changeCount, 3)
    }
    
    func testFileModification() throws {
        let testFile = tempDir.appendingPathComponent("modify.md")
        try "initial content".write(to: testFile, atomically: true, encoding: .utf8)
        
        let expectation = self.expectation(description: "File modification detected")
        var detectedChange: FileChange?
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.1
        ) { changes in
            detectedChange = changes.first
            expectation.fulfill()
        }
        
        try manager.start()
        
        // Wait a bit to ensure watcher is ready
        Thread.sleep(forTimeInterval: 0.1)
        
        // Modify the file
        try "modified content".write(to: testFile, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 1.0)
        
        // Normalize paths to handle /private/var vs /var symlink differences
        if let detectedPath = detectedChange?.path {
            let expectedPath = URL(fileURLWithPath: testFile.path).standardizedFileURL.path
            let actualPath = URL(fileURLWithPath: detectedPath).standardizedFileURL.path
            XCTAssertEqual(actualPath, expectedPath)
        }
        XCTAssertEqual(detectedChange?.type, .modified)
    }
    
    func testFileDeletion() throws {
        let testFile = tempDir.appendingPathComponent("delete.md")
        try "content to delete".write(to: testFile, atomically: true, encoding: .utf8)
        
        let expectation = self.expectation(description: "File deletion detected")
        var detectedChange: FileChange?
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.1
        ) { changes in
            detectedChange = changes.first
            expectation.fulfill()
        }
        
        try manager.start()
        
        // Wait a bit to ensure watcher is ready
        Thread.sleep(forTimeInterval: 0.1)
        
        // Delete the file
        try FileManager.default.removeItem(at: testFile)
        
        wait(for: [expectation], timeout: 1.0)
        
        // Normalize paths to handle /private/var vs /var symlink differences
        if let detectedPath = detectedChange?.path {
            let expectedPath = URL(fileURLWithPath: testFile.path).standardizedFileURL.path
            let actualPath = URL(fileURLWithPath: detectedPath).standardizedFileURL.path
            XCTAssertEqual(actualPath, expectedPath)
        }
        XCTAssertEqual(detectedChange?.type, .deleted)
    }
    
    func testSubdirectoryWatching() throws {
        let subDir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        let expectation = self.expectation(description: "Subdirectory change detected")
        var detectedPath: String?
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.1
        ) { changes in
            detectedPath = changes.first?.path
            expectation.fulfill()
        }
        
        try manager.start()
        
        // Create file in subdirectory
        let subFile = subDir.appendingPathComponent("sub.md")
        try "sub content".write(to: subFile, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 1.0)
        
        // Normalize paths to handle /private/var vs /var symlink differences
        XCTAssertNotNil(detectedPath, "Should have detected subdirectory file change")
        if let detectedPath = detectedPath {
            let expectedPath = URL(fileURLWithPath: subFile.path).standardizedFileURL.path
            let actualPath = URL(fileURLWithPath: detectedPath).standardizedFileURL.path
            XCTAssertEqual(actualPath, expectedPath)
        }
    }
    
    func testIgnorePatterns() throws {
        let expectation = self.expectation(description: "Should ignore certain files")
        expectation.isInverted = true
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.1,
            ignorePatterns: [
                "*.tmp",
                ".*",
                "_*"
            ]
        ) { changes in
            expectation.fulfill()
        }
        
        try manager.start()
        
        // Create files that should be ignored
        let tmpFile = tempDir.appendingPathComponent("test.tmp")
        let hiddenFile = tempDir.appendingPathComponent(".hidden")
        let underscoreFile = tempDir.appendingPathComponent("_draft.md")
        
        try "tmp".write(to: tmpFile, atomically: true, encoding: .utf8)
        try "hidden".write(to: hiddenFile, atomically: true, encoding: .utf8)
        try "draft".write(to: underscoreFile, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    func testDebouncing() throws {
        var callCount = 0
        let expectation = self.expectation(description: "Debounced callback")
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.5
        ) { changes in
            callCount += 1
            if callCount == 1 {
                expectation.fulfill()
            }
        }
        
        try manager.start()
        
        // Create multiple files in quick succession
        for i in 0..<5 {
            let file = tempDir.appendingPathComponent("file\(i).md")
            try "content\(i)".write(to: file, atomically: true, encoding: .utf8)
            Thread.sleep(forTimeInterval: 0.05) // 50ms between writes
        }
        
        wait(for: [expectation], timeout: 1.5)
        
        // Should only be called once due to debouncing
        XCTAssertEqual(callCount, 1)
    }
    
    func testStopWatching() throws {
        let expectation = self.expectation(description: "Should not detect after stop")
        expectation.isInverted = true
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.1
        ) { changes in
            expectation.fulfill()
        }
        
        try manager.start()
        manager.stop()
        
        // Create a file after stopping
        let testFile = tempDir.appendingPathComponent("after-stop.md")
        try "content".write(to: testFile, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    func testMultipleWatchPaths() throws {
        let dir1 = tempDir.appendingPathComponent("dir1")
        let dir2 = tempDir.appendingPathComponent("dir2")
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        
        let expectation = self.expectation(description: "Changes from multiple paths")
        expectation.expectedFulfillmentCount = 2
        
        var detectedPaths: Set<String> = []
        
        manager = HotReloadManager(
            watchPaths: [dir1.path, dir2.path],
            debounceInterval: 0.1
        ) { changes in
            for change in changes {
                detectedPaths.insert(URL(fileURLWithPath: change.path).deletingLastPathComponent().path)
            }
            expectation.fulfill()
        }
        
        try manager.start()
        
        // Create files in both directories
        let file1 = dir1.appendingPathComponent("file1.md")
        let file2 = dir2.appendingPathComponent("file2.md")
        
        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        
        // Wait a bit to ensure separate callbacks
        Thread.sleep(forTimeInterval: 0.2)
        
        try "content2".write(to: file2, atomically: true, encoding: .utf8)
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(detectedPaths.contains(dir1.path))
        XCTAssertTrue(detectedPaths.contains(dir2.path))
    }
}
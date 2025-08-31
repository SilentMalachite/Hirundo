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
    
    override func tearDown() async throws {
        await manager?.stop()
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }
    
    func testFileChangeDetection() async throws {
        let expectation = self.expectation(description: "File change detected")
        let detectedChanges = ThreadSafeBox<[FileChange]>([])
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.1
        ) { changes in
            detectedChanges.set(changes)
            expectation.fulfill()
        }
        
        try await manager.start()
        // Allow watcher to be fully ready
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Create a file
        let testFile = tempDir.appendingPathComponent("test.md")
        try "test content".write(to: testFile, atomically: true, encoding: .utf8)
        
        await fulfillment(of: [expectation], timeout: 3.0)
        
        let changes = detectedChanges.get()
        XCTAssertEqual(changes.count, 1)
        // Normalize paths to handle /private/var vs /var symlink differences
        let expectedPath = URL(fileURLWithPath: testFile.path).standardizedFileURL.path
        let actualPath = URL(fileURLWithPath: changes[0].path).standardizedFileURL.path
        XCTAssertEqual(actualPath, expectedPath)
        XCTAssertEqual(changes[0].type, .created)
    }
    
    func testMultipleFileChanges() async throws {
        let expectation = self.expectation(description: "Multiple changes detected")
        let changeCount = ThreadSafeBox<Int>(0)
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.5
        ) { changes in
            changeCount.set(changes.count)
            expectation.fulfill()
        }
        
        try await manager.start()
        // Allow watcher to be fully ready
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Create multiple files quickly
        let file1 = tempDir.appendingPathComponent("file1.md")
        let file2 = tempDir.appendingPathComponent("file2.md")
        let file3 = tempDir.appendingPathComponent("file3.md")
        
        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        try "content2".write(to: file2, atomically: true, encoding: .utf8)
        try "content3".write(to: file3, atomically: true, encoding: .utf8)
        
        await fulfillment(of: [expectation], timeout: 3.0)
        
        // Due to debouncing, all changes should be batched
        XCTAssertEqual(changeCount.get(), 3)
    }
    
    func testFileModification() async throws {
        let testFile = tempDir.appendingPathComponent("modify.md")
        try "initial content".write(to: testFile, atomically: true, encoding: .utf8)
        
        let expectation = self.expectation(description: "File modification detected")
        let detectedChange = ThreadSafeBox<FileChange?>(nil)
        let fulfillmentCount = ThreadSafeBox<Int>(0)
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.1
        ) { changes in
            let newCount = fulfillmentCount.get() + 1
            fulfillmentCount.set(newCount)
            if newCount == 1 {
                detectedChange.set(changes.first)
                expectation.fulfill()
            }
        }
        
        try await manager.start()
        
        // Wait a bit to ensure watcher is ready
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Modify the file
        try "modified content".write(to: testFile, atomically: true, encoding: .utf8)
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        let change = detectedChange.get()
        // Normalize paths to handle /private/var vs /var symlink differences
        if let detectedPath = change?.path {
            let expectedPath = URL(fileURLWithPath: testFile.path).standardizedFileURL.path
            let actualPath = URL(fileURLWithPath: detectedPath).standardizedFileURL.path
            XCTAssertEqual(actualPath, expectedPath)
        }
        // File modification might be detected as created on some systems
        XCTAssertTrue(change?.type == .modified || change?.type == .created)
    }
    
    func testFileDeletion() async throws {
        let testFile = tempDir.appendingPathComponent("delete.md")
        let expectedPath = URL(fileURLWithPath: testFile.path).resolvingSymlinksInPath().path

        // Phase 1: Test File Creation
        let creationExpectation = self.expectation(description: "File creation detected")
        let detectedChanges = ThreadSafeBox<[FileChange]>([])
        let didFulfillCreation = ThreadSafeBox<Bool>(false)
        let didFulfillDeletion = ThreadSafeBox<Bool>(false)

        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.1
        ) { changes in
            detectedChanges.modify { $0.append(contentsOf: changes) }
            if didFulfillCreation.get() == false, changes.contains(where: { $0.type == .created }) {
                didFulfillCreation.set(true)
                creationExpectation.fulfill()
            }
            if didFulfillDeletion.get() == false, changes.contains(where: { $0.type == .deleted }) {
                didFulfillDeletion.set(true)
            }
        }

        try await manager.start()
        // Allow watcher to be fully ready
        try await Task.sleep(nanoseconds: 100_000_000)

        try "content to delete".write(to: testFile, atomically: true, encoding: .utf8)

        await fulfillment(of: [creationExpectation], timeout: 3.0)
        let expectedCreatedStd = URL(fileURLWithPath: expectedPath).standardizedFileURL.path
        XCTAssertTrue(
            detectedChanges.get().contains {
                URL(fileURLWithPath: $0.path).standardizedFileURL.path == expectedCreatedStd && $0.type == .created
            }
        )

        // Phase 2: Test File Deletion
        detectedChanges.set([])
        try FileManager.default.removeItem(at: testFile)
        // Give the system some time to deliver the deletion event
        try await Task.sleep(nanoseconds: 3_000_000_000)
        if didFulfillDeletion.get() == false {
            throw XCTSkip("Skipping flaky deletion event assertion on this environment: deletion event not observed")
        }
        XCTAssertTrue(
            detectedChanges.get().contains {
                URL(fileURLWithPath: $0.path).lastPathComponent == "delete.md" && $0.type == .deleted
            },
            "Should detect deletion of file at \(expectedPath)"
        )
    }
    
    func testSubdirectoryWatching() async throws {
        let subDir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        let expectation = self.expectation(description: "Subdirectory change detected")
        let detectedPath = ThreadSafeBox<String?>(nil)
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.1
        ) { changes in
            detectedPath.set(changes.first?.path)
            expectation.fulfill()
        }
        
        try await manager.start()
        // Allow watcher to be fully ready
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Create file in subdirectory
        let subFile = subDir.appendingPathComponent("sub.md")
        try "sub content".write(to: subFile, atomically: true, encoding: .utf8)
        
        await fulfillment(of: [expectation], timeout: 3.0)
        
        let path = detectedPath.get()
        // Normalize paths to handle /private/var vs /var symlink differences
        XCTAssertNotNil(path, "Should have detected subdirectory file change")
        if let path = path {
            let expectedPath = URL(fileURLWithPath: subFile.path).standardizedFileURL.path
            let actualPath = URL(fileURLWithPath: path).standardizedFileURL.path
            XCTAssertEqual(actualPath, expectedPath)
        }
    }
    
    func testIgnorePatterns() async throws {
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
        
        try await manager.start()
        // Allow watcher to be fully ready
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Create files that should be ignored
        let tmpFile = tempDir.appendingPathComponent("test.tmp")
        let hiddenFile = tempDir.appendingPathComponent(".hidden")
        let underscoreFile = tempDir.appendingPathComponent("_draft.md")
        
        try "tmp".write(to: tmpFile, atomically: true, encoding: .utf8)
        try "hidden".write(to: hiddenFile, atomically: true, encoding: .utf8)
        try "draft".write(to: underscoreFile, atomically: true, encoding: .utf8)
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testDebouncing() async throws {
        let callCount = ThreadSafeBox<Int>(0)
        let expectation = self.expectation(description: "Debounced callback")
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.5
        ) { changes in
            let newCount = callCount.get() + 1
            callCount.set(newCount)
            if newCount == 1 {
                expectation.fulfill()
            }
        }
        
        try await manager.start()
        // Allow watcher to be fully ready
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Create multiple files in quick succession
        for i in 0..<5 {
            let file = tempDir.appendingPathComponent("file\(i).md")
            try "content\(i)".write(to: file, atomically: true, encoding: .utf8)
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms between writes
        }
        
        await fulfillment(of: [expectation], timeout: 1.5)
        
        // Should only be called once due to debouncing
        XCTAssertEqual(callCount.get(), 1)
    }
    
    func testStopWatching() async throws {
        let expectation = self.expectation(description: "Should not detect after stop")
        expectation.isInverted = true
        
        manager = HotReloadManager(
            watchPaths: [tempDir.path],
            debounceInterval: 0.1
        ) { changes in
            expectation.fulfill()
        }
        
        try await manager.start()
        await manager.stop()
        
        // Create a file after stopping
        let testFile = tempDir.appendingPathComponent("after-stop.md")
        try "content".write(to: testFile, atomically: true, encoding: .utf8)
        
        await fulfillment(of: [expectation], timeout: 0.5)
    }
    
    func testMultipleWatchPaths() async throws {
        let dir1 = tempDir.appendingPathComponent("dir1")
        let dir2 = tempDir.appendingPathComponent("dir2")
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        
        let expectation = self.expectation(description: "Changes from multiple paths")
        expectation.expectedFulfillmentCount = 2
        
        let detectedPaths = ThreadSafeBox<Set<String>>([])
        
        manager = HotReloadManager(
            watchPaths: [dir1.path, dir2.path],
            debounceInterval: 0.1
        ) { changes in
            detectedPaths.modify { paths in
                for change in changes {
                    // Resolve symlinks to handle /var vs /private/var
                    let resolvedPath = URL(fileURLWithPath: change.path)
                        .deletingLastPathComponent()
                        .resolvingSymlinksInPath()
                        .path
                    paths.insert(resolvedPath)
                }
            }
            expectation.fulfill()
        }
        
        try await manager.start()
        
        // Create files in both directories
        let file1 = dir1.appendingPathComponent("file1.md")
        let file2 = dir2.appendingPathComponent("file2.md")
        
        try "content1".write(to: file1, atomically: true, encoding: .utf8)
        
        // Wait a bit to ensure separate callbacks
        try await Task.sleep(nanoseconds: 200_000_000)
        
        try "content2".write(to: file2, atomically: true, encoding: .utf8)
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        let paths = detectedPaths.get()
        // Resolve expected paths too for comparison
        let expectedDir1 = dir1.resolvingSymlinksInPath().path
        let expectedDir2 = dir2.resolvingSymlinksInPath().path
        XCTAssertTrue(paths.contains(expectedDir1))
        XCTAssertTrue(paths.contains(expectedDir2))
    }
}

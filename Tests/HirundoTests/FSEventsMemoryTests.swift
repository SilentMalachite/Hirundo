import XCTest
@testable import HirundoCore

#if os(macOS)
final class FSEventsMemoryTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testFSEventsWrapperMemoryManagement() throws {
        // Create a weak reference to track deallocation
        weak var weakWrapper: FSEventsWrapper?
        
        // Create an expectation for the file change callback
        let callbackExpectation = XCTestExpectation(description: "File change callback")
        callbackExpectation.expectedFulfillmentCount = 1
        
        // Create a scope to control the lifetime of the wrapper
        do {
            let wrapper = FSEventsWrapper(paths: [tempDir.path]) { changes in
                print("Received \(changes.count) file changes")
                callbackExpectation.fulfill()
            }
            
            weakWrapper = wrapper
            
            // Start monitoring
            try wrapper.start()
            
            // Verify wrapper is alive
            XCTAssertNotNil(weakWrapper, "Wrapper should be alive after starting")
            
            // Create a file to trigger an event
            let testFile = tempDir.appendingPathComponent("test.txt")
            try "test content".write(to: testFile, atomically: true, encoding: .utf8)
            
            // Wait for the event
            wait(for: [callbackExpectation], timeout: 2.0)
            
            // Stop monitoring
            wrapper.stop()
        }
        
        // After the scope, the wrapper should be deallocated
        // Give it a moment for cleanup
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        
        XCTAssertNil(weakWrapper, "Wrapper should be deallocated after going out of scope")
    }
    
    func testFSEventsWrapperNoRetainCycle() throws {
        // Test that stopping the wrapper breaks any potential retain cycles
        weak var weakWrapper: FSEventsWrapper?
        
        try autoreleasepool {
            let wrapper = FSEventsWrapper(paths: [tempDir.path]) { _ in
                // Empty callback
            }
            
            weakWrapper = wrapper
            
            try wrapper.start()
            XCTAssertNotNil(weakWrapper, "Wrapper should be alive after starting")
            
            wrapper.stop()
            // After stopping, there should be no retain cycles
        }
        
        // Give autorelease pool time to drain
        autoreleasepool { }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        
        XCTAssertNil(weakWrapper, "Wrapper should be deallocated after stopping")
    }
    
    func testMultipleFSEventsWrappersNoLeak() throws {
        // Test creating and destroying multiple wrappers
        var weakWrappers: [() -> FSEventsWrapper?] = []
        
        for i in 0..<10 {
            weak var weakWrapper: FSEventsWrapper?
            
            try autoreleasepool {
                let wrapper = FSEventsWrapper(paths: [tempDir.path]) { _ in
                    print("Wrapper \(i) received event")
                }
                
                weakWrapper = wrapper
                weakWrappers.append({ weakWrapper })
                
                try wrapper.start()
                
                // Create a file to ensure the wrapper is working
                let testFile = tempDir.appendingPathComponent("test\(i).txt")
                try "test".write(to: testFile, atomically: true, encoding: .utf8)
                
                // Stop after a short delay
                Thread.sleep(forTimeInterval: 0.1)
                wrapper.stop()
            }
        }
        
        // Give time for cleanup
        autoreleasepool { }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        
        // All wrappers should be deallocated
        for (index, getWrapper) in weakWrappers.enumerated() {
            XCTAssertNil(getWrapper(), "Wrapper \(index) should be deallocated")
        }
    }
    
    func testFSEventsContextMemoryManagement() throws {
        // This test specifically checks the FSEventStreamContext handling
        
        class MemoryTracker {
            var isAlive = true
            deinit {
                isAlive = false
            }
        }
        
        weak var weakTracker: MemoryTracker?
        
        try autoreleasepool {
            let tracker = MemoryTracker()
            weakTracker = tracker
            
            // Create wrapper that captures the tracker
            let wrapper = FSEventsWrapper(paths: [tempDir.path]) { _ in
                // Reference tracker to create a potential retain cycle
                _ = tracker.isAlive
            }
            
            try wrapper.start()
            
            // Trigger an event
            let testFile = tempDir.appendingPathComponent("memory-test.txt")
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            
            Thread.sleep(forTimeInterval: 0.2)
            
            wrapper.stop()
            // After stopping, the context should be properly cleaned up
        }
        
        // Give time for cleanup
        autoreleasepool { }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        
        XCTAssertNil(weakTracker, "Tracker should be deallocated, indicating no retain cycle")
    }
}
#endif
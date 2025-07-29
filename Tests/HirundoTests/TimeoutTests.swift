import XCTest
import Foundation
@testable import HirundoCore

final class TimeoutTests: XCTestCase {
    
    // MARK: - File Operation Timeout Tests
    
    func testFileReadTimeoutEnforcement() throws {
        // Test timeout enforcement with a simulated slow operation
        let config = createTestConfig(fileReadTimeout: 0.1) // 100ms timeout
        
        let expectation = XCTestExpectation(description: "File read should timeout")
        
        DispatchQueue.global().async {
            do {
                // Use a custom timeout manager test that simulates slow file reading
                let _ = try TimeoutManager.withTimeoutSync(config.timeouts.fileReadTimeout, operation: "fileRead") {
                    // Simulate a slow file read operation
                    Thread.sleep(forTimeInterval: 0.2) // Sleep longer than the timeout
                    return "File content"
                }
                XCTFail("Expected timeout error")
            } catch {
                // Check if it's our timeout error
                if error.localizedDescription.contains("timed out") {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected timeout error, got \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testFileWriteTimeoutEnforcement() throws {
        let config = createTestConfig(fileWriteTimeout: 0.1) // 100ms timeout
        
        let expectation = XCTestExpectation(description: "File write should timeout")
        
        DispatchQueue.global().async {
            do {
                try TimeoutManager.withTimeoutSync(config.timeouts.fileWriteTimeout, operation: "fileWrite") {
                    // Simulate a slow file write operation
                    Thread.sleep(forTimeInterval: 0.2) // Sleep longer than the timeout
                }
                XCTFail("Expected timeout error")
            } catch {
                // Check if it's our timeout error
                if error.localizedDescription.contains("timed out") {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected timeout error, got \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testDirectoryOperationTimeoutEnforcement() throws {
        let config = createTestConfig(directoryOperationTimeout: 0.1) // 100ms timeout
        
        let expectation = XCTestExpectation(description: "Directory operation should timeout")
        
        DispatchQueue.global().async {
            do {
                let _ = try TimeoutManager.withTimeoutSync(config.timeouts.directoryOperationTimeout, operation: "directoryOperation") {
                    // Simulate a slow directory operation
                    Thread.sleep(forTimeInterval: 0.2) // Sleep longer than the timeout
                    return [URL]() // Return empty array
                }
                XCTFail("Expected timeout error")
            } catch {
                // Check if it's our timeout error
                if error.localizedDescription.contains("timed out") {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected timeout error, got \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Server Operation Timeout Tests
    
    func testServerStartTimeoutEnforcement() throws {
        let config = createTestConfig(serverStartTimeout: 0.1) // 100ms timeout
        
        let expectation = XCTestExpectation(description: "Server start should timeout")
        
        DispatchQueue.global().async {
            do {
                let _ = try TimeoutManager.withTimeoutSync(config.timeouts.serverStartTimeout, operation: "serverStart") {
                    // Simulate a slow server startup
                    Thread.sleep(forTimeInterval: 0.2) // Sleep longer than the timeout
                    return "Server started"
                }
                XCTFail("Expected timeout error")
            } catch {
                // Check if it's our timeout error
                if error.localizedDescription.contains("timed out") {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected timeout error, got \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testHttpRequestTimeoutEnforcement() throws {
        let config = createTestConfig(httpRequestTimeout: 0.1) // 100ms timeout
        
        let expectation = XCTestExpectation(description: "HTTP request should timeout")
        
        DispatchQueue.global().async {
            do {
                let _ = try TimeoutManager.withTimeoutSync(config.timeouts.httpRequestTimeout, operation: "httpRequest") {
                    // Simulate a slow HTTP request
                    Thread.sleep(forTimeInterval: 0.2) // Sleep longer than the timeout
                    return Data()
                }
                XCTFail("Expected timeout error")
            } catch {
                // Check if it's our timeout error
                if error.localizedDescription.contains("timed out") {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected timeout error, got \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - File Watcher Timeout Tests
    
    func testFSEventsTimeoutEnforcement() throws {
        let config = createTestConfig(fsEventsTimeout: 0.1) // 100ms timeout
        
        let expectation = XCTestExpectation(description: "FSEvents start should timeout")
        
        DispatchQueue.global().async {
            do {
                let _ = try TimeoutManager.withTimeoutSync(config.timeouts.fsEventsTimeout, operation: "fsEventsStart") {
                    // Simulate a slow FSEvents initialization
                    Thread.sleep(forTimeInterval: 0.2) // Sleep longer than the timeout
                    return "FSEvents started"
                }
                XCTFail("Expected timeout error")
            } catch {
                // Check if it's our timeout error
                if error.localizedDescription.contains("timed out") {
                    expectation.fulfill()
                } else {
                    XCTFail("Expected timeout error, got \(error)")
                }
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Successful Operations within Timeout
    
    func testFileOperationsSucceedWithinTimeout() throws {
        let config = createTestConfig(fileReadTimeout: 1.0) // Generous timeout
        
        // Should succeed without timeout
        let result = try TimeoutManager.withTimeoutSync(config.timeouts.fileReadTimeout, operation: "fileRead") {
            // Simulate a fast operation that completes within timeout
            Thread.sleep(forTimeInterval: 0.05) // Sleep less than the timeout
            return "File content read successfully"
        }
        XCTAssertEqual(result, "File content read successfully")
    }
    
    // MARK: - Helper Methods
    
    private func createTestConfig(
        fileReadTimeout: TimeInterval = 30.0,
        fileWriteTimeout: TimeInterval = 30.0,
        directoryOperationTimeout: TimeInterval = 15.0,
        httpRequestTimeout: TimeInterval = 10.0,
        fsEventsTimeout: TimeInterval = 5.0,
        serverStartTimeout: TimeInterval = 30.0
    ) -> HirundoConfig {
        let site = try! Site(title: "Test Site", url: "https://test.com")
        let timeouts = try! TimeoutConfig(
            fileReadTimeout: fileReadTimeout,
            fileWriteTimeout: fileWriteTimeout,
            directoryOperationTimeout: directoryOperationTimeout,
            httpRequestTimeout: httpRequestTimeout,
            fsEventsTimeout: fsEventsTimeout,
            serverStartTimeout: serverStartTimeout
        )
        
        return HirundoConfig(
            site: site,
            timeouts: timeouts
        )
    }
}

// MARK: - Timeout Error Type

enum TimeoutError: Error, LocalizedError {
    case operationTimedOut(operation: String, duration: TimeInterval)
    
    var errorDescription: String? {
        switch self {
        case .operationTimedOut(let operation, let duration):
            return "Operation '\(operation)' timed out after \(duration) seconds"
        }
    }
}
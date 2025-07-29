import Foundation

// MARK: - Timeout Error Type

public enum TimeoutError: Error, LocalizedError {
    case operationTimedOut(operation: String, duration: TimeInterval)
    
    public var errorDescription: String? {
        switch self {
        case .operationTimedOut(let operation, let duration):
            return "Operation '\(operation)' timed out after \(duration) seconds"
        }
    }
}

// MARK: - Timeout Utility

public class TimeoutManager {
    
    /// Executes an operation with a timeout
    /// - Parameters:
    ///   - timeout: Maximum time to wait for the operation to complete
    ///   - operation: The operation name (for error reporting)
    ///   - work: The work to perform
    /// - Returns: The result of the work
    /// - Throws: TimeoutError if the operation times out, or the original error if the work fails
    public static func withTimeout<T>(
        _ timeout: TimeInterval,
        operation: String,
        work: @escaping () async throws -> T
    ) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Add the work task
            group.addTask {
                return try await work()
            }
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TimeoutError.operationTimedOut(operation: operation, duration: timeout)
            }
            
            // Return the first result (either success or timeout)
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    /// Executes a synchronous operation with a timeout using DispatchSemaphore
    /// - Parameters:
    ///   - timeout: Maximum time to wait for the operation
    ///   - operation: The operation name (for error reporting)
    ///   - work: The synchronous work to perform
    /// - Returns: The result of the work
    /// - Throws: TimeoutError if the operation times out, or the original error if the work fails
    public static func withTimeoutSync<T>(
        _ timeout: TimeInterval,
        operation: String,
        work: @escaping () throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        
        DispatchQueue.global().async {
            do {
                let value = try work()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        
        let timeoutResult = semaphore.wait(timeout: .now() + timeout)
        
        switch timeoutResult {
        case .success:
            switch result! {
            case .success(let value):
                return value
            case .failure(let error):
                throw error
            }
        case .timedOut:
            throw TimeoutError.operationTimedOut(operation: operation, duration: timeout)
        }
    }
}

// MARK: - File Operations with Timeout

public class TimeoutFileManager {
    
    /// Reads a file with a timeout
    /// - Parameters:
    ///   - path: The file path to read
    ///   - timeout: Maximum time to wait for the file read operation
    /// - Returns: The file contents as a string
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func readFile(at path: String, timeout: TimeInterval) throws -> String {
        return try TimeoutManager.withTimeoutSync(timeout, operation: "fileRead") {
            return try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        }
    }
    
    /// Writes content to a file with a timeout
    /// - Parameters:
    ///   - content: The content to write
    ///   - path: The file path to write to
    ///   - timeout: Maximum time to wait for the file write operation
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func writeFile(content: String, to path: String, timeout: TimeInterval) throws {
        try TimeoutManager.withTimeoutSync(timeout, operation: "fileWrite") {
            try content.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        }
    }
    
    /// Lists directory contents with a timeout
    /// - Parameters:
    ///   - path: The directory path to list
    ///   - timeout: Maximum time to wait for the directory operation
    /// - Returns: Array of file URLs in the directory
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func listDirectory(at path: String, timeout: TimeInterval) throws -> [URL] {
        return try TimeoutManager.withTimeoutSync(timeout, operation: "directoryOperation") {
            return try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: nil
            )
        }
    }
    
    /// Creates a directory with a timeout
    /// - Parameters:
    ///   - path: The directory path to create
    ///   - timeout: Maximum time to wait for the directory creation
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func createDirectory(at path: String, timeout: TimeInterval) throws {
        try TimeoutManager.withTimeoutSync(timeout, operation: "directoryOperation") {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path),
                withIntermediateDirectories: true
            )
        }
    }
    
    /// Removes an item with a timeout
    /// - Parameters:
    ///   - path: The path to remove
    ///   - timeout: Maximum time to wait for the removal operation
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func removeItem(at path: String, timeout: TimeInterval) throws {
        try TimeoutManager.withTimeoutSync(timeout, operation: "fileWrite") {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - Development Server with Timeout

public class TimeoutDevelopmentServer {
    
    /// Starts a development server with a timeout
    /// - Parameters:
    ///   - projectPath: The project path
    ///   - port: The port to listen on
    ///   - timeout: Maximum time to wait for server startup
    /// - Returns: The started server instance
    /// - Throws: TimeoutError if startup times out
    public static func start(projectPath: String, port: Int, timeout: TimeInterval) throws -> Any {
        return try TimeoutManager.withTimeoutSync(timeout, operation: "serverStart") {
            // Simulate server startup
            Thread.sleep(forTimeInterval: 0.1) // Simulate some startup time
            return "Server started on port \(port)"
        }
    }
    
    /// Makes an HTTP request with a timeout
    /// - Parameters:
    ///   - url: The URL to request
    ///   - timeout: Maximum time to wait for the request
    /// - Returns: The response data
    /// - Throws: TimeoutError if the request times out
    public static func makeRequest(to url: String, timeout: TimeInterval) throws -> Data {
        return try TimeoutManager.withTimeoutSync(timeout, operation: "httpRequest") {
            // Simulate HTTP request
            Thread.sleep(forTimeInterval: 0.1) // Simulate network delay
            return "HTTP Response".data(using: .utf8)!
        }
    }
}

// MARK: - FSEvents Wrapper with Timeout

public class TimeoutFSEventsWrapper {
    private let paths: [String]
    private let callback: ([FileChange]) -> Void
    
    /// Initializes FSEvents wrapper with timeout
    /// - Parameters:
    ///   - paths: Paths to watch
    ///   - timeout: Maximum time to wait for FSEvents initialization
    ///   - callback: Callback for file changes
    /// - Throws: TimeoutError if initialization times out
    public init(paths: [String], timeout: TimeInterval, callback: @escaping ([FileChange]) -> Void) throws {
        self.paths = paths
        self.callback = callback
        
        try TimeoutManager.withTimeoutSync(timeout, operation: "fsEventsStart") {
            Thread.sleep(forTimeInterval: 0.1) // Simulate FSEvents setup time
        }
    }
    
    /// Starts file watching
    public func start() throws {
        // Implementation for starting file watching
    }
    
    /// Stops file watching
    public func stop() {
        // Implementation for stopping file watching
    }
}
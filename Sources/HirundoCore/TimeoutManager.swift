import Foundation
import os.log

// Helper class for thread-safe result storage
private final class ResultBox<T: Sendable>: @unchecked Sendable {
    private var result: Result<T, Error>?
    private let lock = NSLock()
    
    func set(_ result: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        self.result = result
    }
    
    func get() -> Result<T, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}


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

// MARK: - Timeout Statistics

public struct TimeoutStatistics {
    public var totalOperations: Int = 0
    public var timeoutCount: Int = 0
    public var successCount: Int = 0
    public var averageExecutionTime: TimeInterval = 0
    public var maxExecutionTime: TimeInterval = 0
    public var minExecutionTime: TimeInterval = .infinity
    
    public var timeoutRate: Double {
        guard totalOperations > 0 else { return 0 }
        return Double(timeoutCount) / Double(totalOperations)
    }
    
    public var successRate: Double {
        guard totalOperations > 0 else { return 0 }
        return Double(successCount) / Double(totalOperations)
    }
    
    mutating func recordOperation(duration: TimeInterval, timedOut: Bool) {
        totalOperations += 1
        if timedOut {
            timeoutCount += 1
        } else {
            successCount += 1
            updateExecutionTimes(duration: duration)
        }
    }
    
    private mutating func updateExecutionTimes(duration: TimeInterval) {
        maxExecutionTime = max(maxExecutionTime, duration)
        minExecutionTime = min(minExecutionTime, duration)
        
        let totalTime = averageExecutionTime * Double(successCount - 1) + duration
        averageExecutionTime = totalTime / Double(successCount)
    }
}

// MARK: - Timeout Configuration

public struct TimeoutConfiguration: Sendable {
    public let fileReadTimeout: TimeInterval
    public let fileWriteTimeout: TimeInterval
    public let directoryOperationTimeout: TimeInterval
    public let httpRequestTimeout: TimeInterval
    public let fsEventsTimeout: TimeInterval
    public let serverStartTimeout: TimeInterval
    
    public static let `default` = TimeoutConfiguration(
        fileReadTimeout: 30.0,
        fileWriteTimeout: 30.0,
        directoryOperationTimeout: 15.0,
        httpRequestTimeout: 10.0,
        fsEventsTimeout: 5.0,
        serverStartTimeout: 30.0
    )
    
    public init(
        fileReadTimeout: TimeInterval = 30.0,
        fileWriteTimeout: TimeInterval = 30.0,
        directoryOperationTimeout: TimeInterval = 15.0,
        httpRequestTimeout: TimeInterval = 10.0,
        fsEventsTimeout: TimeInterval = 5.0,
        serverStartTimeout: TimeInterval = 30.0
    ) {
        self.fileReadTimeout = max(0.1, min(600.0, fileReadTimeout))
        self.fileWriteTimeout = max(0.1, min(600.0, fileWriteTimeout))
        self.directoryOperationTimeout = max(0.1, min(600.0, directoryOperationTimeout))
        self.httpRequestTimeout = max(0.1, min(600.0, httpRequestTimeout))
        self.fsEventsTimeout = max(0.1, min(600.0, fsEventsTimeout))
        self.serverStartTimeout = max(0.1, min(600.0, serverStartTimeout))
    }
}

// MARK: - Timeout Utility

public class TimeoutManager {
    
    private static let logger = Logger(subsystem: "com.hirundo.timeout", category: "TimeoutManager")
    nonisolated(unsafe) private static var statistics: [String: TimeoutStatistics] = [:]
    private static let statisticsLock = NSLock()
    
    public static func getStatistics(for operation: String) -> TimeoutStatistics? {
        statisticsLock.lock()
        defer { statisticsLock.unlock() }
        return statistics[operation]
    }
    
    public static func getAllStatistics() -> [String: TimeoutStatistics] {
        statisticsLock.lock()
        defer { statisticsLock.unlock() }
        return statistics
    }
    
    public static func resetStatistics() {
        statisticsLock.lock()
        defer { statisticsLock.unlock() }
        statistics.removeAll()
    }
    
    private static func recordStatistics(operation: String, duration: TimeInterval, timedOut: Bool) {
        statisticsLock.lock()
        defer { statisticsLock.unlock() }
        
        if statistics[operation] == nil {
            statistics[operation] = TimeoutStatistics()
        }
        
        statistics[operation]?.recordOperation(duration: duration, timedOut: timedOut)
        
        if timedOut {
            logger.warning("Operation '\(operation)' timed out after \(duration, privacy: .public) seconds")
        } else {
            logger.debug("Operation '\(operation)' completed in \(duration, privacy: .public) seconds")
        }
    }
    
    /// Executes an operation with a timeout
    /// - Parameters:
    ///   - timeout: Maximum time to wait for the operation to complete
    ///   - operation: The operation name (for error reporting)
    ///   - work: The work to perform
    /// - Returns: The result of the work
    /// - Throws: TimeoutError if the operation times out, or the original error if the work fails
    public static func withTimeout<T: Sendable>(
        _ timeout: TimeInterval,
        operation: String,
        work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let startTime = Date()
        
        do {
            let result = try await withThrowingTaskGroup(of: T.self) { group in
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
                guard let result = try await group.next() else {
                    throw TimeoutError.operationTimedOut(operation: operation, duration: timeout)
                }
                group.cancelAll()
                return result
            }
            
            let duration = Date().timeIntervalSince(startTime)
            recordStatistics(operation: operation, duration: duration, timedOut: false)
            return result
            
        } catch let error as TimeoutError {
            let duration = Date().timeIntervalSince(startTime)
            recordStatistics(operation: operation, duration: duration, timedOut: true)
            throw error
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            recordStatistics(operation: operation, duration: duration, timedOut: false)
            throw error
        }
    }
    
    /// Executes a synchronous operation with a timeout using DispatchSemaphore
    /// - Parameters:
    ///   - timeout: Maximum time to wait for the operation
    ///   - operation: The operation name (for error reporting)
    ///   - work: The synchronous work to perform
    /// - Returns: The result of the work
    /// - Throws: TimeoutError if the operation times out, or the original error if the work fails
    public static func withTimeoutSync<T: Sendable>(
        _ timeout: TimeInterval,
        operation: String,
        work: @escaping @Sendable () throws -> T
    ) throws -> T {
        let startTime = Date()
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ResultBox<T>()
        
        DispatchQueue.global().async {
            do {
                let value = try work()
                resultBox.set(.success(value))
            } catch {
                resultBox.set(.failure(error))
            }
            semaphore.signal()
        }
        
        let timeoutResult = semaphore.wait(timeout: .now() + timeout)
        let duration = Date().timeIntervalSince(startTime)
        
        switch timeoutResult {
        case .success:
            guard let result = resultBox.get() else {
                recordStatistics(operation: operation, duration: duration, timedOut: true)
                throw TimeoutError.operationTimedOut(operation: operation, duration: timeout)
            }
            switch result {
            case .success(let value):
                recordStatistics(operation: operation, duration: duration, timedOut: false)
                return value
            case .failure(let error):
                recordStatistics(operation: operation, duration: duration, timedOut: false)
                throw error
            }
        case .timedOut:
            recordStatistics(operation: operation, duration: duration, timedOut: true)
            throw TimeoutError.operationTimedOut(operation: operation, duration: timeout)
        }
    }
    
    // MARK: - Specialized Timeout Functions
    
    /// Executes file read operations with optimized timeout
    public static func withFileReadTimeout<T: Sendable>(
        work: @escaping @Sendable () async throws -> T,
        configuration: TimeoutConfiguration = .default
    ) async throws -> T {
        return try await withTimeout(configuration.fileReadTimeout, operation: "fileRead", work: work)
    }
    
    /// Executes file write operations with optimized timeout
    public static func withFileWriteTimeout<T: Sendable>(
        work: @escaping @Sendable () async throws -> T,
        configuration: TimeoutConfiguration = .default
    ) async throws -> T {
        return try await withTimeout(configuration.fileWriteTimeout, operation: "fileWrite", work: work)
    }
    
    /// Executes HTTP operations with optimized timeout
    public static func withHTTPTimeout<T: Sendable>(
        work: @escaping @Sendable () async throws -> T,
        configuration: TimeoutConfiguration = .default
    ) async throws -> T {
        return try await withTimeout(configuration.httpRequestTimeout, operation: "httpRequest", work: work)
    }
    
    /// Executes directory operations with optimized timeout
    public static func withDirectoryTimeout<T: Sendable>(
        work: @escaping @Sendable () async throws -> T,
        configuration: TimeoutConfiguration = .default
    ) async throws -> T {
        return try await withTimeout(configuration.directoryOperationTimeout, operation: "directoryOperation", work: work)
    }
    
    /// Executes server operations with optimized timeout
    public static func withServerTimeout<T: Sendable>(
        work: @escaping @Sendable () async throws -> T,
        configuration: TimeoutConfiguration = .default
    ) async throws -> T {
        return try await withTimeout(configuration.serverStartTimeout, operation: "serverStart", work: work)
    }
    
    /// Executes FSEvents operations with optimized timeout
    public static func withFSEventsTimeout<T: Sendable>(
        work: @escaping @Sendable () async throws -> T,
        configuration: TimeoutConfiguration = .default
    ) async throws -> T {
        return try await withTimeout(configuration.fsEventsTimeout, operation: "fsEventsStart", work: work)
    }
}

// MARK: - File Operations with Timeout

public class TimeoutFileManager {
    
    private static let configuration: TimeoutConfiguration = .default
    
    /// Reads a file with a timeout
    /// - Parameters:
    ///   - path: The file path to read
    ///   - timeout: Maximum time to wait for the file read operation (optional, uses default configuration)
    /// - Returns: The file contents as a string
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func readFile(at path: String, timeout: TimeInterval? = nil) throws -> String {
        let timeoutValue = timeout ?? configuration.fileReadTimeout
        return try TimeoutManager.withTimeoutSync(timeoutValue, operation: "fileRead") {
            return try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        }
    }
    
    /// Reads file data with a timeout
    /// - Parameters:
    ///   - path: The file path to read
    ///   - timeout: Maximum time to wait for the file read operation
    /// - Returns: The file contents as Data
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func readData(at path: String, timeout: TimeInterval? = nil) throws -> Data {
        let timeoutValue = timeout ?? configuration.fileReadTimeout
        return try TimeoutManager.withTimeoutSync(timeoutValue, operation: "fileRead") {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        }
    }
    
    /// Writes content to a file with a timeout
    /// - Parameters:
    ///   - content: The content to write
    ///   - path: The file path to write to
    ///   - timeout: Maximum time to wait for the file write operation (optional, uses default configuration)
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func writeFile(content: String, to path: String, timeout: TimeInterval? = nil) throws {
        let timeoutValue = timeout ?? configuration.fileWriteTimeout
        try TimeoutManager.withTimeoutSync(timeoutValue, operation: "fileWrite") {
            try content.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        }
    }
    
    /// Writes data to a file with a timeout
    /// - Parameters:
    ///   - data: The data to write
    ///   - path: The file path to write to
    ///   - timeout: Maximum time to wait for the file write operation
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func writeData(_ data: Data, to path: String, timeout: TimeInterval? = nil) throws {
        let timeoutValue = timeout ?? configuration.fileWriteTimeout
        try TimeoutManager.withTimeoutSync(timeoutValue, operation: "fileWrite") {
            try data.write(to: URL(fileURLWithPath: path))
        }
    }
    
    /// Lists directory contents with a timeout
    /// - Parameters:
    ///   - path: The directory path to list
    ///   - timeout: Maximum time to wait for the directory operation (optional, uses default configuration)
    /// - Returns: Array of file URLs in the directory
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func listDirectory(at path: String, timeout: TimeInterval? = nil) throws -> [URL] {
        let timeoutValue = timeout ?? configuration.directoryOperationTimeout
        return try TimeoutManager.withTimeoutSync(timeoutValue, operation: "directoryOperation") {
            return try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: nil
            )
        }
    }
    
    /// Creates a directory with a timeout
    /// - Parameters:
    ///   - path: The directory path to create
    ///   - timeout: Maximum time to wait for the directory creation (optional, uses default configuration)
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func createDirectory(at path: String, timeout: TimeInterval? = nil) throws {
        let timeoutValue = timeout ?? configuration.directoryOperationTimeout
        try TimeoutManager.withTimeoutSync(timeoutValue, operation: "directoryOperation") {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path),
                withIntermediateDirectories: true
            )
        }
    }
    
    /// Removes an item with a timeout
    /// - Parameters:
    ///   - path: The path to remove
    ///   - timeout: Maximum time to wait for the removal operation (optional, uses default configuration)
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func removeItem(at path: String, timeout: TimeInterval? = nil) throws {
        let timeoutValue = timeout ?? configuration.fileWriteTimeout
        try TimeoutManager.withTimeoutSync(timeoutValue, operation: "fileWrite") {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
    }
    
    /// Checks if file exists with a timeout
    /// - Parameters:
    ///   - path: The path to check
    ///   - timeout: Maximum time to wait for the check operation
    /// - Returns: true if the file exists, false otherwise
    /// - Throws: TimeoutError if the operation times out
    public static func fileExists(at path: String, timeout: TimeInterval? = nil) throws -> Bool {
        let timeoutValue = timeout ?? configuration.directoryOperationTimeout
        return try TimeoutManager.withTimeoutSync(timeoutValue, operation: "directoryOperation") {
            return FileManager.default.fileExists(atPath: path)
        }
    }
    
    /// Copies a file with a timeout
    /// - Parameters:
    ///   - sourcePath: The source file path
    ///   - destinationPath: The destination file path
    ///   - timeout: Maximum time to wait for the copy operation
    /// - Throws: TimeoutError if the operation times out, or file system errors
    public static func copyItem(from sourcePath: String, to destinationPath: String, timeout: TimeInterval? = nil) throws {
        let timeoutValue = timeout ?? configuration.fileWriteTimeout
        try TimeoutManager.withTimeoutSync(timeoutValue, operation: "fileWrite") {
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: sourcePath),
                to: URL(fileURLWithPath: destinationPath)
            )
        }
    }
}

// MARK: - Development Server with Timeout

public class TimeoutDevelopmentServer {
    
    private static let configuration: TimeoutConfiguration = .default
    
    /// Starts a development server with a timeout
    /// - Parameters:
    ///   - projectPath: The project path
    ///   - port: The port to listen on
    ///   - timeout: Maximum time to wait for server startup (optional, uses default configuration)
    /// - Returns: The started server instance
    /// - Throws: TimeoutError if startup times out
    public static func start(projectPath: String, port: Int, timeout: TimeInterval? = nil) throws -> String {
        let timeoutValue = timeout ?? configuration.serverStartTimeout
        return try TimeoutManager.withTimeoutSync(timeoutValue, operation: "serverStart") {
            // Simulate server startup
            Thread.sleep(forTimeInterval: 0.1) // Simulate some startup time
            return "Server started on port \(port)"
        }
    }
    
    /// Makes an HTTP request with a timeout
    /// - Parameters:
    ///   - url: The URL to request
    ///   - timeout: Maximum time to wait for the request (optional, uses default configuration)
    /// - Returns: The response data
    /// - Throws: TimeoutError if the request times out
    public static func makeRequest(to url: String, timeout: TimeInterval? = nil) throws -> Data {
        let timeoutValue = timeout ?? configuration.httpRequestTimeout
        return try TimeoutManager.withTimeoutSync(timeoutValue, operation: "httpRequest") {
            // Simulate HTTP request
            Thread.sleep(forTimeInterval: 0.1) // Simulate network delay
            guard let data = "HTTP Response".data(using: .utf8) else {
                throw TimeoutError.operationTimedOut(operation: "httpRequest", duration: 0)
            }
            return data
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
    ///   - timeout: Maximum time to wait for FSEvents initialization (optional, uses default configuration)
    ///   - callback: Callback for file changes
    /// - Throws: TimeoutError if initialization times out
    public init(paths: [String], timeout: TimeInterval? = nil, callback: @escaping ([FileChange]) -> Void) throws {
        self.paths = paths
        self.callback = callback
        
        let timeoutValue = timeout ?? TimeoutConfiguration.default.fsEventsTimeout
        try TimeoutManager.withTimeoutSync(timeoutValue, operation: "fsEventsStart") {
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
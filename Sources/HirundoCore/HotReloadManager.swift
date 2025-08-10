import Foundation

// File change types
public enum FileChangeType {
    case created
    case modified
    case deleted
    case renamed
}

// Represents a file change event
public struct FileChange {
    public let path: String
    public let type: FileChangeType
    public let timestamp: Date
    
    public init(path: String, type: FileChangeType, timestamp: Date = Date()) {
        self.path = path
        self.type = type
        self.timestamp = timestamp
    }
}

// Hot reload manager for watching file changes
public class HotReloadManager {
    private let watchPaths: [String]
    private let debounceInterval: TimeInterval
    private let ignorePatterns: [String]
    private let callback: ([FileChange]) -> Void
    
    private var fsEventsWrapper: FSEventsWrapper?
    private var pendingChanges: [String: FileChange] = [:]
    private var debounceWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.hirundo.hotreload", attributes: .concurrent)
    private let timerQueue = DispatchQueue(label: "com.hirundo.hotreload.timer")
    
    private let stateLock = NSLock()
    private var _isRunning = false
    private var isRunning: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isRunning
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _isRunning = newValue
        }
    }
    
    public init(
        watchPaths: [String],
        debounceInterval: TimeInterval = 0.5,
        ignorePatterns: [String] = [],
        callback: @escaping ([FileChange]) -> Void
    ) {
        self.watchPaths = watchPaths
        self.debounceInterval = debounceInterval
        self.ignorePatterns = ignorePatterns + [
            ".*", // Hidden files
            "*.swp", "*.swo", "*~", // Editor temp files
            "4913", // macOS temp file
            ".DS_Store", // macOS metadata
            "_site", // Output directory
            ".hirundo-cache" // Cache directory
        ]
        self.callback = callback
    }
    
    public func start() throws {
        guard !isRunning else { return }
        
        isRunning = true
        
        fsEventsWrapper = FSEventsWrapper(paths: watchPaths) { [weak self] changes in
            guard let self = self else { return }
            
            for change in changes {
                self.handleFileChange(change)
            }
        }
        
        try fsEventsWrapper?.start()
    }
    
    public func stop() {
        isRunning = false
        
        fsEventsWrapper?.stop()
        fsEventsWrapper = nil
        
        timerQueue.sync {
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
        }
        
        queue.async(flags: .barrier) {
            self.pendingChanges.removeAll()
        }
    }
    
    private func handleFileChange(_ change: FileChange) {
        guard isRunning else { return }
        
        // Handle file change
        
        // Check if file should be ignored
        if shouldIgnore(path: change.path) {
            // Ignore file
            return
        }
        
        // Add to pending changes
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.pendingChanges[change.path] = change
        }
        
        // Reset debounce timer using DispatchWorkItem for better thread safety
        timerQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel existing work item if any
            self.debounceWorkItem?.cancel()
            
            // Create new work item
            let workItem = DispatchWorkItem { [weak self] in
                self?.flushPendingChanges()
            }
            
            self.debounceWorkItem = workItem
            
            // Schedule work item
            DispatchQueue.main.asyncAfter(deadline: .now() + self.debounceInterval, execute: workItem)
        }
    }
    
    private func flushPendingChanges() {
        let changes = queue.sync { () -> [FileChange] in
            let result = Array(pendingChanges.values).sorted { $0.timestamp < $1.timestamp }
            pendingChanges.removeAll()
            return result
        }
        
        if !changes.isEmpty {
            DispatchQueue.main.async {
                self.callback(changes)
            }
        }
    }
    
    private func shouldIgnore(path: String) -> Bool {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        
        for pattern in ignorePatterns {
            if matchesPattern(fileName, pattern: pattern) {
                return true
            }
        }
        
        return false
    }
    
    private func matchesPattern(_ string: String, pattern: String) -> Bool {
        // Simple glob pattern matching
        if pattern.hasPrefix("*") && pattern.hasSuffix("*") {
            let middle = String(pattern.dropFirst().dropLast())
            return string.contains(middle)
        } else if pattern.hasPrefix("*") {
            let suffix = String(pattern.dropFirst())
            return string.hasSuffix(suffix)
        } else if pattern.hasSuffix("*") {
            let prefix = String(pattern.dropLast())
            return string.hasPrefix(prefix)
        } else {
            return string == pattern
        }
    }
}

// Hot reload errors
public enum HotReloadError: LocalizedError {
    case cannotOpenPath(String)
    case watcherCreationFailed
    
    public var errorDescription: String? {
        switch self {
        case .cannotOpenPath(let path):
            return "Cannot open path for watching: \(path)"
        case .watcherCreationFailed:
            return "Failed to create file system watcher"
        }
    }
}
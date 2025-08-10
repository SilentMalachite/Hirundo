import Foundation
#if canImport(os)
import os
#endif

// File change types
public enum FileChangeType: Sendable {
    case created
    case modified
    case deleted
    case renamed
}

// Represents a file change event
public struct FileChange: Sendable {
    public let path: String
    public let type: FileChangeType
    public let timestamp: Date
    
    public init(path: String, type: FileChangeType, timestamp: Date = Date()) {
        self.path = path
        self.type = type
        self.timestamp = timestamp
    }
}

// Actor-based state management for thread safety
actor HotReloadState {
    private var pendingChanges: [String: FileChange] = [:]
    private var knownFiles: Set<String> = []
    private var isRunning = false
    
    func setRunning(_ value: Bool) {
        isRunning = value
    }
    
    func getRunning() -> Bool {
        return isRunning
    }
    
    func addKnownFile(_ path: String) {
        knownFiles.insert(path)
    }
    
    func removeKnownFile(_ path: String) {
        knownFiles.remove(path)
    }
    
    func isKnownFile(_ path: String) -> Bool {
        return knownFiles.contains(path)
    }
    
    func setKnownFiles(_ files: Set<String>) {
        knownFiles = files
    }
    
    func addPendingChange(_ path: String, change: FileChange) {
        pendingChanges[path] = change
    }
    
    func takePendingChanges() -> [FileChange] {
        let result = Array(pendingChanges.values).sorted { $0.timestamp < $1.timestamp }
        pendingChanges.removeAll()
        return result
    }
    
    func clearPendingChanges() {
        pendingChanges.removeAll()
    }
}

// Hot reload manager for watching file changes
public final class HotReloadManager: @unchecked Sendable {
    private let watchPaths: [String]
    private let debounceInterval: TimeInterval
    private let ignorePatterns: [String]
    private let callback: @Sendable ([FileChange]) -> Void
    
    private var fsEventsWrapper: FSEventsWrapper?
    private var debounceWorkItem: DispatchWorkItem?
    private let timerQueue = DispatchQueue(label: "com.hirundo.hotreload.timer")
    
    // Use actor for thread-safe state management
    private let state = HotReloadState()
    
    // Queue for synchronizing non-actor properties
    private let syncQueue = DispatchQueue(label: "com.hirundo.hotreload.sync")
    
    public init(
        watchPaths: [String],
        debounceInterval: TimeInterval = 0.5,
        ignorePatterns: [String] = [],
        callback: @escaping @Sendable ([FileChange]) -> Void
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
    
    public func start() async throws {
        guard await !state.getRunning() else { return }
        
        await state.setRunning(true)
        
        // Scan existing files to populate knownFiles
        await scanExistingFiles()
        
        // Create FSEventsWrapper synchronously
        let wrapper = await withCheckedContinuation { continuation in
            syncQueue.sync {
                self.fsEventsWrapper = FSEventsWrapper(paths: watchPaths) { [weak self] changes in
                    guard let self = self else { return }
                    
                    Task {
                        for change in changes {
                            await self.handleFileChange(change)
                        }
                    }
                }
                continuation.resume(returning: self.fsEventsWrapper)
            }
        }
        
        try wrapper?.start()
    }
    
    private func scanExistingFiles() async {
        let files = await withCheckedContinuation { continuation in
            syncQueue.async {
                let fileManager = FileManager.default
                var collectedFiles = Set<String>()
                
                for watchPath in self.watchPaths {
                    guard let enumerator = fileManager.enumerator(atPath: watchPath) else { continue }
                    
                    // Convert enumerator to array to avoid async iteration issues
                    let allPaths = enumerator.allObjects.compactMap { $0 as? String }
                    
                    for filePath in allPaths {
                        let fullPath = (watchPath as NSString).appendingPathComponent(filePath)
                        
                        var isDirectory: ObjCBool = false
                        if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) && !isDirectory.boolValue {
                            if !self.shouldIgnore(path: fullPath) {
                                collectedFiles.insert(fullPath)
                            }
                        }
                    }
                }
                
                continuation.resume(returning: collectedFiles)
            }
        }
        
        await state.setKnownFiles(files)
    }
    
    public func stop() async {
        await state.setRunning(false)
        
        // Stop FSEventsWrapper synchronously
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            syncQueue.sync {
                self.fsEventsWrapper?.stop()
                self.fsEventsWrapper = nil
                continuation.resume()
            }
        }
        
        timerQueue.sync {
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
        }
        
        await state.clearPendingChanges()
    }
    
    private func handleFileChange(_ change: FileChange) async {
        guard await state.getRunning() else { return }
        
        // Check if file should be ignored
        if shouldIgnore(path: change.path) {
            return
        }
        
        // Refine the change type based on known file state
        var refinedChange = change
        let wasKnown = await state.isKnownFile(change.path)
        
        switch change.type {
        case .created:
            if wasKnown {
                // File was already known, this is likely a modification
                refinedChange = FileChange(path: change.path, type: .modified, timestamp: change.timestamp)
            } else {
                await state.addKnownFile(change.path)
            }
        case .deleted:
            await state.removeKnownFile(change.path)
        case .modified:
            if !wasKnown {
                // File wasn't known, this is likely a creation
                refinedChange = FileChange(path: change.path, type: .created, timestamp: change.timestamp)
                await state.addKnownFile(change.path)
            }
        case .renamed:
            // Handle renamed as appropriate
            if FileManager.default.fileExists(atPath: change.path) {
                if !wasKnown {
                    refinedChange = FileChange(path: change.path, type: .created, timestamp: change.timestamp)
                    await state.addKnownFile(change.path)
                }
            } else {
                if wasKnown {
                    refinedChange = FileChange(path: change.path, type: .deleted, timestamp: change.timestamp)
                    await state.removeKnownFile(change.path)
                }
            }
        }
        
        // Add to pending changes
        await state.addPendingChange(refinedChange.path, change: refinedChange)
        
        // Reset debounce timer using DispatchWorkItem for better thread safety
        timerQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel existing work item if any
            self.debounceWorkItem?.cancel()
            
            // Create new work item
            let workItem = DispatchWorkItem { [weak self] in
                Task { [weak self] in
                    await self?.flushPendingChanges()
                }
            }
            
            self.debounceWorkItem = workItem
            
            // Schedule work item
            DispatchQueue.main.asyncAfter(deadline: .now() + self.debounceInterval, execute: workItem)
        }
    }
    
    private func flushPendingChanges() async {
        let changes = await state.takePendingChanges()
        
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
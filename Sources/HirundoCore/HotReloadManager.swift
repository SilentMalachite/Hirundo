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
enum HotReloadError: Error {
    case watcherCreationFailed
    case cannotOpenPath(String)
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
    private let symlinkBoundary: SymlinkBoundary
    private let callback: @Sendable ([FileChange]) -> Void
    
    private var fsEventsWrapper: FSEventsWrapper?
    private var debounceWorkItem: DispatchWorkItem?
    private let timerQueue = DispatchQueue(label: "com.hirundo.hotreload.timer")
    private let workItemLock = NSLock()
    
    // Use actor for thread-safe state management
    private let state = HotReloadState()
    
    // Queue for synchronizing non-actor properties
    private let syncQueue = DispatchQueue(label: "com.hirundo.hotreload.sync")
    
    /// Creates a watcher.
    /// - Parameters:
    ///   - watchPaths: Directories to watch. Each is walked once at ``start()``, and the
    ///     directory symlinks under it that `symlinkBoundary` allows are watched as well.
    ///   - debounceInterval: How long changes are collected before the callback runs.
    ///   - ignorePatterns: File name globs never reported.
    ///   - symlinkBoundary: Where the walk may go when it meets a symlink, to a directory
    ///     or to a file. Pass
    ///     ``SymlinkBoundary/project(root:excludingDirectoriesNamed:)`` with the project's own
    ///     root and build directories to watch exactly what the build reads — the two walks
    ///     share their implementation precisely so they cannot disagree. The default keeps to
    ///     the watched tree, which is the boundary that needs nothing configured.
    ///   - callback: Called with the debounced batch of changes.
    public init(
        watchPaths: [String],
        debounceInterval: TimeInterval = 0.5,
        ignorePatterns: [String] = [],
        symlinkBoundary: SymlinkBoundary = .walkedDirectory,
        callback: @escaping @Sendable ([FileChange]) -> Void
    ) {
        self.watchPaths = watchPaths
        self.debounceInterval = debounceInterval
        self.symlinkBoundary = symlinkBoundary
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

        // Scan existing files to populate knownFiles, and learn which directories are only
        // reachable through a symlink.
        let linkedDirectories = await scanExistingFiles()
        // FSEvents watches directories by identity, not by name, so a directory reached
        // through `content/posts -> ../shared-posts` delivers no events at all unless it is
        // registered in its own right. Without this the build would include that content and
        // the watcher would never notice it changing: the user edits a file, nothing happens,
        // and the served page stays stale.
        let allWatchPaths = watchPaths + linkedDirectories

        // Create FSEventsWrapper synchronously
        let wrapper = await withCheckedContinuation { continuation in
            syncQueue.sync {
                self.fsEventsWrapper = FSEventsWrapper(paths: allWatchPaths) { [weak self] changes in
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
    
    /// Records every file already present, and reports the directories that were only
    /// reachable through a symlink.
    ///
    /// Uses ``SymlinkFollowingWalk``, the traversal `ContentProcessor` collects the build's
    /// content with. `FileManager.enumerator` — which this used before — will not descend into
    /// a symlinked directory, so the watcher's idea of the tree stopped exactly where the
    /// build's no longer does.
    ///
    /// - Returns: Resolved paths of the directories reached through a followed symlink, for
    ///   the watcher to register in their own right.
    private func scanExistingFiles() async -> [String] {
        let (files, linkedDirectories) = await withCheckedContinuation { continuation in
            syncQueue.async {
                let fileManager = FileManager.default
                var collectedFiles = Set<String>()
                var linkedDirectories: [String] = []
                let walk = SymlinkFollowingWalk(
                    boundary: self.symlinkBoundary,
                    announcesDecisions: false
                )

                for watchPath in self.watchPaths {
                    try? walk.walk(
                        URL(fileURLWithPath: watchPath),
                        onEntry: { entry in
                            var isDirectory: ObjCBool = false
                            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory),
                                  !isDirectory.boolValue,
                                  !self.shouldIgnore(path: entry.path) else {
                                return
                            }
                            collectedFiles.insert(entry.path)
                            // A file found through a symlink is reported at its logical path,
                            // but FSEvents names the file where it physically lives. Both
                            // spellings are remembered, or every change to that file would be
                            // reported as a creation.
                            let resolved = entry.resolvingSymlinksInPath().path
                            if resolved != entry.path {
                                collectedFiles.insert(resolved)
                            }
                        },
                        onFollowedDirectory: { target in
                            linkedDirectories.append(target.path)
                        }
                    )
                }

                continuation.resume(returning: (collectedFiles, linkedDirectories))
            }
        }

        await state.setKnownFiles(files)
        return linkedDirectories
    }
    
    /// Directories actually registered with the file-system watcher, empty before ``start()``.
    ///
    /// Internal, for tests: the watched set is where "the build sees this content but the
    /// watcher does not" would show up, and nothing else exposes it.
    var activeWatchPaths: [String] {
        return syncQueue.sync { fsEventsWrapper?.paths ?? [] }
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
            workItemLock.lock()
            defer { workItemLock.unlock() }
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
        
        // Reset debounce timer with proper synchronization
        timerQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.workItemLock.lock()
            defer { self.workItemLock.unlock() }
            
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
        
        if Self.isAtomicWriteTemporaryFile(fileName) {
            return true
        }
        
        for pattern in ignorePatterns {
            if matchesPattern(fileName, pattern: pattern) {
                return true
            }
        }
        
        return false
    }
    
    /// `index.md.sb-56e0572d-GAYA6W` — the scratch file Foundation writes beside the target
    /// during an atomic save, then renames away.
    ///
    /// Every Cocoa editor saves this way, and so does `String.write(to:atomically: true)`, so a
    /// single save reports two paths: this one and the real file. Without this check the extra
    /// path reaches the callback as a change to a file that no longer exists, doubling the
    /// reported change count and defeating the user's own ignore patterns — `*.tmp` does not
    /// match `notes.tmp.sb-…`, so a pattern meant to silence a file would not silence its save.
    static func isAtomicWriteTemporaryFile(_ fileName: String) -> Bool {
        guard let range = fileName.range(of: ".sb-", options: .backwards) else { return false }
        let suffix = fileName[range.upperBound...]
        // `<8 hex digits>-<random alphanumerics>`. The hex half is a machine identifier and has
        // been eight digits wherever this was checked; requiring that length keeps an ordinary
        // name like `report.sb-abc-def` from being mistaken for a scratch file.
        let parts = suffix.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 8, parts[1].count >= 4 else { return false }
        // ASCII only: `isHexDigit` and `isNumber` accept fullwidth digits and every other
        // script, and a real content file must never be mistaken for a scratch file.
        return parts[0].allSatisfy { $0.isASCII && $0.isHexDigit }
            && parts[1].allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
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

// Basic hot reload errors
public enum BasicHotReloadError: LocalizedError {
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
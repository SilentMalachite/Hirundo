import Foundation

#if os(macOS)
import CoreServices

// FSEvents wrapper for macOS
internal class FSEventsWrapper {
    private let paths: [String]
    private let callback: ([FileChange]) -> Void
    private var streamRef: FSEventStreamRef?
    private let eventQueue = DispatchQueue(label: "com.hirundo.fsevents", attributes: .concurrent)
    
    init(paths: [String], callback: @escaping ([FileChange]) -> Void) {
        self.paths = paths
        // Store callback directly - retain cycle prevention happens at FSEventStreamContext level
        self.callback = callback
    }
    
    deinit {
        stop()
    }
    
    func start() throws {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: { info in
                // Release the retained reference when the stream is deallocated
                if let info = info {
                    Unmanaged<FSEventsWrapper>.fromOpaque(info).release()
                }
            },
            copyDescription: nil
        )
        
        let pathsCFArray = paths as CFArray
        
        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventsCallback,
            &context,
            pathsCFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1, // reduced latency for faster response
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer |
                kFSEventStreamCreateFlagWatchRoot
            )
        )
        
        guard let stream = streamRef else {
            throw HotReloadError.watcherCreationFailed
        }
        
        FSEventStreamSetDispatchQueue(stream, eventQueue)
        
        if !FSEventStreamStart(stream) {
            throw HotReloadError.watcherCreationFailed
        }
        
        // Successfully started watching
    }
    
    func stop() {
        guard let stream = streamRef else { return }
        
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
    }
    
    private let fsEventsCallback: FSEventStreamCallback = { (
        streamRef: ConstFSEventStreamRef,
        clientCallBackInfo: UnsafeMutableRawPointer?,
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>,
        eventIds: UnsafePointer<FSEventStreamEventId>
    ) in
        guard let info = clientCallBackInfo else { return }
        
        let wrapper = Unmanaged<FSEventsWrapper>.fromOpaque(info).takeUnretainedValue()
        let pathsArray = unsafeBitCast(eventPaths, to: CFArray.self)
        
        var paths: [String] = []
        for i in 0..<numEvents {
            if let path = CFArrayGetValueAtIndex(pathsArray, i) {
                let pathString = unsafeBitCast(path, to: CFString.self) as String
                paths.append(pathString)
            }
        }
        
        // Process events
        
        var changes: [FileChange] = []
        let fileManager = FileManager.default
        
        for i in 0..<numEvents {
            let path = paths[i]
            let flags = eventFlags[i]
            
            // Skip directory events (we only care about files)
            if flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 {
                continue
            }
            
            // Proceed even if specific file flags aren't set; some deletions
            // may come without ItemIsFile or specific flags.
            
            // Determine the change type based on flags
            // Note: FSEvents doesn't always set flags as expected, so we need to be flexible
            let type: FileChangeType
            
            // Check if file exists to help determine the event type
            let fileExists = fileManager.fileExists(atPath: path)
            
            // Debug logging for testing
            #if DEBUG
            let isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            if isTestEnvironment && (path.contains(".md") || path.contains("test")) {
                print("FSEvents Debug: path=\(path), flags=\(String(format: "0x%08X", flags)), exists=\(fileExists)")
            }
            #endif
            
            if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                type = .deleted
            } else if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
                type = .created
            } else if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                // Renamed can mean moved, created, or deleted
                if fileExists {
                    type = .created  // File was moved in or renamed to this path
                } else {
                    type = .deleted  // File was moved out or renamed from this path
                }
            } else if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
                type = .modified
            } else if flags & UInt32(kFSEventStreamEventFlagItemInodeMetaMod) != 0 {
                type = .modified  // Metadata change counts as modification
            } else if flags & UInt32(kFSEventStreamEventFlagItemXattrMod) != 0 {
                type = .modified  // Extended attributes change counts as modification
            } else {
                // For generic events, infer based on file existence.
                // Some systems may not set specific flags for deletions.
                if fileExists {
                    type = .modified  // File exists, assume it was modified
                } else {
                    type = .deleted   // File no longer exists; treat as deletion
                }
            }
            
            changes.append(FileChange(path: path, type: type))
        }
        
        if !changes.isEmpty {
            // Report changes
            wrapper.callback(changes)
        }
    }
}

#else

// Fallback implementation for non-macOS platforms
internal class FSEventsWrapper {
    private let paths: [String]
    private let callback: ([FileChange]) -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private let queue = DispatchQueue(label: "com.hirundo.fswatcher")
    
    init(paths: [String], callback: @escaping ([FileChange]) -> Void) {
        self.paths = paths
        self.callback = callback
    }
    
    deinit {
        stop()
    }
    
    func start() throws {
        for path in paths {
            try watchPath(path)
        }
    }
    
    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }
    
    private func watchPath(_ path: String) throws {
        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            throw HotReloadError.cannotOpenPath(path)
        }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        
        source.setEventHandler { [weak self] in
            let change = FileChange(path: path, type: .modified)
            self?.callback([change])
        }
        
        source.setCancelHandler {
            close(fileDescriptor)
        }
        
        source.resume()
        sources.append(source)
    }
}

#endif

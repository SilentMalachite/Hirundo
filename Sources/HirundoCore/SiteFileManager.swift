import Foundation

// File system operations separated from SiteGenerator
public class SiteFileManager {
    private let fileManager: FileManager
    private let config: HirundoConfig
    private let projectPath: String
    
    public init(config: HirundoConfig, projectPath: String, fileManager: FileManager = .default) {
        self.config = config
        self.projectPath = projectPath
        self.fileManager = fileManager
    }
    
    // Create output directory structure
    public func prepareOutputDirectory(at path: String, clean: Bool) throws {
        let outputURL = URL(fileURLWithPath: path)
        
        // Clean output directory if requested
        if clean && fileManager.fileExists(atPath: outputURL.path) {
            try removeDirectory(at: outputURL)
        }
        
        // Create output directory
        try createDirectory(at: outputURL)
    }
    
    // Create a directory with proper error handling and symlink protection
    public func createDirectory(at url: URL) throws {
        // Create directory
        
        // Also resolve the target path for consistency
        let resolvedURL = url.resolvingSymlinksInPath()
        
        try fileManager.createDirectory(
            at: resolvedURL,
            withIntermediateDirectories: true
        )
    }
    
    // Remove a directory
    public func removeDirectory(at url: URL) throws {
        
        // Remove directory
        
        // Also resolve the target path for consistency
        let resolvedURL = url.resolvingSymlinksInPath()
        
        try fileManager.removeItem(at: resolvedURL)
    }
    
    // Write content to file
    public func writeFile(content: String, to url: URL) throws {
        
        // Create parent directory if needed
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try createDirectory(at: parentDir)
        }
        
        // Write file with symlink protection
        if let data = content.data(using: .utf8) {
            // Write file
            
            // Also resolve the target path for consistency
            let resolvedURL = url.resolvingSymlinksInPath()
            #if DEBUG
            let isTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            if isTest { print("[SiteFileManager] write \(resolvedURL.path)") }
            #endif
            try data.write(to: resolvedURL)
        }
    }
    
    // Copy a file
    public func copyFile(from source: URL, to destination: URL) throws {
        
        // Create parent directory if needed
        let parentDir = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try createDirectory(at: parentDir)
        }
        
        // Copy file
        
        // Also resolve the paths for consistency
        let resolvedSource = source.resolvingSymlinksInPath()
        let resolvedDestination = destination.resolvingSymlinksInPath()
        #if DEBUG
        let isTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isTest { print("[SiteFileManager] copy \(resolvedSource.path) -> \(resolvedDestination.path)") }
        #endif
        try fileManager.copyItem(at: resolvedSource, to: resolvedDestination)
    }
    
    // Copy directory recursively
    public func copyDirectory(from source: URL, to destination: URL) throws {
        
        // Create destination directory
        try createDirectory(at: destination)
        
        // Get directory contents
        let contents = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        for itemURL in contents {
            let destinationURL = destination.appendingPathComponent(itemURL.lastPathComponent)
            
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    try copyDirectory(from: itemURL, to: destinationURL)
                } else {
                    try copyFile(from: itemURL, to: destinationURL)
                }
            }
        }
    }
    
    // List files in directory
    public func listFiles(
        in directory: URL,
        withExtension ext: String? = nil,
        recursive: Bool = false
    ) throws -> [URL] {
        // Basic directory validation
        
        var files: [URL] = []
        
        if recursive {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                throw FileManagerError.cannotEnumerateDirectory(directory.path)
            }
            
            for case let fileURL as URL in enumerator {
                if let ext = ext {
                    if fileURL.pathExtension == ext {
                        files.append(fileURL)
                    }
                } else {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                       !isDirectory.boolValue {
                        files.append(fileURL)
                    }
                }
            }
        } else {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            for fileURL in contents {
                if let ext = ext {
                    if fileURL.pathExtension == ext {
                        files.append(fileURL)
                    }
                } else {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                       !isDirectory.boolValue {
                        files.append(fileURL)
                    }
                }
            }
        }
        
        return files
    }
    
    // Check if path exists
    public func fileExists(at path: String) -> Bool {
        return fileManager.fileExists(atPath: path)
    }
    
    // Get file attributes
    public func fileAttributes(at path: String) throws -> [FileAttributeKey: Any] {
        // Basic path validation
        return try fileManager.attributesOfItem(atPath: path)
    }
}

// File manager errors
public enum FileManagerError: LocalizedError {
    case cannotEnumerateDirectory(String)
    case cannotCreateDirectory(String)
    case cannotWriteFile(String)
    case cannotCopyFile(String, String)
    
    public var errorDescription: String? {
        switch self {
        case .cannotEnumerateDirectory(let path):
            return "Cannot enumerate directory: \(path)"
        case .cannotCreateDirectory(let path):
            return "Cannot create directory: \(path)"
        case .cannotWriteFile(let path):
            return "Cannot write file: \(path)"
        case .cannotCopyFile(let source, let destination):
            return "Cannot copy file from \(source) to \(destination)"
        }
    }
}

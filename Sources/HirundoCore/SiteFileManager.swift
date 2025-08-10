import Foundation

// File system operations separated from SiteGenerator
public class SiteFileManager {
    private let fileManager: FileManager
    private let config: HirundoConfig
    private let securityValidator: SecurityValidator
    private let projectPath: String
    
    public init(config: HirundoConfig, securityValidator: SecurityValidator, projectPath: String, fileManager: FileManager = .default) {
        self.config = config
        self.securityValidator = securityValidator
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
        // Use FileSecurityUtilities for symlink-safe directory creation
        // Resolve the basePath to handle system symlinks like /var -> /private/var
        let outputPath = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.outputDirectory)
            .resolvingSymlinksInPath()
            .path
        
        // Also resolve the target path for consistency
        let resolvedURL = url.resolvingSymlinksInPath()
        
        try FileSecurityUtilities.createDirectory(
            at: resolvedURL.path,
            withIntermediateDirectories: true,
            basePath: outputPath
        )
    }
    
    // Remove a directory with symlink protection
    public func removeDirectory(at url: URL) throws {
        try securityValidator.validatePath(url.path, withinBaseDirectory: url.deletingLastPathComponent().path)
        
        // Use FileSecurityUtilities for symlink-safe removal
        // Resolve the basePath to handle system symlinks like /var -> /private/var
        let outputPath = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.outputDirectory)
            .resolvingSymlinksInPath()
            .path
        
        // Also resolve the target path for consistency
        let resolvedURL = url.resolvingSymlinksInPath()
        
        try FileSecurityUtilities.removeItem(
            at: resolvedURL.path,
            basePath: outputPath
        )
    }
    
    // Write content to file with symlink protection
    public func writeFile(content: String, to url: URL) throws {
        try securityValidator.validatePath(url.path, withinBaseDirectory: url.deletingLastPathComponent().path)
        
        // Create parent directory if needed
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try createDirectory(at: parentDir)
        }
        
        // Write file with symlink protection
        if let data = content.data(using: .utf8) {
            // Resolve the basePath to handle system symlinks like /var -> /private/var
            let outputPath = URL(fileURLWithPath: projectPath)
                .appendingPathComponent(config.build.outputDirectory)
                .resolvingSymlinksInPath()
                .path
            
            // Also resolve the target path for consistency
            let resolvedURL = url.resolvingSymlinksInPath()
            
            try FileSecurityUtilities.writeData(
                data,
                toPath: resolvedURL.path,
                basePath: outputPath
            )
        }
    }
    
    // Copy a file with symlink protection
    public func copyFile(from source: URL, to destination: URL) throws {
        try securityValidator.validatePath(source.path, withinBaseDirectory: source.deletingLastPathComponent().path)
        try securityValidator.validatePath(destination.path, withinBaseDirectory: destination.deletingLastPathComponent().path)
        
        // Create parent directory if needed
        let parentDir = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try createDirectory(at: parentDir)
        }
        
        // Copy file with symlink protection
        // Resolve the basePath to handle system symlinks like /var -> /private/var
        let outputPath = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.outputDirectory)
            .resolvingSymlinksInPath()
            .path
        
        // Also resolve the paths for consistency
        let resolvedSource = source.resolvingSymlinksInPath()
        let resolvedDestination = destination.resolvingSymlinksInPath()
        
        try FileSecurityUtilities.copyItem(
            at: resolvedSource.path,
            to: resolvedDestination.path,
            basePath: outputPath
        )
    }
    
    // Copy directory recursively
    public func copyDirectory(from source: URL, to destination: URL) throws {
        try securityValidator.validatePath(source.path, withinBaseDirectory: source.deletingLastPathComponent().path)
        try securityValidator.validatePath(destination.path, withinBaseDirectory: destination.deletingLastPathComponent().path)
        
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
        try securityValidator.validatePath(directory.path, withinBaseDirectory: directory.path)
        
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
        try securityValidator.validatePath(path, withinBaseDirectory: URL(fileURLWithPath: path).deletingLastPathComponent().path)
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
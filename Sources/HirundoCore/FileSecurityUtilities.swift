import Foundation

/// Comprehensive file security utilities for symlink attack protection
public struct FileSecurityUtilities {
    
    /// Maximum allowed symlink depth to prevent infinite loops
    private static let maxSymlinkDepth = 10
    
    /// Validates that a path is safe from symlink attacks
    /// - Parameters:
    ///   - path: The path to validate
    ///   - allowSymlinks: Whether to allow symlinks at all
    ///   - basePath: Optional base path that the resolved path must be within
    /// - Returns: The resolved, safe path
    /// - Throws: FileSecurityError if the path is unsafe
    public static func validatePath(_ path: String, 
                                   allowSymlinks: Bool = false,
                                   basePath: String? = nil) throws -> String {
        // First resolve all symlinks in the path (including system symlinks like /var -> /private/var)
        let resolvedURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let resolvedPath = resolvedURL.path
        
        // Check if path exists
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            // Non-existent paths are safe to create
            // But still check if they would be within basePath
            if let basePath = basePath {
                let baseURL = URL(fileURLWithPath: basePath).resolvingSymlinksInPath().standardized
                let normalizedResolved = resolvedURL.standardized.path
                
                if !normalizedResolved.hasPrefix(baseURL.path) && !normalizedResolved.hasPrefix(baseURL.path + "/") {
                    throw FileSecurityError.pathTraversalAttempt(normalizedResolved)
                }
            }
            return resolvedURL.standardized.path
        }
        
        // Get file attributes on the resolved path
        let attributes = try FileManager.default.attributesOfItem(atPath: resolvedPath)
        let fileType = attributes[.type] as? FileAttributeType
        
        // Check if the resolved file itself is a symlink (should be rare after resolving)
        if fileType == .typeSymbolicLink {
            if !allowSymlinks {
                throw FileSecurityError.symlinkNotAllowed(path)
            }
        }
        
        // If a base path is specified, ensure resolved path is within it
        if let basePath = basePath {
            // Also resolve the base path to handle system symlinks
            let baseURL = URL(fileURLWithPath: basePath).resolvingSymlinksInPath().standardized
            
            if !resolvedPath.hasPrefix(baseURL.path) && !resolvedPath.hasPrefix(baseURL.path + "/") {
                throw FileSecurityError.pathTraversalAttempt(resolvedPath)
            }
        }
        
        return resolvedPath
    }
    
    /// Recursively resolves a symlink with depth protection
    private static func resolveSymlink(_ path: String, depth: Int) throws -> String {
        guard depth < maxSymlinkDepth else {
            throw FileSecurityError.symlinkDepthExceeded(path)
        }
        
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: path)
        
        // Convert relative paths to absolute
        let absoluteDestination: String
        if destination.hasPrefix("/") {
            absoluteDestination = destination
        } else {
            let baseURL = URL(fileURLWithPath: path).deletingLastPathComponent()
            absoluteDestination = baseURL.appendingPathComponent(destination).standardized.path
        }
        
        // Check if the destination exists
        guard FileManager.default.fileExists(atPath: absoluteDestination) else {
            throw FileSecurityError.symlinkDestinationNotFound(absoluteDestination)
        }
        
        // Check if destination is also a symlink
        let destAttributes = try FileManager.default.attributesOfItem(atPath: absoluteDestination)
        if destAttributes[.type] as? FileAttributeType == .typeSymbolicLink {
            return try resolveSymlink(absoluteDestination, depth: depth + 1)
        }
        
        return absoluteDestination
    }
    
    /// Creates a file safely with symlink protection
    public static func createFile(atPath path: String, 
                                 contents: Data?,
                                 attributes: [FileAttributeKey: Any]? = nil,
                                 basePath: String? = nil) throws {
        // Validate parent directory
        let url = URL(fileURLWithPath: path)
        let parentPath = url.deletingLastPathComponent().path
        
        if FileManager.default.fileExists(atPath: parentPath) {
            _ = try validatePath(parentPath, allowSymlinks: false, basePath: basePath)
        }
        
        // Check if file already exists
        if FileManager.default.fileExists(atPath: path) {
            let validatedPath = try validatePath(path, allowSymlinks: false, basePath: basePath)
            
            // Remove existing file safely
            try FileManager.default.removeItem(atPath: validatedPath)
        }
        
        // Create the file
        guard FileManager.default.createFile(atPath: path, contents: contents, attributes: attributes) else {
            throw FileSecurityError.fileCreationFailed(path)
        }
    }
    
    /// Writes data to a file safely with symlink protection
    public static func writeData(_ data: Data, 
                                toPath path: String,
                                basePath: String? = nil) throws {
        // Resolve symlinks in the path first
        let resolvedURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let resolvedPath = resolvedURL.path
        
        // If basePath is provided, ensure we're within it
        if let basePath = basePath {
            let resolvedBase = URL(fileURLWithPath: basePath).resolvingSymlinksInPath().path
            
            if !resolvedPath.hasPrefix(resolvedBase) && !resolvedPath.hasPrefix(resolvedBase + "/") {
                throw FileSecurityError.pathTraversalAttempt(resolvedPath)
            }
        }
        
        // Create parent directory if needed
        let parentURL = resolvedURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentURL.path) {
            try FileManager.default.createDirectory(
                at: parentURL,
                withIntermediateDirectories: true
            )
        }
        
        // Write the data
        try data.write(to: resolvedURL)
    }
    
    /// Copies an item safely with symlink protection
    public static func copyItem(at source: String, 
                               to destination: String,
                               basePath: String? = nil) throws {
        // Resolve symlinks in both paths
        let resolvedSource = URL(fileURLWithPath: source).resolvingSymlinksInPath()
        let resolvedDest = URL(fileURLWithPath: destination).resolvingSymlinksInPath()
        
        // Check if source exists
        guard FileManager.default.fileExists(atPath: resolvedSource.path) else {
            throw FileSecurityError.fileCreationFailed(source)
        }
        
        // If basePath is provided, ensure both paths are within it
        if let basePath = basePath {
            let resolvedBase = URL(fileURLWithPath: basePath).resolvingSymlinksInPath().path
            
            if !resolvedSource.path.hasPrefix(resolvedBase) && !resolvedSource.path.hasPrefix(resolvedBase + "/") {
                throw FileSecurityError.pathTraversalAttempt(resolvedSource.path)
            }
            
            if !resolvedDest.path.hasPrefix(resolvedBase) && !resolvedDest.path.hasPrefix(resolvedBase + "/") {
                throw FileSecurityError.pathTraversalAttempt(resolvedDest.path)
            }
        }
        
        // Create parent directory if needed
        let destParent = resolvedDest.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destParent.path) {
            try FileManager.default.createDirectory(
                at: destParent,
                withIntermediateDirectories: true
            )
        }
        
        // Remove destination if it exists
        if FileManager.default.fileExists(atPath: resolvedDest.path) {
            try FileManager.default.removeItem(at: resolvedDest)
        }
        
        // Copy the item
        try FileManager.default.copyItem(at: resolvedSource, to: resolvedDest)
    }
    
    /// Moves an item safely with symlink protection
    public static func moveItem(at source: String,
                               to destination: String,
                               basePath: String? = nil) throws {
        // Validate source
        let validatedSource = try validatePath(source, allowSymlinks: false, basePath: basePath)
        
        // Validate destination parent directory
        let destURL = URL(fileURLWithPath: destination)
        let destParent = destURL.deletingLastPathComponent().path
        
        if FileManager.default.fileExists(atPath: destParent) {
            _ = try validatePath(destParent, allowSymlinks: false, basePath: basePath)
        }
        
        // Check if destination exists
        if FileManager.default.fileExists(atPath: destination) {
            _ = try validatePath(destination, allowSymlinks: false, basePath: basePath)
            try FileManager.default.removeItem(atPath: destination)
        }
        
        // Move the item
        try FileManager.default.moveItem(atPath: validatedSource, toPath: destination)
    }
    
    /// Removes an item safely with symlink protection
    public static func removeItem(at path: String,
                                 basePath: String? = nil) throws {
        // Resolve symlinks in the path first
        let resolvedURL = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let resolvedPath = resolvedURL.path
        
        // Check if the item exists
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            // Item doesn't exist, nothing to remove
            return
        }
        
        // If basePath is provided, ensure we're within it
        if let basePath = basePath {
            let resolvedBase = URL(fileURLWithPath: basePath).resolvingSymlinksInPath().path
            
            if !resolvedPath.hasPrefix(resolvedBase) && !resolvedPath.hasPrefix(resolvedBase + "/") {
                throw FileSecurityError.pathTraversalAttempt(resolvedPath)
            }
        }
        
        // Remove the item
        try FileManager.default.removeItem(atPath: resolvedPath)
    }
    
    /// Creates a directory safely with symlink protection
    public static func createDirectory(at path: String,
                                      withIntermediateDirectories: Bool = false,
                                      attributes: [FileAttributeKey: Any]? = nil,
                                      basePath: String? = nil) throws {
        // First resolve any symlinks in the path (like /var -> /private/var)
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        
        // If basePath is provided, resolve it too and check containment
        if let basePath = basePath {
            let resolvedBase = URL(fileURLWithPath: basePath).resolvingSymlinksInPath().path
            
            // Ensure the resolved path is within the resolved base path
            if !resolvedPath.hasPrefix(resolvedBase) && !resolvedPath.hasPrefix(resolvedBase + "/") {
                throw FileSecurityError.pathTraversalAttempt(resolvedPath)
            }
        }
        
        // Now create the directory using the resolved path
        if withIntermediateDirectories {
            try FileManager.default.createDirectory(
                atPath: resolvedPath,
                withIntermediateDirectories: true,
                attributes: attributes
            )
        } else {
            // Check parent exists
            let parentURL = URL(fileURLWithPath: resolvedPath).deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentURL.path) {
                throw FileSecurityError.fileCreationFailed(resolvedPath)
            }
            
            try FileManager.default.createDirectory(
                atPath: resolvedPath,
                withIntermediateDirectories: false,
                attributes: attributes
            )
        }
    }
}

/// File security-related errors
public enum FileSecurityError: LocalizedError {
    case symlinkNotAllowed(String)
    case symlinkDepthExceeded(String)
    case symlinkDestinationNotFound(String)
    case pathTraversalAttempt(String)
    case fileCreationFailed(String)
    case notADirectory(String)
    
    public var errorDescription: String? {
        switch self {
        case .symlinkNotAllowed(let path):
            return "Symbolic links are not allowed: \(path)"
        case .symlinkDepthExceeded(let path):
            return "Symbolic link depth exceeded (possible loop): \(path)"
        case .symlinkDestinationNotFound(let path):
            return "Symbolic link destination not found: \(path)"
        case .pathTraversalAttempt(let path):
            return "Path traversal attempt detected: \(path)"
        case .fileCreationFailed(let path):
            return "Failed to create file: \(path)"
        case .notADirectory(let path):
            return "Path exists but is not a directory: \(path)"
        }
    }
}
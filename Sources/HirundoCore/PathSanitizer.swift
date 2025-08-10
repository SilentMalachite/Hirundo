import Foundation

/// Thread-safe path sanitization with caching for performance optimization
public final class PathSanitizer {
    private static let shared = PathSanitizer()
    
    // Cache for sanitized paths with LRU eviction
    private var cache = [String: String]()
    private var accessOrder = [String]()
    private let maxCacheSize = 1000
    private let queue = DispatchQueue(label: "com.hirundo.pathsanitizer", attributes: .concurrent)
    
    // Statistics for monitoring
    private var cacheHits = 0
    private var cacheMisses = 0
    
    private init() {}
    
    /// Sanitizes a path and caches the result for performance
    /// - Parameter path: The path to sanitize
    /// - Returns: A sanitized path safe for file operations
    public static func sanitize(_ path: String) -> String {
        return shared.sanitizePath(path)
    }
    
    /// Clears the sanitization cache
    public static func clearCache() {
        shared.clearCacheInternal()
    }
    
    /// Gets cache statistics for monitoring
    public static func getCacheStatistics() -> (hits: Int, misses: Int, size: Int) {
        return shared.getStatistics()
    }
    
    private func sanitizePath(_ path: String) -> String {
        // Check cache first
        if let cached = getCached(path) {
            return cached
        }
        
        // Perform sanitization
        let sanitized = performSanitization(path)
        
        // Cache the result
        setCached(path, sanitized)
        
        return sanitized
    }
    
    private func getCached(_ path: String) -> String? {
        return queue.sync {
            if let cached = cache[path] {
                cacheHits += 1
                // Update access order for LRU
                if let index = accessOrder.firstIndex(of: path) {
                    accessOrder.remove(at: index)
                }
                accessOrder.append(path)
                return cached
            }
            cacheMisses += 1
            return nil
        }
    }
    
    private func setCached(_ path: String, _ sanitized: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Add to cache
            self.cache[path] = sanitized
            self.accessOrder.append(path)
            
            // Evict oldest entries if cache is too large
            while self.cache.count > self.maxCacheSize {
                if let oldest = self.accessOrder.first {
                    self.accessOrder.removeFirst()
                    self.cache.removeValue(forKey: oldest)
                }
            }
        }
    }
    
    private func performSanitization(_ path: String) -> String {
        // Early return for obviously invalid paths
        if path.isEmpty || path.contains("\0") {
            return ""
        }
        
        // Check for obvious path traversal attempts
        if path.contains("..") || path.contains("./") || path.hasPrefix("/") {
            return ""
        }
        
        // Split path into components and filter out dangerous ones
        let components = path.components(separatedBy: "/")
            .filter { component in
                // Remove empty components, current directory (.), and parent directory (..)
                !component.isEmpty && 
                component != "." && 
                component != ".." &&
                !component.contains("\0") &&
                !component.contains("\r") &&
                !component.contains("\n")
            }
            .map { component in
                // Additional sanitization for each component
                var sanitized = component
                
                // Remove leading/trailing whitespace
                sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Replace multiple spaces with single space
                sanitized = sanitized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                
                // Remove control characters
                sanitized = sanitized.replacingOccurrences(of: "[\\x00-\\x1F\\x7F]", with: "", options: .regularExpression)
                
                return sanitized
            }
            .filter { !$0.isEmpty } // Remove any empty components after sanitization
        
        let result = components.joined(separator: "/")
        
        // Final validation
        if result.hasPrefix("/") || result.hasPrefix("\\") || result.contains("://") {
            return ""
        }
        
        return result
    }
    
    private func clearCacheInternal() {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
            self?.accessOrder.removeAll()
            self?.cacheHits = 0
            self?.cacheMisses = 0
        }
    }
    
    private func getStatistics() -> (hits: Int, misses: Int, size: Int) {
        return queue.sync {
            (hits: cacheHits, misses: cacheMisses, size: cache.count)
        }
    }
}

/// Extension for validating paths within base directories
extension PathSanitizer {
    /// Validates that a path is safe and within the expected directory
    /// - Parameters:
    ///   - path: The path to validate
    ///   - baseDirectory: The base directory that should contain the path
    /// - Returns: True if the path is safe, false otherwise
    public static func isPathSafe(_ path: String, withinBaseDirectory baseDirectory: String) -> Bool {
        // First sanitize the path
        let sanitizedPath = sanitize(path)
        
        // If sanitization resulted in empty path, it's unsafe
        if sanitizedPath.isEmpty {
            return false
        }
        
        // Resolve all symbolic links and relative components
        let basePath = URL(fileURLWithPath: baseDirectory).standardizedFileURL.resolvingSymlinksInPath()
        let potentialPath = basePath.appendingPathComponent(sanitizedPath)
        
        // Check if the path exists and is a symlink
        var isSymlink = false
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: potentialPath.path) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: potentialPath.path)
                if let fileType = attributes[.type] as? FileAttributeType {
                    isSymlink = (fileType == .typeSymbolicLink)
                }
            } catch {
                // If we can't read attributes, treat as unsafe
                return false
            }
        }
        
        // Resolve symlinks if needed
        let fullPath = isSymlink ? potentialPath.resolvingSymlinksInPath() : potentialPath.standardizedFileURL
        
        // Ensure the resolved path is still within the base directory
        let basePathString = basePath.path
        let fullPathString = fullPath.path
        
        // Check if the path is exactly the base path or is a subdirectory
        return fullPathString == basePathString || fullPathString.hasPrefix(basePathString + "/")
    }
}
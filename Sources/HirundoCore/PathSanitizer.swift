import Foundation

/// Thread-safe path sanitization (pure function, no caching)
public enum PathSanitizer {
    
    /// Sanitizes a path to make it safe for file operations
    /// - Parameter path: The path to sanitize
    /// - Returns: A sanitized path safe for file operations
    public static func sanitize(_ path: String) -> String {
        return performSanitization(path)
    }
    
    private static func performSanitization(_ path: String) -> String {
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
}

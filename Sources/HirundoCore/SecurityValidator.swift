import Foundation

// Security validation separated from SiteGenerator
public class SecurityValidator {
    private let projectPath: String
    private let config: HirundoConfig
    
    public init(projectPath: String, config: HirundoConfig) {
        self.projectPath = projectPath
        self.config = config
    }
    
    // Validate a file path is safe and within bounds
    public func validatePath(_ path: String, withinBaseDirectory baseDirectory: String) throws {
        // First validate raw path before sanitization
        if path.contains("\0") {
            throw SecurityError.invalidPath(path, reason: "Path contains null bytes")
        }
        
        if path.count > config.limits.maxFilenameLength {
            throw SecurityError.pathTooLong(path, limit: config.limits.maxFilenameLength)
        }
        
        // Check for suspicious patterns before sanitization
        if containsSuspiciousPattern(path) {
            throw SecurityError.invalidPath(path, reason: "Path contains suspicious patterns")
        }
        
        // Handle absolute paths by converting to relative if they're within the base directory
        let canonicalBase = URL(fileURLWithPath: baseDirectory).standardized.path
        let canonicalPath = URL(fileURLWithPath: path).standardized.path
        
        // Check if the canonical path is within the base directory
        if !canonicalPath.hasPrefix(canonicalBase) {
            throw SecurityError.pathTraversal(path)
        }
        
        // For absolute paths within the base directory, we can proceed with validation
        // Convert to relative path for sanitization if it's absolute and within base
        let pathToSanitize: String
        if canonicalPath.hasPrefix(canonicalBase) {
            if canonicalPath == canonicalBase {
                pathToSanitize = "."
            } else {
                // Remove the base directory prefix to get relative path
                let relativePath = String(canonicalPath.dropFirst(canonicalBase.count))
                pathToSanitize = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
            }
        } else {
            pathToSanitize = path
        }
        
        let sanitized = sanitizePath(pathToSanitize)
        
        if sanitized.isEmpty && !pathToSanitize.isEmpty {
            throw SecurityError.invalidPath(path, reason: "Path sanitization resulted in empty path")
        }
    }
    
    // Sanitize a path by delegating to PathSanitizer to avoid duplication
    public func sanitizePath(_ path: String) -> String {
        return PathSanitizer.sanitize(path)
    }
    
    // Clear the path cache (delegates to PathSanitizer)
    public func clearCache() {
        PathSanitizer.clearCache()
    }
    
    // Check if a path is safe (no directory traversal)
    public func isPathSafe(_ path: String, withinBaseDirectory baseDirectory: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedBase = URL(fileURLWithPath: baseDirectory).standardizedFileURL.path
        
        // Check if the normalized path starts with the base directory
        return normalizedPath.hasPrefix(normalizedBase)
    }
    
    // Validate file size
    public func validateFileSize(at path: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw SecurityError.cannotDetermineFileSize(path)
        }
        
        let maxSize: Int64
        if path.hasSuffix(".md") || path.hasSuffix(".markdown") {
            maxSize = Int64(config.limits.maxMarkdownFileSize)
        } else if path.hasSuffix(".yaml") || path.hasSuffix(".yml") {
            maxSize = Int64(config.limits.maxConfigFileSize)
        } else {
            // Default max size for other files
            maxSize = Int64(config.limits.maxMarkdownFileSize)
        }
        
        if fileSize > maxSize {
            throw SecurityError.fileTooLarge(path, size: fileSize, limit: maxSize)
        }
    }
    
    // Validate metadata values
    public func validateMetadata(_ metadata: [String: Any]) throws {
        // Validate title length
        if let title = metadata["title"] as? String {
            if title.count > config.limits.maxTitleLength {
                throw SecurityError.metadataTooLong("title", length: title.count, limit: config.limits.maxTitleLength)
            }
        }
        
        // Validate description length
        if let description = metadata["description"] as? String {
            if description.count > config.limits.maxDescriptionLength {
                throw SecurityError.metadataTooLong("description", length: description.count, limit: config.limits.maxDescriptionLength)
            }
        }
        
        // Check for suspicious patterns in metadata
        for (key, value) in metadata {
            if let stringValue = value as? String {
                // Check for script injection attempts
                if containsSuspiciousPattern(stringValue) {
                    throw SecurityError.suspiciousContent(key, value: stringValue)
                }
            }
        }
    }
    
    // Sanitize HTML content for template
    public func sanitizeForTemplate(_ text: String) -> String {
        // Simple HTML entity escaping for template safety
        // This provides basic XSS protection without being overly restrictive
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    
    private func containsSuspiciousPattern(_ text: String) -> Bool {
        let suspiciousPatterns = [
            "<script",
            "javascript:",
            "onerror=",
            "onload=",
            "onclick=",
            "eval(",
            "document.cookie",
            "window.location",
            ".innerHTML",
            "data:text/html"
        ]
        
        let lowercased = text.lowercased()
        for pattern in suspiciousPatterns {
            if lowercased.contains(pattern) {
                return true
            }
        }
        
        return false
    }
}

// Security errors
public enum SecurityError: LocalizedError {
    case pathTraversal(String)
    case invalidPath(String, reason: String)
    case pathTooLong(String, limit: Int)
    case fileTooLarge(String, size: Int64, limit: Int64)
    case cannotDetermineFileSize(String)
    case metadataTooLong(String, length: Int, limit: Int)
    case suspiciousContent(String, value: String)
    
    public var errorDescription: String? {
        switch self {
        case .pathTraversal(let path):
            return "Path traversal attempt detected: \(path)"
        case .invalidPath(let path, let reason):
            return "Invalid path '\(path)': \(reason)"
        case .pathTooLong(let path, let limit):
            return "Path too long '\(path)': exceeds limit of \(limit) characters"
        case .fileTooLarge(let path, let size, let limit):
            return "File too large '\(path)': \(size) bytes exceeds limit of \(limit) bytes"
        case .cannotDetermineFileSize(let path):
            return "Cannot determine file size for: \(path)"
        case .metadataTooLong(let field, let length, let limit):
            return "Metadata field '\(field)' too long: \(length) characters exceeds limit of \(limit)"
        case .suspiciousContent(let field, let value):
            return "Suspicious content in field '\(field)': \(value)"
        }
    }
}
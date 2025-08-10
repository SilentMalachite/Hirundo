import Foundation

// Security validation separated from SiteGenerator
public class SecurityValidator {
    private let projectPath: String
    private let config: HirundoConfig
    
    // Path sanitization cache for performance
    private var pathCache: [String: String] = [:]
    private let cacheQueue = DispatchQueue(label: "com.hirundo.pathcache", attributes: .concurrent)
    private let maxCacheSize = 1000
    
    public init(projectPath: String, config: HirundoConfig) {
        self.projectPath = projectPath
        self.config = config
    }
    
    // Validate a file path is safe and within bounds
    public func validatePath(_ path: String, withinBaseDirectory baseDirectory: String) throws {
        let sanitized = sanitizePath(path)
        
        if !isPathSafe(sanitized, withinBaseDirectory: baseDirectory) {
            throw SecurityError.pathTraversal(path)
        }
        
        // Check for null bytes
        if path.contains("\0") {
            throw SecurityError.invalidPath(path, reason: "Path contains null bytes")
        }
        
        // Check path length
        if path.count > config.limits.maxFilenameLength {
            throw SecurityError.pathTooLong(path, limit: config.limits.maxFilenameLength)
        }
    }
    
    // Sanitize a path by resolving .. and . components with caching
    public func sanitizePath(_ path: String) -> String {
        // Check cache first
        let cached = cacheQueue.sync {
            return pathCache[path]
        }
        
        if let cachedPath = cached {
            return cachedPath
        }
        
        // Remove any null bytes
        var sanitized = path.replacingOccurrences(of: "\0", with: "")
        
        // Normalize the path
        let url = URL(fileURLWithPath: sanitized)
        sanitized = url.standardizedFileURL.path
        
        // Remove any double slashes
        while sanitized.contains("//") {
            sanitized = sanitized.replacingOccurrences(of: "//", with: "/")
        }
        
        // Add to cache with size limit enforcement
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Evict oldest entries if cache is full
            if self.pathCache.count >= self.maxCacheSize {
                // Remove 20% of cache entries (LRU approximation)
                let entriesToRemove = self.maxCacheSize / 5
                let keysToRemove = Array(self.pathCache.keys.prefix(entriesToRemove))
                for key in keysToRemove {
                    self.pathCache.removeValue(forKey: key)
                }
            }
            
            self.pathCache[path] = sanitized
        }
        
        return sanitized
    }
    
    // Clear the path cache
    public func clearCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.pathCache.removeAll()
        }
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
        var sanitized = text
        
        // Escape HTML entities
        sanitized = sanitized
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
        
        // Remove any script tags (extra safety)
        let scriptPattern = #"<script[^>]*>.*?</script>"#
        if let regex = try? NSRegularExpression(pattern: scriptPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            sanitized = regex.stringByReplacingMatches(in: sanitized, options: [], range: NSRange(location: 0, length: sanitized.count), withTemplate: "")
        }
        
        // Remove any event handlers
        let eventPattern = #"\s*on\w+\s*=\s*["'][^"']*["']"#
        if let regex = try? NSRegularExpression(pattern: eventPattern, options: .caseInsensitive) {
            sanitized = regex.stringByReplacingMatches(in: sanitized, options: [], range: NSRange(location: 0, length: sanitized.count), withTemplate: "")
        }
        
        // Remove javascript: protocol
        sanitized = sanitized.replacingOccurrences(of: "javascript:", with: "", options: .caseInsensitive)
        
        // Remove data: protocol for potential XSS
        let dataPattern = #"data:[^,]*script[^,]*,"#
        if let regex = try? NSRegularExpression(pattern: dataPattern, options: .caseInsensitive) {
            sanitized = regex.stringByReplacingMatches(in: sanitized, options: [], range: NSRange(location: 0, length: sanitized.count), withTemplate: "")
        }
        
        return sanitized
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
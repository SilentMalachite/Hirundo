import Foundation
import CryptoKit

// AssetConcatenationRule is defined in Assets/AssetConcatenationRule.swift

// Asset pipeline for processing static assets
public class AssetPipeline {
    private let pluginManager: PluginManager
    private let fileManager = FileManager.default
    
    // Configuration
    public var enableFingerprinting: Bool = false
    public var enableSourceMaps: Bool = false
    public var excludePatterns: [String] = []
    public var concatenationRules: [AssetConcatenationRule] = []
    public var cssOptions: CSSProcessingOptions = CSSProcessingOptions()
    public var jsOptions: JSProcessingOptions = JSProcessingOptions()
    
    public init(pluginManager: PluginManager) {
        self.pluginManager = pluginManager
    }
    
    // Process all assets from source to destination
    public func processAssets(from sourcePath: String, to destinationPath: String) throws -> [String: String] {
        var manifest: [String: String] = [:]
        
        // Create destination directory
        try fileManager.createDirectory(
            atPath: destinationPath,
            withIntermediateDirectories: true
        )
        
        // First, handle concatenation rules
        if !concatenationRules.isEmpty {
            try processConcatenationRules(
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                manifest: &manifest
            )
        }
        
        // Process individual assets
        let sourceURL = URL(fileURLWithPath: sourcePath)
        try processDirectory(
            sourceURL,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            manifest: &manifest
        )
        
        return manifest
    }
    
    // Detect asset type from filename
    public func detectAssetType(for filename: String) -> AssetItem.AssetType {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        
        switch ext {
        case "css":
            return .css
        case "js", "javascript", "mjs":
            return .javascript
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "ico":
            return .image(ext)
        default:
            return .other(ext)
        }
    }
    
    // Save manifest to file
    public func saveManifest(_ manifest: [String: String], to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(manifest)
        try data.write(to: URL(fileURLWithPath: path))
    }
    
    // Load manifest from file
    public func loadManifest(from path: String) throws -> [String: String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode([String: String].self, from: data)
    }
    
    // Process a directory recursively
    private func processDirectory(
        _ directoryURL: URL,
        sourcePath: String,
        destinationPath: String,
        manifest: inout [String: String]
    ) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        
        for itemURL in contents {
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            
            if isDirectory {
                // Recurse into subdirectory
                try processDirectory(
                    itemURL,
                    sourcePath: sourcePath,
                    destinationPath: destinationPath,
                    manifest: &manifest
                )
            } else {
                // Process file
                let standardizedItemPath = itemURL.standardizedFileURL.path
                let standardizedSourcePath = URL(fileURLWithPath: sourcePath).standardizedFileURL.path
                let relativePath = standardizedItemPath.replacingOccurrences(of: standardizedSourcePath + "/", with: "")
                
                // Check if file should be excluded
                if shouldExclude(path: relativePath) {
                    continue
                }
                
                // Check if file was already processed by concatenation
                if isConcatenatedFile(relativePath) {
                    continue
                }
                
                try processFile(
                    itemURL,
                    relativePath: relativePath,
                    sourcePath: sourcePath,
                    destinationPath: destinationPath,
                    manifest: &manifest
                )
            }
        }
    }
    
    // Process a single file
    private func processFile(
        _ fileURL: URL,
        relativePath: String,
        sourcePath: String,
        destinationPath: String,
        manifest: inout [String: String]
    ) throws {
        let assetType = detectAssetType(for: fileURL.lastPathComponent)
        
        // Sanitize the relative path to prevent path traversal attacks
        let sanitizedRelativePath = sanitizePath(relativePath)
        
        // Validate that the sanitized path is safe
        guard isPathSafe(sanitizedRelativePath, withinBaseDirectory: destinationPath) else {
            throw AssetPipelineError.pathTraversalAttempt(relativePath)
        }
        
        // Create asset item
        var outputPath = URL(fileURLWithPath: destinationPath)
            .appendingPathComponent(sanitizedRelativePath)
            .path
        
        // Generate fingerprint if enabled
        let fingerprint: String?
        if enableFingerprinting {
            fingerprint = try generateFingerprint(for: fileURL)
            guard let validFingerprint = fingerprint else {
                throw AssetPipelineError.processingFailed("Failed to generate fingerprint for file: \(fileURL.path)")
            }
            outputPath = addFingerprint(to: outputPath, fingerprint: validFingerprint)
        } else {
            fingerprint = nil
        }
        
        // Ensure output directory exists
        let outputURL = URL(fileURLWithPath: outputPath)
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // Create asset item for plugin processing
        let asset = AssetItem(
            sourcePath: fileURL.path,
            outputPath: outputPath,
            type: assetType
        )
        
        // Process through built-in pipeline first
        try processAssetContent(asset)
        
        // Then process through plugins
        let processedAsset = try pluginManager.processAsset(asset)
        
        // If not processed by plugins, copy the file
        if !processedAsset.processed {
            // Remove existing file if it exists
            if fileManager.fileExists(atPath: outputPath) {
                try fileManager.removeItem(atPath: outputPath)
            }
            try fileManager.copyItem(atPath: fileURL.path, toPath: outputPath)
        }
        
        // Update manifest
        if enableFingerprinting {
            manifest[relativePath] = outputURL.lastPathComponent
        }
    }
    
    // Process concatenation rules
    private func processConcatenationRules(
        sourcePath: String,
        destinationPath: String,
        manifest: inout [String: String]
    ) throws {
        for rule in concatenationRules {
            let files = try findFiles(matching: rule.pattern, in: sourcePath)
            
            if files.isEmpty {
                continue
            }
            
            // Concatenate files
            var concatenatedContent = ""
            for (index, file) in files.enumerated() {
                if index > 0 {
                    concatenatedContent += rule.separator
                }
                concatenatedContent += try String(contentsOfFile: file, encoding: .utf8)
            }
            
            // Write concatenated file
            let outputPath = URL(fileURLWithPath: destinationPath)
                .appendingPathComponent(rule.output)
            
            try fileManager.createDirectory(
                at: outputPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            // Apply fingerprinting if enabled
            var finalOutputPath = outputPath.path
            if enableFingerprinting {
                let fingerprint = generateFingerprint(for: concatenatedContent)
                finalOutputPath = addFingerprint(to: finalOutputPath, fingerprint: fingerprint)
                manifest[rule.output] = URL(fileURLWithPath: finalOutputPath).lastPathComponent
            }
            
            try concatenatedContent.write(to: URL(fileURLWithPath: finalOutputPath), atomically: true, encoding: .utf8)
        }
    }
    
    // Find files matching a pattern
    private func findFiles(matching pattern: String, in directory: String) throws -> [String] {
        var files: [String] = []
        let directoryURL = URL(fileURLWithPath: directory)
        
        // Simple glob pattern matching
        let components = pattern.components(separatedBy: "/")
        let filePattern = components.last ?? ""
        let subdirectory = components.dropLast().joined(separator: "/")
        
        let searchURL = subdirectory.isEmpty ? directoryURL : directoryURL.appendingPathComponent(subdirectory)
        
        if fileManager.fileExists(atPath: searchURL.path) {
            let contents = try fileManager.contentsOfDirectory(at: searchURL, includingPropertiesForKeys: nil)
            
            for url in contents {
                if matchesPattern(url.lastPathComponent, pattern: filePattern) {
                    files.append(url.path)
                }
            }
        }
        
        return files.sorted()
    }
    
    // Check if path should be excluded
    private func shouldExclude(path: String) -> Bool {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        
        for pattern in excludePatterns {
            if matchesPattern(filename, pattern: pattern) {
                return true
            }
        }
        
        return false
    }
    
    // Check if file was processed by concatenation
    private func isConcatenatedFile(_ path: String) -> Bool {
        for rule in concatenationRules {
            if matchesPattern(path, pattern: rule.pattern) {
                return true
            }
        }
        return false
    }
    
    // Simple pattern matching
    private func matchesPattern(_ string: String, pattern: String) -> Bool {
        if pattern == "*" {
            return true
        } else if pattern.hasPrefix("*") && pattern.hasSuffix("*") {
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
    
    // Generate fingerprint for file
    private func generateFingerprint(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return generateFingerprint(for: data)
    }
    
    // Generate fingerprint for content
    private func generateFingerprint(for content: String) -> String {
        let data = content.data(using: .utf8) ?? Data()
        return generateFingerprint(for: data)
    }
    
    // Generate fingerprint for data
    private func generateFingerprint(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        // Use 16 characters (64-bit) instead of 8 for better collision resistance
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16).lowercased()
    }
    
    // Process asset content based on type
    private func processAssetContent(_ asset: AssetItem) throws {
        switch asset.type {
        case .css:
            try processCSSThroughPipeline(asset)
        case .javascript:
            try processJSThroughPipeline(asset)
        default:
            // For other assets, just copy
            if asset.sourcePath != asset.outputPath {
                // Remove existing file if it exists
                if fileManager.fileExists(atPath: asset.outputPath) {
                    try fileManager.removeItem(atPath: asset.outputPath)
                }
                try fileManager.copyItem(atPath: asset.sourcePath, toPath: asset.outputPath)
            }
        }
    }
    
    // Process CSS file through pipeline
    private func processCSSThroughPipeline(_ asset: AssetItem) throws {
        let content = try String(contentsOfFile: asset.sourcePath, encoding: .utf8)
        let processed = processCSS(content, options: cssOptions)
        try processed.write(toFile: asset.outputPath, atomically: true, encoding: .utf8)
    }
    
    // Process JavaScript file through pipeline
    private func processJSThroughPipeline(_ asset: AssetItem) throws {
        let content = try String(contentsOfFile: asset.sourcePath, encoding: .utf8)
        let processed = processJS(content, options: jsOptions)
        try processed.write(toFile: asset.outputPath, atomically: true, encoding: .utf8)
    }
    
    // Add fingerprint to filename
    private func addFingerprint(to path: String, fingerprint: String) -> String {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension
        let nameWithoutExt = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()
        
        let newName = "\(nameWithoutExt)-\(fingerprint)"
        return directory
            .appendingPathComponent(newName)
            .appendingPathExtension(ext)
            .path
    }
    
    // Process CSS content
    public func processCSS(_ content: String, options: CSSProcessingOptions = CSSProcessingOptions()) -> String {
        var processed = content
        
        if options.autoprefixer {
            processed = addCSSVendorPrefixes(processed)
        }
        
        if options.minify {
            processed = minifyCSS(processed)
        }
        
        return processed
    }
    
    // Process JavaScript content
    public func processJS(_ content: String, options: JSProcessingOptions = JSProcessingOptions()) -> String {
        var processed = content
        
        if options.transpile {
            processed = transpileJS(processed, target: options.target)
        }
        
        if options.minify {
            processed = minifyJS(processed)
        }
        
        return processed
    }
    
    // Safe CSS minification with validation
    private func minifyCSS(_ css: String) -> String {
        // Validate CSS before processing
        guard isValidCSS(css) else {
            print("⚠️ Invalid CSS detected, skipping minification")
            return css
        }
        
        var minified = css
        
        // Step 1: Remove comments (careful not to break strings)
        var inString = false
        var stringChar: Character? = nil
        var result = ""
        var i = css.startIndex
        
        while i < css.endIndex {
            let char = css[i]
            
            if !inString && (char == "\"" || char == "'") {
                inString = true
                stringChar = char
                result.append(char)
            } else if inString && char == stringChar {
                inString = false
                stringChar = nil
                result.append(char)
            } else if !inString && char == "/" && i < css.index(before: css.endIndex) {
                let nextIndex = css.index(after: i)
                if css[nextIndex] == "*" {
                    // Skip comment
                    i = nextIndex
                    while i < css.endIndex {
                        if css[i] == "*" && i < css.index(before: css.endIndex) {
                            let nextIndex = css.index(after: i)
                            if css[nextIndex] == "/" {
                                i = css.index(after: nextIndex)
                                break
                            }
                        }
                        i = css.index(after: i)
                    }
                    continue
                } else {
                    result.append(char)
                }
            } else {
                result.append(char)
            }
            
            i = css.index(after: i)
        }
        
        minified = result
        
        // Step 2: Normalize whitespace (preserve strings)
        minified = minified.components(separatedBy: .newlines).joined(separator: " ")
        minified = minified.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        // Step 3: Remove whitespace around safe characters
        let safePatterns = [
            (#"\s*{\s*"#, "{"),
            (#"\s*}\s*"#, "}"),
            (#"\s*;\s*"#, ";"),
            (#"\s*:\s*"#, ":"),
            (#"\s*,\s*"#, ",")
        ]
        
        for (pattern, replacement) in safePatterns {
            minified = minified.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        
        return minified.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Validate CSS syntax
    private func isValidCSS(_ css: String) -> Bool {
        // Basic CSS validation
        let braceCount = css.filter { $0 == "{" }.count - css.filter { $0 == "}" }.count
        return braceCount == 0 // Balanced braces
    }
    
    // Safe JavaScript minification with validation
    private func minifyJS(_ js: String) -> String {
        // Validate JavaScript before processing
        guard isValidJS(js) else {
            print("⚠️ Invalid JavaScript detected, skipping minification")
            return js
        }
        
        var minified = js
        
        // Step 1: Remove comments safely (preserve strings and regex)
        minified = removeJSComments(from: minified)
        
        // Step 2: Normalize whitespace
        minified = minified.components(separatedBy: .newlines).joined(separator: " ")
        minified = minified.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        // Step 3: Remove safe whitespace around operators
        let safePatterns = [
            (#"\s*{\s*"#, "{"),
            (#"\s*}\s*"#, "}"),
            (#"\s*;\s*"#, ";"),
            (#"\s*,\s*"#, ",")
        ]
        
        for (pattern, replacement) in safePatterns {
            minified = minified.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        
        return minified.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Remove JavaScript comments while preserving strings and regex
    private func removeJSComments(from js: String) -> String {
        var result = ""
        var i = js.startIndex
        var inString = false
        var stringChar: Character? = nil
        var inRegex = false
        
        while i < js.endIndex {
            let char = js[i]
            
            if !inString && !inRegex && (char == "\"" || char == "'") {
                inString = true
                stringChar = char
                result.append(char)
            } else if inString && char == stringChar && (i == js.startIndex || js[js.index(before: i)] != "\\") {
                inString = false
                stringChar = nil
                result.append(char)
            } else if !inString && !inRegex && char == "/" && i < js.index(before: js.endIndex) {
                let nextIndex = js.index(after: i)
                let nextChar = js[nextIndex]
                
                if nextChar == "/" {
                    // Single line comment - skip to end of line
                    while i < js.endIndex && js[i] != "\n" {
                        i = js.index(after: i)
                    }
                    continue
                } else if nextChar == "*" {
                    // Multi-line comment - skip to */
                    i = nextIndex
                    while i < js.index(before: js.endIndex) {
                        if js[i] == "*" && js[js.index(after: i)] == "/" {
                            i = js.index(after: js.index(after: i))
                            break
                        }
                        i = js.index(after: i)
                    }
                    continue
                } else {
                    // Could be regex - basic detection
                    let prevNonWhiteIndex = findPreviousNonWhitespace(in: js, before: i)
                    if let prevIndex = prevNonWhiteIndex {
                        let prevChar = js[prevIndex]
                        if "=([,;:!&|".contains(prevChar) {
                            inRegex = true
                        }
                    }
                    result.append(char)
                }
            } else if inRegex && char == "/" && (i == js.startIndex || js[js.index(before: i)] != "\\") {
                inRegex = false
                result.append(char)
            } else {
                result.append(char)
            }
            
            i = js.index(after: i)
        }
        
        return result
    }
    
    // Helper function to find previous non-whitespace character
    private func findPreviousNonWhitespace(in string: String, before index: String.Index) -> String.Index? {
        var current = string.index(before: index)
        while current > string.startIndex {
            if !string[current].isWhitespace {
                return current
            }
            current = string.index(before: current)
        }
        return nil
    }
    
    // Basic JavaScript validation
    private func isValidJS(_ js: String) -> Bool {
        // Basic validation: check for balanced braces and parentheses
        let braceCount = js.filter { $0 == "{" }.count - js.filter { $0 == "}" }.count
        let parenCount = js.filter { $0 == "(" }.count - js.filter { $0 == ")" }.count
        let bracketCount = js.filter { $0 == "[" }.count - js.filter { $0 == "]" }.count
        
        return braceCount == 0 && parenCount == 0 && bracketCount == 0
    }
    
    // Add CSS vendor prefixes (basic implementation)
    private func addCSSVendorPrefixes(_ css: String) -> String {
        var prefixed = css
        
        // Transform properties that need prefixes
        let prefixMap = [
            "transform": ["-webkit-transform", "-moz-transform", "-ms-transform"],
            "transition": ["-webkit-transition", "-moz-transition", "-ms-transition"],
            "box-shadow": ["-webkit-box-shadow", "-moz-box-shadow"],
            "border-radius": ["-webkit-border-radius", "-moz-border-radius"],
            "user-select": ["-webkit-user-select", "-moz-user-select", "-ms-user-select"]
        ]
        
        for (property, prefixes) in prefixMap {
            let pattern = #"\b"# + property + #"\s*:"#
            prefixed = prefixed.replacingOccurrences(
                of: pattern,
                with: prefixes.map { "\($0):" }.joined(separator: " ") + " \(property):",
                options: .regularExpression
            )
        }
        
        return prefixed
    }
    
    // JavaScript transpilation (disabled for safety)
    private func transpileJS(_ js: String, target: String) -> String {
        print("⚠️ JavaScript transpilation is disabled for safety reasons.")
        print("   Use a dedicated build tool like Babel or esbuild for ES6+ transpilation.")
        print("   Returning original JavaScript unchanged.")
        
        // Return original JavaScript unchanged
        // Transpilation with regex is unreliable and can break code
        return js
    }
    
    // MARK: - Security Utilities
    
    /// Sanitizes a file path to prevent path traversal attacks
    /// - Parameter path: The path to sanitize
    /// - Returns: A sanitized path safe for file operations
    private func sanitizePath(_ path: String) -> String {
        // Use centralized path sanitizer with caching
        return PathSanitizer.sanitize(path)
    }
    
    // Keep original implementation as fallback for specific asset pipeline needs
    private func sanitizePathLegacy(_ path: String) -> String {
        // First, check for obvious path traversal attempts
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
                !component.contains("\\") && // Block Windows path separators
                !component.hasPrefix("~") && // Block home directory references
                !component.contains(":") // Block Windows drive references and other schemes
            }
            .map { component in
                // Remove any null bytes and other dangerous characters
                var cleaned = component
                    .replacingOccurrences(of: "\0", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\t", with: "")
                
                // Remove Unicode control characters
                cleaned = cleaned.components(separatedBy: .controlCharacters).joined()
                
                // Limit component length to prevent very long filenames
                if cleaned.count > 255 {
                    cleaned = String(cleaned.prefix(255))
                }
                
                return cleaned
            }
            .filter { !$0.isEmpty } // Remove any components that became empty after cleaning
        
        let result = components.joined(separator: "/")
        
        // Additional validation: ensure the path doesn't start with dangerous patterns
        if result.hasPrefix("/") || result.hasPrefix("\\") || result.contains("://") {
            return ""
        }
        
        return result
    }
    
    /// Validates that a path is safe and within the expected directory
    /// - Parameters:
    ///   - path: The path to validate
    ///   - baseDirectory: The base directory that should contain the path
    /// - Returns: True if the path is safe, false otherwise
    private func isPathSafe(_ path: String, withinBaseDirectory baseDirectory: String) -> Bool {
        // Use centralized path validator
        return PathSanitizer.isPathSafe(path, withinBaseDirectory: baseDirectory)
    }
}

// AssetPipelineError is defined in Assets/AssetPipelineError.swift

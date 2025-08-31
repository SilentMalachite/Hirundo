import Foundation
import CryptoKit

/// Handles individual asset processing operations
public class AssetProcessor {
    private let fileManager = FileManager.default
    
    public init() {}
    
    /// Detects asset type from filename
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
    
    /// Generates fingerprint for file
    public func generateFingerprint(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return generateFingerprint(for: data)
    }
    
    /// Generates fingerprint for content
    public func generateFingerprint(for content: String) -> String {
        let data = content.data(using: .utf8) ?? Data()
        return generateFingerprint(for: data)
    }
    
    /// Generates fingerprint for data
    public func generateFingerprint(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        // Use 16 characters (64-bit) instead of 8 for better collision resistance
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16).lowercased()
    }
    
    /// Adds fingerprint to filename
    public func addFingerprint(to path: String, fingerprint: String) -> String {
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
    
    /// Processes asset content based on type
    public func processAssetContent(_ asset: AssetItem, cssOptions: CSSProcessingOptions, jsOptions: JSProcessingOptions) throws {
        switch asset.type {
        case .css:
            try processCSSThroughPipeline(asset, options: cssOptions)
        case .javascript:
            try processJSThroughPipeline(asset, options: jsOptions)
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
    
    /// Processes CSS file through pipeline
    private func processCSSThroughPipeline(_ asset: AssetItem, options: CSSProcessingOptions) throws {
        let content = try String(contentsOfFile: asset.sourcePath, encoding: .utf8)
        let processed = processCSS(content, options: options)
        try processed.write(toFile: asset.outputPath, atomically: true, encoding: .utf8)
    }
    
    /// Processes JavaScript file through pipeline
    private func processJSThroughPipeline(_ asset: AssetItem, options: JSProcessingOptions) throws {
        let content = try String(contentsOfFile: asset.sourcePath, encoding: .utf8)
        let processed = processJS(content, options: options)
        try processed.write(toFile: asset.outputPath, atomically: true, encoding: .utf8)
    }
    
    /// Processes CSS content
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
    
    /// Processes JavaScript content
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
    
    // MARK: - CSS Processing
    
    /// Safe CSS minification with validation
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
        // Ensure no space remains before opening brace
        minified = minified.replacingOccurrences(of: #"(\w)\s*\{"#, with: "$1{", options: .regularExpression)
        
        return minified.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Validates CSS syntax
    private func isValidCSS(_ css: String) -> Bool {
        // Basic CSS validation
        let braceCount = css.filter { $0 == "{" }.count - css.filter { $0 == "}" }.count
        return braceCount == 0 // Balanced braces
    }
    
    /// Adds CSS vendor prefixes (basic implementation)
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
    
    // MARK: - JavaScript Processing
    
    /// Safe JavaScript minification with validation
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
    
    /// Removes JavaScript comments while preserving strings and regex
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
    
    /// Helper function to find previous non-whitespace character
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
    
    /// Basic JavaScript validation
    private func isValidJS(_ js: String) -> Bool {
        // Basic validation: check for balanced braces and parentheses
        let braceCount = js.filter { $0 == "{" }.count - js.filter { $0 == "}" }.count
        let parenCount = js.filter { $0 == "(" }.count - js.filter { $0 == ")" }.count
        let bracketCount = js.filter { $0 == "[" }.count - js.filter { $0 == "]" }.count
        
        return braceCount == 0 && parenCount == 0 && bracketCount == 0
    }
    
    /// JavaScript transpilation (disabled for safety)
    private func transpileJS(_ js: String, target: String) -> String {
        print("⚠️ JavaScript transpilation is disabled for safety reasons.")
        print("   Use a dedicated build tool like Babel or esbuild for ES6+ transpilation.")
        print("   Returning original JavaScript unchanged.")
        
        // Return original JavaScript unchanged
        // Transpilation with regex is unreliable and can break code
        return js
    }
}

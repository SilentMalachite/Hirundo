import Foundation

/// Handles file operations for asset processing
public class AssetFileManager {
    private let fileManager = FileManager.default
    
    public init() {}
    
    /// Saves manifest to file
    public func saveManifest(_ manifest: [String: String], to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(manifest)
        try data.write(to: URL(fileURLWithPath: path))
    }
    
    /// Loads manifest from file
    public func loadManifest(from path: String) throws -> [String: String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode([String: String].self, from: data)
    }
    
    /// Processes a directory recursively
    public func processDirectory(
        _ directoryURL: URL,
        sourcePath: String,
        destinationPath: String,
        excludePatterns: [String],
        concatenationRules: [AssetConcatenationRule],
        onFile: (URL, String) throws -> Void
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
                    excludePatterns: excludePatterns,
                    concatenationRules: concatenationRules,
                    onFile: onFile
                )
            } else {
                // Process file
                let standardizedItemPath = itemURL.standardizedFileURL.path
                let standardizedSourcePath = URL(fileURLWithPath: sourcePath).standardizedFileURL.path
                let relativePath = standardizedItemPath.replacingOccurrences(of: standardizedSourcePath + "/", with: "")
                
                // Check if file should be excluded
                if shouldExclude(path: relativePath, patterns: excludePatterns) {
                    continue
                }
                
                // Check if file was already processed by concatenation
                if isConcatenatedFile(relativePath, rules: concatenationRules) {
                    continue
                }
                
                try onFile(itemURL, relativePath)
            }
        }
    }
    
    /// Finds files matching a pattern
    public func findFiles(matching pattern: String, in directory: String) throws -> [String] {
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
    
    /// Checks if path should be excluded
    private func shouldExclude(path: String, patterns: [String]) -> Bool {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        
        for pattern in patterns {
            if matchesPattern(filename, pattern: pattern) {
                return true
            }
        }
        
        return false
    }
    
    /// Checks if file was processed by concatenation
    private func isConcatenatedFile(_ path: String, rules: [AssetConcatenationRule]) -> Bool {
        for rule in rules {
            if matchesPattern(path, pattern: rule.pattern) {
                return true
            }
        }
        return false
    }
    
    /// Simple pattern matching
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
}
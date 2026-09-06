import Foundation

/// Handles file operations for asset processing
public class AssetFileManager {
    private let fileManager = FileManager.default
    
    public init() {}
    
    /// Saves manifest to file
    public func saveManifest(_ manifest: AssetManifest, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Loads manifest from file
    public func loadManifest(from path: String) throws -> AssetManifest {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(AssetManifest.self, from: data)
    }
    
    /// Processes a directory recursively
    public func processDirectory(
        _ directoryURL: URL,
        sourcePath: String,
        excludePatterns: [String],
        onFile: (URL, String) throws -> Void
    ) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for itemURL in contents {
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDirectory {
                try processDirectory(
                    itemURL,
                    sourcePath: sourcePath,
                    excludePatterns: excludePatterns,
                    onFile: onFile
                )
            } else {
                let standardizedItemPath = itemURL.standardizedFileURL.path
                let standardizedSourcePath = URL(fileURLWithPath: sourcePath).standardizedFileURL.path
                let relativePath = standardizedItemPath.replacingOccurrences(of: standardizedSourcePath + "/", with: "")

                if shouldExclude(path: relativePath, patterns: excludePatterns) {
                    continue
                }

                try onFile(itemURL, relativePath)
            }
        }
    }

    /// Checks if path should be excluded.
    ///
    /// パターンは**ファイル名**にのみ照合される。`css/*.tmp` のようなディレクトリ付きの
    /// パターンは意図どおりには効かない。
    private func shouldExclude(path: String, patterns: [String]) -> Bool {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        
        for pattern in patterns {
            if matchesPattern(filename, pattern: pattern) {
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
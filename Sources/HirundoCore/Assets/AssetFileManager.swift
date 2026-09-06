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
    
    /// Processes a directory recursively.
    ///
    /// シンボリックリンクは**解決先がソースディレクトリの中に収まる場合だけ**たどる。外を指す
    /// リンクは警告を出して読まずに飛ばす。`static/leak.txt -> /etc/passwd` のようなリンクを
    /// 含むツリーをビルドしても、リンク先の中身が公開成果物へ出ていかないようにするため。
    public func processDirectory(
        _ directoryURL: URL,
        sourcePath: String,
        excludePatterns: [String],
        onFile: (URL, String) throws -> Void
    ) throws {
        let rootPath = URL(fileURLWithPath: sourcePath).resolvingSymlinksInPath().path
        var visitedDirectories: Set<String> = []
        try processDirectory(
            directoryURL,
            sourcePath: sourcePath,
            rootPath: rootPath,
            excludePatterns: excludePatterns,
            visitedDirectories: &visitedDirectories,
            onFile: onFile
        )
    }

    private func processDirectory(
        _ directoryURL: URL,
        sourcePath: String,
        rootPath: String,
        excludePatterns: [String],
        visitedDirectories: inout Set<String>,
        onFile: (URL, String) throws -> Void
    ) throws {
        // リンクがソース内の祖先ディレクトリを指している場合の無限再帰を止める。
        guard visitedDirectories.insert(directoryURL.resolvingSymlinksInPath().path).inserted else { return }

        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )

        for itemURL in contents {
            let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isSymbolicLink = values?.isSymbolicLink ?? false

            if isSymbolicLink && !isContained(itemURL, in: rootPath) {
                warn("\(itemURL.lastPathComponent): symbolic link resolves outside "
                     + "\(rootPath); skipped")
                continue
            }

            // リンク自身の `.isDirectoryKey` は環境によって解決されないため、リンクのときは
            // 解決先で種別を判定する。
            let isDirectory = isSymbolicLink
                ? (try? itemURL.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                : values?.isDirectory ?? false

            if isDirectory {
                try processDirectory(
                    itemURL,
                    sourcePath: sourcePath,
                    rootPath: rootPath,
                    excludePatterns: excludePatterns,
                    visitedDirectories: &visitedDirectories,
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

    /// 解決先が `rootPath` の中（またはそれ自身）か。
    private func isContained(_ url: URL, in rootPath: String) -> Bool {
        let resolved = url.resolvingSymlinksInPath().path
        if resolved == rootPath { return true }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return resolved.hasPrefix(prefix)
    }

    private func warn(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("⚠️  \(message)\n".utf8))
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
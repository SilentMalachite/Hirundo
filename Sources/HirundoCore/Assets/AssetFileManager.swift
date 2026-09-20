import Foundation

/// Handles file operations for asset processing
public class AssetFileManager {
    private let fileManager = FileManager.default
    
    public init() {}
    
    /// The manifest's bytes, for a caller that knows where it is allowed to put them.
    ///
    /// This type used to write the file itself, to any path it was handed, with no containment
    /// check and no atomic flag — so `_site/asset-manifest.json` left as a link to somewhere
    /// outside was followed. Encoding and writing are separated so the write can go through
    /// `SiteFileManager` like every other generated file.
    public func encodedManifest(_ manifest: AssetManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
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
            relativePrefix: startingPrefix(for: directoryURL, sourcePath: sourcePath),
            excludePatterns: excludePatterns,
            visitedDirectories: &visitedDirectories,
            onFile: onFile
        )
    }

    /// Where `directoryURL` sits under `sourcePath`, as a relative prefix.
    ///
    /// Empty whenever the walk starts at the source directory itself, which is the only way
    /// `AssetPipeline` calls this. A caller that starts deeper gets the prefix its files deserve;
    /// one that starts outside gets `""`, and the paths reported are relative to where it began.
    private func startingPrefix(for directoryURL: URL, sourcePath: String) -> String {
        let relative = PathBoundary.relativePath(
            of: directoryURL.standardizedFileURL.path,
            under: URL(fileURLWithPath: sourcePath).standardizedFileURL.path
        )
        guard let relative, !relative.isEmpty else { return "" }
        return relative + "/"
    }

    private func processDirectory(
        _ directoryURL: URL,
        sourcePath: String,
        rootPath: String,
        relativePrefix: String,
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

            // 壊れたリンクは解決できず、行き先が中か外かを確かめようがない。飛ばして黙らせる
            // のではなく通し、`AssetPipeline.write` に「読めないソース」として報告させる ──
            // ソース側の書き間違いなので、作者に見えなければ意味がない。
            let isBrokenLink = isSymbolicLink && !fileManager.fileExists(atPath: itemURL.path)

            if isSymbolicLink && !isBrokenLink && !isContained(itemURL, in: rootPath) {
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
                    relativePrefix: relativePrefix + itemURL.lastPathComponent + "/",
                    excludePatterns: excludePatterns,
                    visitedDirectories: &visitedDirectories,
                    onFile: onFile
                )
            } else {
                // The relative path is accumulated on the way down, not subtracted from the
                // absolute one on the way out. Subtracting cannot be made correct here: the
                // enumerator reports its own spelling (`/private/var/…` where the configuration
                // says `/var/…`), `standardizedFileURL` folds the two together only for a path
                // that resolves, and `resolvingSymlinksInPath()` on the source normalises the
                // other way — so a *broken* link matches neither spelling of its own directory.
                // Before this it was `replacingOccurrences`, which removed the source
                // directory's spelling wherever it sat, so a tree repeating it
                // (`static/<the whole of static's own path>/logo.png`) lost both copies and
                // published the file at the wrong depth under the wrong manifest key.
                //
                // Accumulating also keeps a symbolic link that stays inside the source
                // directory at the name its author gave it, rather than its target's.
                let relativePath = relativePrefix + itemURL.lastPathComponent

                if shouldExclude(path: relativePath, patterns: excludePatterns) {
                    continue
                }

                try onFile(itemURL, relativePath)
            }
        }
    }

    /// 解決先が `rootPath` の中（またはそれ自身）か。
    private func isContained(_ url: URL, in rootPath: String) -> Bool {
        PathBoundary.contains(url.resolvingSymlinksInPath().path, in: rootPath)
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
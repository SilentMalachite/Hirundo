import Foundation

/// 出力ツリーから、今回のビルドが生成しなかったフィンガープリント済みアセットを取り除く。
///
/// `hirundo serve` は clean せずに再ビルドするため、これが無いとハッシュ名の出力が世代ごとに
/// 積み上がっていく。
///
/// 削除するのは次の3つを**すべて**満たすファイルだけ。
///
/// 1. `static/` のトップレベル要素に対応する出力の範囲にあること
/// 2. 名前がフィンガープリント形（`<name>-<16桁の小文字16進数>.<ext>`）であること
/// 3. 現在のマニフェストの値に含まれないこと
///
/// 条件2があるため、`content/css/foo.md` が `_site/css/foo/index.html` を生むようなパスの
/// 衝突があってもページ出力を消すことは構造上あり得ない。
public enum AssetPruner {

    /// `<name>-<16桁の小文字16進数>.<ext>` か。
    public static func isFingerprintedName(_ name: String) -> Bool {
        let url = URL(fileURLWithPath: name)
        guard !url.pathExtension.isEmpty else { return false }

        let stem = url.deletingPathExtension().lastPathComponent
        guard let dash = stem.lastIndex(of: "-") else { return false }

        let hash = stem[stem.index(after: dash)...]
        guard hash.count == 16 else { return false }
        return hash.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    public static func prune(
        outputDirectory: URL,
        staticDirectory: URL,
        keeping manifest: AssetManifest,
        fileManager: FileManager = .default
    ) throws {
        let keep = manifest.outputPaths
        let topLevel = (try? fileManager.contentsOfDirectory(atPath: staticDirectory.path)) ?? []

        for entry in topLevel {
            var isDirectory: ObjCBool = false
            let sourceEntry = staticDirectory.appendingPathComponent(entry)
            guard fileManager.fileExists(atPath: sourceEntry.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                let scope = outputDirectory.appendingPathComponent(entry)
                guard fileManager.fileExists(atPath: scope.path),
                      let walker = fileManager.enumerator(
                        at: scope,
                        includingPropertiesForKeys: [.isRegularFileKey]
                      ) else { continue }

                for case let fileURL as URL in walker {
                    guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                    else { continue }
                    try pruneIfStale(fileURL, outputDirectory: outputDirectory, keep: keep, fileManager: fileManager)
                }
            } else {
                // トップレベルのファイルは出力でハッシュ名になっているので、名前の完全一致では
                // 見つからない。語幹が一致する出力ルート直下のファイルを候補にする。
                let stem = URL(fileURLWithPath: entry).deletingPathExtension().lastPathComponent
                let siblings = (try? fileManager.contentsOfDirectory(atPath: outputDirectory.path)) ?? []
                for sibling in siblings where sibling.hasPrefix(stem + "-") {
                    try pruneIfStale(
                        outputDirectory.appendingPathComponent(sibling),
                        outputDirectory: outputDirectory,
                        keep: keep,
                        fileManager: fileManager
                    )
                }
            }
        }
    }

    private static func pruneIfStale(
        _ fileURL: URL,
        outputDirectory: URL,
        keep: Set<String>,
        fileManager: FileManager
    ) throws {
        guard isFingerprintedName(fileURL.lastPathComponent) else { return }
        guard let relativePath = relativePath(of: fileURL, under: outputDirectory) else { return }
        guard !keep.contains(relativePath) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private static func relativePath(of fileURL: URL, under root: URL) -> String? {
        let filePath = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }
}

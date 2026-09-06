import Foundation

/// 出力ツリーから、今回のビルドが生成しなかったフィンガープリント済みアセットを取り除く。
///
/// `hirundo serve` は clean せずに再ビルドするため、これが無いとハッシュ名の出力が世代ごとに
/// 積み上がっていく。
///
/// 削除するのは次の3つを**すべて**満たすファイルだけ。
///
/// 1. 出力ルートの中で、次のどちらかの範囲にあること
///    - `static/` のトップレベル要素に対応する出力の範囲
///    - 前回のマニフェストが記録している出力（`static/images/` ごと消したときのように、
///      今回のトップレベル一覧からは届かない範囲は、これだけが知っている）
/// 2. 名前がフィンガープリント形（`<name>-<16桁の小文字16進数>.<ext>`）であること
/// 3. 現在のマニフェストの値に含まれないこと
///
/// 条件2があるため、`content/css/foo.md` が `_site/css/foo/index.html` を生むようなパスの
/// 衝突があってもページ出力を消すことは構造上あり得ない。固定 URL のアセット（`robots.txt`
/// など、`AssetNamePolicy` を参照）もハッシュ名にならないので、同じ条件で守られる。
public enum AssetPruner {

    /// `<name>-<16桁の小文字16進数>.<ext>` か、拡張子の無いアセット（`CNAME` など）由来の
    /// `<name>-<16桁の小文字16進数>` か。
    public static func isFingerprintedName(_ name: String) -> Bool {
        let url = URL(fileURLWithPath: name)
        let stem = url.pathExtension.isEmpty ? name : url.deletingPathExtension().lastPathComponent
        guard let dash = stem.lastIndex(of: "-") else { return false }

        let hash = stem[stem.index(after: dash)...]
        guard hash.count == 16 else { return false }
        return hash.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    public static func prune(
        outputDirectory: URL,
        staticDirectory: URL,
        keeping manifest: AssetManifest,
        previous: AssetManifest = AssetManifest(),
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
                    let siblingURL = outputDirectory.appendingPathComponent(sibling)
                    guard (try? siblingURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                    else { continue }
                    try pruneIfStale(
                        siblingURL,
                        outputDirectory: outputDirectory,
                        keep: keep,
                        fileManager: fileManager
                    )
                }
            }
        }

        // 前回のマニフェストにしか無い出力。`static/images/` ごと消したときのように、今回の
        // トップレベル一覧からは届かない範囲は、前回のマニフェストだけが知っている。
        for outputPath in previous.outputPaths.subtracting(keep) {
            let fileURL = outputDirectory.appendingPathComponent(outputPath)
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            try pruneIfStale(fileURL, outputDirectory: outputDirectory, keep: keep, fileManager: fileManager)
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

    /// 出力ディレクトリからの相対パス。出力の外なら `nil`。
    ///
    /// シンボリックリンクは両辺とも解決してから前方一致を取る。これにより macOS の
    /// `/var` → `/private/var` のようなテンポラリディレクトリの下でも正しく判定でき、
    /// 出力ルートの外を指すシンボリックリンクは前方一致に失敗してスキップされる。
    ///
    /// `SiteGenerator`（書き込みの許可判定）と `AssetPruner`（削除の対象判定）の両方が
    /// この関数に依存している。どちらか一方だけを直すことがないよう、実装は1箇所に保つ。
    internal static func relativePath(of fileURL: URL, under root: URL) -> String? {
        let filePath = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }
}

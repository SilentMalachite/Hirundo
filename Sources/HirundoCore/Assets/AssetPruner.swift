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
/// など、`AssetFingerprintExclusions` を参照）もハッシュ名にならないので、同じ条件で守られる。
///
/// 閉じ込めの判定は `OutputPathGuard` に通す。書き込みと同じ規則で、同じ理由である ── 親は
/// 解決するので出力の外へ出るリンクを経由した削除は届かず、最後の要素は解決しないので
/// `removeItem` が消すのはそこにある実体そのもの（リンクならリンク）になる。
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
        // 削除も書き込みと同じ判定を通す。かつてはここだけが自前の包含判定（両辺を解決する
        // `relativePath`）を持っていて、規則が2系統あることをドキュメントに書き残していた。
        let guardian = OutputPathGuard(
            root: outputDirectory.standardizedFileURL.resolvingSymlinksInPath(),
            fileManager: fileManager
        )

        // 出力が無ければ掃除するものも無い。
        guard fileManager.fileExists(atPath: outputDirectory.path) else { return }

        // `static/` がまるごと消えている場合は「トップレベルに何も無い」として続ける。その状態で
        // 古い出力を知っているのは前回のマニフェストだけなので、ここで throw すると掃除そのものが
        // 走らなくなる。存在するのに読めない（権限エラーなど）は握り潰さず呼び出し元へ伝える。
        let topLevel = fileManager.fileExists(atPath: staticDirectory.path)
            ? try fileManager.contentsOfDirectory(atPath: staticDirectory.path)
            : []
        // トップレベルの各ファイル用の候補探しは同じ出力ルートを毎回列挙するだけなので、
        // ループの外で一度だけ読む。
        let outputDirectoryContents = try fileManager.contentsOfDirectory(atPath: outputDirectory.path)

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
                    guard isPrunableEntry(fileURL) else { continue }
                    try pruneIfStale(fileURL, guardian: guardian, keep: keep)
                }
            } else {
                // トップレベルのファイルは出力でハッシュ名になっているので、名前の完全一致では
                // 見つからない。語幹が一致する出力ルート直下のファイルを候補にする。
                let stem = URL(fileURLWithPath: entry).deletingPathExtension().lastPathComponent
                for sibling in outputDirectoryContents where sibling.hasPrefix(stem + "-") {
                    let siblingURL = outputDirectory.appendingPathComponent(sibling)
                    guard isPrunableEntry(siblingURL) else { continue }
                    try pruneIfStale(siblingURL, guardian: guardian, keep: keep)
                }
            }
        }

        // 前回のマニフェストにしか無い出力。`static/images/` ごと消したときのように、今回の
        // トップレベル一覧からは届かない範囲は、前回のマニフェストだけが知っている。
        for outputPath in previous.outputPaths.subtracting(keep) {
            let fileURL = outputDirectory.appendingPathComponent(outputPath)
            guard isPrunableEntry(fileURL) else { continue }
            try pruneIfStale(fileURL, guardian: guardian, keep: keep)
        }
    }

    /// 掃除の対象になりうる種類か ── 通常ファイルか、シンボリックリンクそのもの。
    ///
    /// リンクを含めるのは、書き込み側が生成物の位置に残ったリンクを取り除くのと同じ理由。
    /// `URLResourceValues` はリンクを辿らないので `isRegularFile` はリンクに対して false
    /// になり、ここを通さないとハッシュ名のリンクは一度も判定に届かず残り続ける。
    /// ディレクトリは（リンクでない限り）ここで落ちるので、実体のディレクトリを消すことはない。
    private static func isPrunableEntry(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        else { return false }
        return values.isRegularFile == true || values.isSymbolicLink == true
    }

    private static func pruneIfStale(
        _ fileURL: URL,
        guardian: OutputPathGuard,
        keep: Set<String>
    ) throws {
        guard isFingerprintedName(fileURL.lastPathComponent) else { return }
        guard let destination = guardian.destination(for: fileURL) else { return }
        guard !keep.contains(guardian.relativePath(of: destination)) else { return }
        try guardian.remove(at: fileURL)
    }
}

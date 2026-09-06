import Foundation

/// フィンガープリント（コンテンツハッシュ付きファイル名への変更）から除外すべきアセットを判定する。
///
/// `robots.txt` や `favicon.ico` のような固定名で取得されるファイルは、どのページからも
/// 参照されないためリンクの書き換えが起きず、フィンガープリントすると404になる。この型は
/// そうしたファイルの一覧を「常に効く組み込みパターン」として持ち、設定側で追加できるように
/// する純粋な述語。I/O や `FileManager` には一切触れない。
public struct AssetFingerprintExclusions: Equatable, Sendable {

    /// 設定に関わらず常に適用されるパターン。
    public static let builtIn: [String] = [
        "robots.txt",
        "favicon.ico",
        "CNAME",
        "_headers",
        "_redirects",
        ".htaccess",
        ".well-known/**",
    ]

    private let patterns: [String]

    /// `additional` は組み込みパターンに追加されるだけで、組み込みを取り除くことはできない。
    public init(additional: [String] = []) {
        patterns = Self.builtIn + additional
    }

    /// `staticRelativePath` は static ディレクトリからの相対パスで、区切りは `/`、
    /// 先頭に `/` は付かない（例: `css/style.css`、`robots.txt`、`.well-known/security.txt`）。
    public func excludes(_ staticRelativePath: String) -> Bool {
        patterns.contains { Self.matches(pattern: $0, path: staticRelativePath) }
    }

    // MARK: - パターンマッチング

    /// 1つのパターンが1つのパスに一致するか。
    ///
    /// - パターンに `/` を含まない場合、パスの**最後の要素**だけに一致させる
    ///   （`ads.txt` は `ads.txt` にも `vendor/ads.txt` にも一致するが、`ads.txt/inside` には
    ///   一致しない ── 最後の要素は常に `inside` になるため）。
    /// - パターンに `/` を含む場合、パス**全体**に一致させる（深い階層への「にじみ出し」を防ぐ）。
    ///
    /// この二分岐だけがこの関数の外側の仕事で、実際のワイルドカード展開（`*` と `**`）は
    /// セグメント列同士の再帰的な比較 `matchSegments` に委ねる。
    static func matches(pattern: String, path: String) -> Bool {
        guard !pattern.isEmpty else { return false }

        if pattern.contains("/") {
            return matchSegments(
                pattern: pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init),
                path: path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            )
        }

        let lastComponent = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
        return matchSegment(pattern: pattern, text: lastComponent)
    }

    /// パターンのセグメント列とパスのセグメント列を先頭から再帰的に比較する。
    ///
    /// `**` はセグメントそのもの（例えば `a/**/b` の真ん中）としてのみ意味を持ち、その場合は
    /// 残りのパスのどの位置からでも再開できる ── ゼロ個のセグメントの読み飛ばしも許すことで、
    /// `a/**/b.txt` が `a/b.txt` に一致するようにする。それ以外のセグメントは `matchSegment` で
    /// `*` を1セグメント内のワイルドカードとして比較する。
    private static func matchSegments(pattern: [String], path: [String]) -> Bool {
        guard let first = pattern.first else { return path.isEmpty }
        let restPattern = Array(pattern.dropFirst())

        if first == "**" {
            // ゼロ個から全部までのセグメントを読み飛ばして、残りのパターンが続きに一致するか試す。
            for count in 0...path.count {
                if matchSegments(pattern: restPattern, path: Array(path.dropFirst(count))) {
                    return true
                }
            }
            return false
        }

        guard let firstPathSegment = path.first else { return false }
        guard matchSegment(pattern: first, text: firstPathSegment) else { return false }
        return matchSegments(pattern: restPattern, path: Array(path.dropFirst()))
    }

    /// 1セグメント内での `*` ワイルドカード比較（`*` は空文字列にも一致する）。
    private static func matchSegment(pattern: String, text: String) -> Bool {
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)

        // `*` を含まないパターンは完全一致のみ。
        if parts.count == 1 { return text == pattern }

        var remaining = Substring(text)

        for (index, part) in parts.enumerated() {
            if index == 0 {
                guard remaining.hasPrefix(part) else { return false }
                remaining.removeFirst(part.count)
                continue
            }
            if index == parts.count - 1 {
                return remaining.hasSuffix(part)
            }
            guard let range = remaining.range(of: part) else { return false }
            remaining = remaining[range.upperBound...]
        }
        return true
    }
}

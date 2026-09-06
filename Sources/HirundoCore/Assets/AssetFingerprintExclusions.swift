import Foundation

/// フィンガープリント（コンテンツハッシュ付きファイル名への変更）から除外すべきアセットを判定する。
///
/// `robots.txt` や `favicon.ico` のような固定名で取得されるファイルは、どのページからも
/// 参照されないためリンクの書き換えが起きず、フィンガープリントすると404になる。この型は
/// そうしたファイルの一覧を「常に効く組み込みパターン」として持ち、設定側で追加できるように
/// する純粋な述語。I/O や `FileManager` には一切触れない。
public struct AssetFingerprintExclusions: Equatable, Sendable {

    /// 設定に関わらず常に適用されるパターン。
    ///
    /// - `robots.txt` / `sitemap.xml`: クローラが URL を直接叩く
    /// - `favicon.ico`: 参照が無くてもブラウザが `/favicon.ico` を取得する
    /// - `CNAME`: GitHub Pages のカスタムドメイン
    /// - `_headers` / `_redirects`: Netlify・Cloudflare Pages のホスティング設定
    /// - `.htaccess`: Apache が**各ディレクトリで**読む（だから深さを問わない）
    /// - `ads.txt` / `app-ads.txt`: IAB の仕様でパスが決まっている
    /// - `sw.js` / `service-worker.js`: JavaScript 内の固定 URL で登録され、制御できる
    ///   範囲（スコープ）がそのパスで決まる
    public static let builtIn: [String] = [
        "robots.txt",
        "sitemap.xml",
        "favicon.ico",
        "CNAME",
        "_headers",
        "_redirects",
        ".htaccess",
        "ads.txt",
        "app-ads.txt",
        "sw.js",
        "service-worker.js",
        ".well-known/**",
    ]

    private let patterns: [String]

    /// `additional` は組み込みパターンに追加されるだけで、組み込みを取り除くことはできない。
    ///
    /// 各パターンの先頭の `/` または `./` は取り除く。`staticRelativePath` は先頭に `/` を
    /// 持たないため、`"/robots.txt"` は「ファイルへの参照のつもり」で書かれた最初の一手だが、
    /// 素通しすると全体パス一致に回されて絶対に一致しなくなる（`"./ads.txt"` も同様）。
    /// 警告なしで一度も一致しないまま静かに壊れるくらいなら、寛容に解釈する。
    public init(additional: [String] = []) {
        patterns = Self.builtIn + additional.map(Self.strippingLeadingSlashOrDotSlash)
    }

    /// パターン先頭の `/` または `./` を1つだけ取り除く。
    private static func strippingLeadingSlashOrDotSlash(_ pattern: String) -> String {
        if pattern.hasPrefix("./") {
            return String(pattern.dropFirst(2))
        }
        if pattern.hasPrefix("/") {
            return String(pattern.dropFirst())
        }
        return pattern
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
            let patternSegments = collapsingConsecutiveDoubleStars(
                pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            )
            return matchSegments(
                pattern: patternSegments,
                path: path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            )
        }

        let lastComponent = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
        return matchSegment(pattern: pattern, text: lastComponent)
    }

    /// 連続する `**` セグメントを1つに畳む。`a/**/**/b` は `a/**/b` と意味的に同じなので、
    /// これは近似ではなく厳密な書き換え。計算量は `matchSegments` のメモ化が抑えるので、
    /// これは正規化にすぎない（メモの行数を減らす程度の効果）。
    private static func collapsingConsecutiveDoubleStars(_ segments: [String]) -> [String] {
        var result: [String] = []
        for segment in segments where !(segment == "**" && result.last == "**") {
            result.append(segment)
        }
        return result
    }

    /// パターンのセグメント列とパスのセグメント列を比較する。
    ///
    /// `**` はセグメントそのもの（例えば `a/**/b` の真ん中）としてのみ意味を持ち、その場合は
    /// ゼロ個以上のセグメントを読み飛ばせる ── ゼロ個も許すことで `a/**/b.txt` が `a/b.txt` に
    /// 一致する。それ以外のセグメントは `matchSegment` で `*` を1セグメント内のワイルドカード
    /// として比較する。
    ///
    /// 状態は `(パターンの添字, パスの添字)` の組で、各状態の結果をメモ化する。`**` が複数ある
    /// パターンでは同じ状態に何度も到達するため、メモ化しないと「`**` ごとに再開位置を全部
    /// 試す」探索がパス長に対して指数的になる（`assets.fingerprintExclude` はユーザー入力なので、
    /// 設定ミス1つでビルドが止まる経路だった）。メモ化すれば状態数はパターン長 × パス長で
    /// 抑えられる。配列を切り出さず添字だけを進めるのも同じ理由（切り出しごとの確保を無くす）。
    private static func matchSegments(pattern: [String], path: [String]) -> Bool {
        // memo[patternIndex][pathIndex]。nil は未計算。
        var memo = [[Bool?]](
            repeating: [Bool?](repeating: nil, count: path.count + 1),
            count: pattern.count + 1
        )

        func match(_ patternIndex: Int, _ pathIndex: Int) -> Bool {
            if let cached = memo[patternIndex][pathIndex] { return cached }

            let result: Bool
            if patternIndex == pattern.count {
                result = pathIndex == path.count
            } else if pattern[patternIndex] == "**" {
                // ゼロ個読み飛ばして次のパターンへ進むか、パスを1つ読み飛ばして `**` に留まるか。
                result = match(patternIndex + 1, pathIndex)
                    || (pathIndex < path.count && match(patternIndex, pathIndex + 1))
            } else if pathIndex < path.count,
                      matchSegment(pattern: pattern[patternIndex], text: path[pathIndex]) {
                result = match(patternIndex + 1, pathIndex + 1)
            } else {
                result = false
            }

            memo[patternIndex][pathIndex] = result
            return result
        }

        return match(0, 0)
    }

    /// 1セグメント内での `*` ワイルドカード比較（`*` は空文字列にも一致する）。
    private static func matchSegment(pattern: String, text: String) -> Bool {
        // 隣接する `*` を1つに畳んでおく。畳まないと `**` や `a**b` を `*` で分割したとき
        // 空文字列のパートができ、`String.range(of: "")` が `nil` を返すせいで
        // 常に不一致になってしまう（バラの `**` が何にも一致しなくなる、という形で顕在化する）。
        let parts = collapsingConsecutiveStars(pattern)
            .split(separator: "*", omittingEmptySubsequences: false)
            .map(String.init)

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

    /// 連続する `*` を1つに畳む。`**` は単体の `*` と同じ（＝すべてに一致する）ものとして
    /// 扱いたいが、畳まずに `*` で分割すると隣接する `*` の間に空文字列のパートができ、
    /// `String.range(of: "")` が `nil` を返すために不一致になってしまう。
    private static func collapsingConsecutiveStars(_ pattern: String) -> String {
        var result = ""
        var previousWasStar = false
        for character in pattern {
            let isStar = character == "*"
            if isStar && previousWasStar { continue }
            result.append(character)
            previousWasStar = isStar
        }
        return result
    }
}

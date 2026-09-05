import Foundation

/// 生成済みの HTML と CSS の中のアセット参照を、フィンガープリント済みの名前に差し替える。
///
/// この型は入力を**逐語的にコピー**し、マニフェストのキーに解決できた参照だけを差し替える。
/// HTML を構文木に読み込んで書き戻すことはしない。したがって走査が誤っても、起こり得るのは
/// 「書き換えそこねる」か「本来対象でない文字列を書き換える」だけで、無関係なバイトが壊れる
/// ことは構造上あり得ない。
public enum AssetReferenceRewriter {

    public struct CSSResult: Equatable {
        public let content: String
        /// マニフェストで解決できなかった `.css` への参照。パス2は全 CSS を同時に扱うため、
        /// CSS から CSS への `@import url(...)` はここで必ず未解決になる。呼び出し側が
        /// 警告を出すために報告する。
        public let unresolvedStylesheetReferences: [String]
    }

    /// CSS の `url(...)` を書き換える。
    public static func rewriteCSS(
        _ css: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> CSSResult {
        var result = ""
        var unresolved: [String] = []
        var index = css.startIndex

        while let token = css.range(of: "url(", options: [.caseInsensitive], range: index..<css.endIndex) {
            result += css[index..<token.upperBound]
            var cursor = token.upperBound

            while cursor < css.endIndex, css[cursor].isWhitespace {
                result.append(css[cursor])
                cursor = css.index(after: cursor)
            }
            guard cursor < css.endIndex else {
                index = cursor
                break
            }

            var quote: Character?
            if css[cursor] == "\"" || css[cursor] == "'" {
                quote = css[cursor]
                result.append(css[cursor])
                cursor = css.index(after: cursor)
            }

            let terminator = quote ?? ")"
            let valueStart = cursor
            while cursor < css.endIndex, css[cursor] != terminator {
                cursor = css.index(after: cursor)
            }
            guard cursor < css.endIndex else {
                // 閉じられていない `url(`。残りをそのまま出して終える。
                result += css[valueStart...]
                index = css.endIndex
                break
            }

            let rawValue = String(css[valueStart..<cursor])
            let reference = rawValue.trimmingCharacters(in: .whitespaces)
            if let rewritten = manifest.rewrite(reference: reference, inDirectory: directory) {
                result += rewritten
            } else {
                result += rawValue
                if isUnresolvedStylesheet(reference, manifest: manifest, inDirectory: directory) {
                    unresolved.append(reference)
                }
            }
            index = cursor
        }

        result += css[index...]
        return CSSResult(content: result, unresolvedStylesheetReferences: unresolved)
    }

    /// 書き換えられなかった参照が、ローカルの `.css` を指しているか。
    private static func isUnresolvedStylesheet(
        _ reference: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> Bool {
        let path = reference.split(separator: "?").first.map(String.init) ?? reference
        let withoutFragment = path.split(separator: "#").first.map(String.init) ?? path
        guard withoutFragment.lowercased().hasSuffix(".css") else { return false }
        guard !withoutFragment.hasPrefix("//"), !withoutFragment.contains(":") else { return false }
        return true
    }
}

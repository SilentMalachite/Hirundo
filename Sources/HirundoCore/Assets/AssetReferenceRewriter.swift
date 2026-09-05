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

    /// アセット参照を持つ HTML 属性。`style` だけは URL ではなく CSS として扱う。
    private static let urlAttributes: Set<String> = ["href", "src"]

    /// HTML の `href` / `src` / `srcset` 属性と、`style` 属性・`<style>` 本文の `url(...)` を
    /// 書き換える。
    ///
    /// `<script>` の本文と HTML コメントは走査しない。本文中の `a<b` をタグの開始と誤認する
    /// 余地を減らすためで、同時に JS の文字列リテラルを書き換えないことも保証する。
    public static func rewriteHTML(
        _ html: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> String {
        var result = ""
        var index = html.startIndex

        while index < html.endIndex {
            guard let open = html[index...].firstIndex(of: "<") else {
                result += html[index...]
                index = html.endIndex
                break
            }
            result += html[index..<open]
            index = open

            if html[index...].hasPrefix("<!--") {
                if let close = html.range(of: "-->", range: index..<html.endIndex) {
                    result += html[index..<close.upperBound]
                    index = close.upperBound
                } else {
                    result += html[index...]
                    index = html.endIndex
                }
                continue
            }

            let afterOpen = html.index(after: index)
            guard afterOpen < html.endIndex,
                  html[afterOpen].isLetter || html[afterOpen] == "/" || html[afterOpen] == "!",
                  let close = findTagEnd(in: html, from: index) else {
                result.append("<")
                index = afterOpen
                continue
            }

            let tag = String(html[index...close])
            result += rewriteTag(tag, manifest: manifest, inDirectory: directory)
            index = html.index(after: close)

            let name = tagName(of: tag)
            guard name == "script" || name == "style" else { continue }

            if let closing = html.range(of: "</\(name)", options: [.caseInsensitive], range: index..<html.endIndex) {
                let body = String(html[index..<closing.lowerBound])
                result += name == "style"
                    ? rewriteCSS(body, manifest: manifest, inDirectory: directory).content
                    : body
                index = closing.lowerBound
            } else {
                result += html[index...]
                index = html.endIndex
            }
        }

        return result
    }

    // MARK: - HTML の走査

    /// 引用符の中の `>` を無視してタグの終わりを探す。
    private static func findTagEnd(in html: String, from start: String.Index) -> String.Index? {
        var index = start
        var quote: Character?
        while index < html.endIndex {
            let character = html[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }
            index = html.index(after: index)
        }
        return nil
    }

    /// 開始タグの名前（小文字）。終了タグや `<!DOCTYPE` では空文字列。
    private static func tagName(of tag: String) -> String {
        var index = tag.index(after: tag.startIndex)
        let start = index
        while index < tag.endIndex, tag[index].isLetter || tag[index].isNumber {
            index = tag.index(after: index)
        }
        return tag[start..<index].lowercased()
    }

    /// `<` と `>` を含むタグ1つ分を受け取り、対象の属性値だけを差し替えて返す。
    private static func rewriteTag(
        _ tag: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> String {
        var result = ""
        var index = tag.startIndex

        // `<` とタグ名を写す。
        while index < tag.endIndex, !tag[index].isWhitespace {
            result.append(tag[index])
            index = tag.index(after: index)
        }

        while index < tag.endIndex {
            if tag[index].isWhitespace || tag[index] == ">" || tag[index] == "/" {
                result.append(tag[index])
                index = tag.index(after: index)
                continue
            }

            let nameStart = index
            while index < tag.endIndex, !tag[index].isWhitespace,
                  tag[index] != "=", tag[index] != ">", tag[index] != "/" {
                index = tag.index(after: index)
            }
            let name = tag[nameStart..<index].lowercased()
            result += tag[nameStart..<index]

            guard index < tag.endIndex, tag[index] == "=" else { continue }
            result.append("=")
            index = tag.index(after: index)

            var quote: Character?
            if index < tag.endIndex, tag[index] == "\"" || tag[index] == "'" {
                quote = tag[index]
                result.append(tag[index])
                index = tag.index(after: index)
            }

            let valueStart = index
            if let open = quote {
                while index < tag.endIndex, tag[index] != open {
                    index = tag.index(after: index)
                }
            } else {
                while index < tag.endIndex, !tag[index].isWhitespace, tag[index] != ">" {
                    index = tag.index(after: index)
                }
            }

            let value = String(tag[valueStart..<index])
            result += rewriteAttributeValue(value, named: name, manifest: manifest, inDirectory: directory)

            if let open = quote, index < tag.endIndex, tag[index] == open {
                result.append(open)
                index = tag.index(after: index)
            }
        }

        return result
    }

    private static func rewriteAttributeValue(
        _ value: String,
        named name: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> String {
        if urlAttributes.contains(name) {
            return manifest.rewrite(reference: value, inDirectory: directory) ?? value
        }
        if name == "srcset" {
            return rewriteSrcset(value, manifest: manifest, inDirectory: directory)
        }
        if name == "style" {
            return rewriteCSS(value, manifest: manifest, inDirectory: directory).content
        }
        return value
    }

    /// `srcset` はカンマ区切りの候補列。各候補の先頭の URL だけを書き換え、`1.5x` や `800w`
    /// といった記述子はそのまま残す。
    private static func rewriteSrcset(
        _ value: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> String {
        let candidates = value.split(separator: ",", omittingEmptySubsequences: false)
        return candidates.map { candidate -> String in
            let text = String(candidate)
            let leading = String(text.prefix(while: { $0.isWhitespace }))
            let rest = text.dropFirst(leading.count)
            let url = String(rest.prefix(while: { !$0.isWhitespace }))
            guard !url.isEmpty,
                  let rewritten = manifest.rewrite(reference: url, inDirectory: directory) else {
                return text
            }
            return leading + rewritten + rest.dropFirst(url.count)
        }.joined(separator: ",")
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
            let trailingWhitespace = String(rawValue.reversed().prefix { $0.isWhitespace }.reversed())
            let reference = String(rawValue.dropLast(trailingWhitespace.count))
            if let rewritten = manifest.rewrite(reference: reference, inDirectory: directory) {
                result += rewritten + trailingWhitespace
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

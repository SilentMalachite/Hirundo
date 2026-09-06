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
        /// マニフェストで解決できなかった `.css` への参照。行き先が存在しないか、参照先が
        /// 閉路にいて元の名前のまま出力されるかのどちらか。呼び出し側が警告を出すために報告する。
        public let unresolvedStylesheetReferences: [String]
    }

    /// アセット参照を持つ HTML 属性。`style` だけは URL ではなく CSS として扱う。
    private static let urlAttributes: Set<String> = ["href", "src"]

    /// 中身をタグとして走査しない要素。`style` だけは中身を CSS として書き換える。
    ///
    /// `script` の本文を走査しないのは、`a<b` をタグの開始と誤認する余地を減らすためと、
    /// JavaScript の文字列リテラルを書き換えないことを保証するため。`textarea` と `title` は
    /// 中身が地の文で、`<img src="...">` と書いてあってもそれは表示される文字列である。
    private static let rawTextElements: Set<String> = ["script", "style", "textarea", "title"]

    /// HTML の `href` / `src` / `srcset` 属性と、`style` 属性・`<style>` 本文の `url(...)` を
    /// 書き換える。
    ///
    /// `rawTextElements` の本文と HTML コメントは走査しない。本文中の `a<b` をタグの開始と
    /// 誤認する余地を減らすためで、同時に JS の文字列リテラルを書き換えないことも保証する。
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
            guard rawTextElements.contains(name) else { continue }

            if let closing = findClosingTag(named: name, in: html, from: index) {
                let body = String(html[index..<closing])
                result += name == "style"
                    ? rewriteCSS(body, manifest: manifest, inDirectory: directory).content
                    : body
                index = closing
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

    /// `</name` の開始位置。見つからなければ `nil`。
    ///
    /// タグ名の直後が空白・`/`・`>`（または文字列の終わり）であることを確かめる。これが無いと
    /// JavaScript の文字列にある `</scripture>` を `<script>` の終了タグと取り違え、そこから
    /// 先を HTML として走査してしまう。
    private static func findClosingTag(
        named name: String,
        in html: String,
        from start: String.Index
    ) -> String.Index? {
        var searchStart = start
        while let found = html.range(
            of: "</\(name)",
            options: [.caseInsensitive],
            range: searchStart..<html.endIndex
        ) {
            if found.upperBound == html.endIndex {
                return found.lowerBound
            }
            let next = html[found.upperBound]
            if next.isWhitespace || next == "/" || next == ">" {
                return found.lowerBound
            }
            searchStart = found.upperBound
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

            // 属性名と `=` の間の空白は合法。写しつつ読み飛ばす。`=` が続かなければ値の無い
            // 属性だったということで、写した空白はそのまま次の属性の前置きになる。
            index = copyWhitespace(of: tag, from: index, into: &result)

            guard index < tag.endIndex, tag[index] == "=" else { continue }
            result.append("=")
            index = tag.index(after: index)

            // `=` と値の間の空白も同じく合法。
            index = copyWhitespace(of: tag, from: index, into: &result)

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

    /// `from` から続く空白を逐語的に写し、その次の位置を返す。
    private static func copyWhitespace(
        of tag: String,
        from start: String.Index,
        into result: inout String
    ) -> String.Index {
        var index = start
        while index < tag.endIndex, tag[index].isWhitespace {
            result.append(tag[index])
            index = tag.index(after: index)
        }
        return index
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

    /// `srcset` の各候補の URL だけを書き換え、`1.5x` や `800w` といった記述子と、区切りの
    /// カンマ・空白はそのまま残す。
    ///
    /// 候補の切れ目は「空白のあとのカンマ」であって、URL トークンの中のカンマではない。
    /// 単純にカンマで分割すると `data:image/png,...` のような data URL を途中で断ち切る。
    private static func rewriteSrcset(
        _ value: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> String {
        var result = ""
        var index = value.startIndex

        while index < value.endIndex {
            // 候補の前の空白とカンマ。
            while index < value.endIndex, value[index].isWhitespace || value[index] == "," {
                result.append(value[index])
                index = value.index(after: index)
            }
            guard index < value.endIndex else { break }

            // URL は次の空白まで。途中のカンマは URL の一部。
            var urlEnd = index
            while urlEnd < value.endIndex, !value[urlEnd].isWhitespace {
                urlEnd = value.index(after: urlEnd)
            }

            // ただし末尾のカンマは URL ではなく候補の区切り。
            var urlStop = urlEnd
            var trailingCommas = 0
            while urlStop > index, value[value.index(before: urlStop)] == "," {
                urlStop = value.index(before: urlStop)
                trailingCommas += 1
            }

            let url = String(value[index..<urlStop])
            result += manifest.rewrite(reference: url, inDirectory: directory) ?? url
            result += String(repeating: ",", count: trailingCommas)
            index = urlEnd

            // 区切りのカンマで終わっていた候補に記述子は付かない。
            if trailingCommas > 0 { continue }

            // 記述子。丸括弧の外のカンマが次の候補の始まり。
            var depth = 0
            while index < value.endIndex {
                let character = value[index]
                if character == "," && depth == 0 { break }
                if character == "(" { depth += 1 }
                if character == ")" { depth = max(0, depth - 1) }
                result.append(character)
                index = value.index(after: index)
            }
        }

        return result
    }

    /// CSS の `url(...)` と `@import "..."` を書き換える。
    ///
    /// 文字列リテラルとコメントは走査から外す。`content: "url(/images/logo.png)"` の `url(` は
    /// URL トークンではなく表示される文字列なので、書き換えてはいけない。
    public static func rewriteCSS(
        _ css: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> CSSResult {
        var unresolved: [String] = []
        let content = scanCSS(css) { reference in
            if let rewritten = manifest.rewrite(reference: reference, inDirectory: directory) {
                return rewritten
            }
            if isUnresolvedStylesheet(reference) {
                unresolved.append(reference)
            }
            return nil
        }
        return CSSResult(content: content, unresolvedStylesheetReferences: unresolved)
    }

    /// CSS が参照しているアセットを、書き換えずに列挙する。
    ///
    /// スタイルシート同士の依存順を決めるために使う。参照はソースに書かれたままの文字列で、
    /// 解決も正規化もしていない。
    internal static func cssReferences(in css: String) -> [String] {
        var references: [String] = []
        _ = scanCSS(css) { reference in
            references.append(reference)
            return nil
        }
        return references
    }

    // MARK: - CSS の走査

    /// CSS を走査し、URL トークンごとに `transform` を呼ぶ。返り値がその参照の置き換え後の
    /// 文字列で、`nil` なら元のまま残す。トークン以外のバイトは逐語的にコピーされる。
    private static func scanCSS(_ css: String, transform: (String) -> String?) -> String {
        var result = ""
        var index = css.startIndex

        while index < css.endIndex {
            let character = css[index]

            if character == "/", matches("/*", in: css, at: index) {
                let bodyStart = css.index(index, offsetBy: 2)
                if let end = css.range(of: "*/", range: bodyStart..<css.endIndex) {
                    result += css[index..<end.upperBound]
                    index = end.upperBound
                } else {
                    result += css[index...]
                    index = css.endIndex
                }
                continue
            }

            if character == "\"" || character == "'" {
                let end = endOfString(in: css, openingAt: index)
                result += css[index..<end]
                index = end
                continue
            }

            if character == "u" || character == "U", matches("url(", in: css, at: index) {
                index = scanURLToken(in: css, at: index, into: &result, transform: transform)
                continue
            }

            // `@import url(...)` は次の周回の `url(` の枝が拾う。ここで扱うのは文字列形式だけ。
            if character == "@", matches("@import", in: css, at: index) {
                index = scanImportToken(in: css, at: index, into: &result, transform: transform)
                continue
            }

            result.append(character)
            index = css.index(after: index)
        }

        return result
    }

    /// `index` の位置に `prefix`（小文字で書くこと）が大文字小文字を無視して現れるか。
    private static func matches(_ prefix: String, in css: String, at index: String.Index) -> Bool {
        var cursor = index
        for expected in prefix {
            guard cursor < css.endIndex, String(css[cursor]).lowercased() == String(expected) else {
                return false
            }
            cursor = css.index(after: cursor)
        }
        return true
    }

    /// 開始引用符の位置から、閉じ引用符の**次**の位置を返す。閉じられていなければ末尾。
    private static func endOfString(in css: String, openingAt start: String.Index) -> String.Index {
        let quote = css[start]
        var index = css.index(after: start)
        while index < css.endIndex {
            if css[index] == "\\" {
                index = css.index(after: index)
                if index < css.endIndex { index = css.index(after: index) }
                continue
            }
            if css[index] == quote { return css.index(after: index) }
            index = css.index(after: index)
        }
        return css.endIndex
    }

    /// `url(` の位置から1トークン分を書き出し、次の走査位置を返す。
    private static func scanURLToken(
        in css: String,
        at start: String.Index,
        into result: inout String,
        transform: (String) -> String?
    ) -> String.Index {
        var cursor = css.index(start, offsetBy: 4)
        result += css[start..<cursor]

        while cursor < css.endIndex, css[cursor].isWhitespace {
            result.append(css[cursor])
            cursor = css.index(after: cursor)
        }
        guard cursor < css.endIndex else { return cursor }

        if css[cursor] == "\"" || css[cursor] == "'" {
            let quote = css[cursor]
            let valueStart = css.index(after: cursor)
            var end = valueStart
            while end < css.endIndex, css[end] != quote {
                end = css.index(after: end)
            }
            guard end < css.endIndex else {
                // 閉じられていない `url("`。残りをそのまま出して終える。
                result += css[cursor...]
                return css.endIndex
            }
            let reference = String(css[valueStart..<end])
            result.append(quote)
            result += transform(reference) ?? reference
            result.append(quote)
            return css.index(after: end)
        }

        let valueStart = cursor
        var end = cursor
        while end < css.endIndex, css[end] != ")" {
            end = css.index(after: end)
        }
        guard end < css.endIndex else {
            result += css[valueStart...]
            return css.endIndex
        }

        let rawValue = String(css[valueStart..<end])
        let trailingWhitespace = String(rawValue.reversed().prefix { $0.isWhitespace }.reversed())
        let reference = String(rawValue.dropLast(trailingWhitespace.count))
        if let rewritten = transform(reference) {
            result += rewritten + trailingWhitespace
        } else {
            result += rawValue
        }
        return end
    }

    /// `@import` の直後に来る文字列形式の URL を書き換え、次の走査位置を返す。
    private static func scanImportToken(
        in css: String,
        at start: String.Index,
        into result: inout String,
        transform: (String) -> String?
    ) -> String.Index {
        var cursor = css.index(start, offsetBy: 7)
        result += css[start..<cursor]

        while cursor < css.endIndex, css[cursor].isWhitespace {
            result.append(css[cursor])
            cursor = css.index(after: cursor)
        }
        guard cursor < css.endIndex, css[cursor] == "\"" || css[cursor] == "'" else { return cursor }

        let quote = css[cursor]
        let valueStart = css.index(after: cursor)
        var end = valueStart
        while end < css.endIndex, css[end] != quote {
            end = css.index(after: end)
        }
        guard end < css.endIndex else { return cursor }

        let reference = String(css[valueStart..<end])
        result.append(quote)
        result += transform(reference) ?? reference
        result.append(quote)
        return css.index(after: end)
    }

    /// 書き換えられなかった参照が、ローカルの `.css` を指しているか。
    private static func isUnresolvedStylesheet(_ reference: String) -> Bool {
        let path = reference.split(separator: "?").first.map(String.init) ?? reference
        let withoutFragment = path.split(separator: "#").first.map(String.init) ?? path
        guard withoutFragment.lowercased().hasSuffix(".css") else { return false }
        guard !withoutFragment.hasPrefix("//"), !withoutFragment.contains(":") else { return false }
        return true
    }
}

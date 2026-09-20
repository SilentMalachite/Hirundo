import Foundation

/// Turning a string into markup that means the string, wherever it lands.
///
/// Every generator in this module builds its HTML by interpolating values into a literal —
/// `HTMLRenderer` from a Markdown AST, `DefaultHTMLGenerator` and `ArchiveGenerator` from a
/// template context. The values come from a Markdown file's front matter or from `config.yaml`,
/// and neither is markup. Interpolated raw, a title of `<iframe src=…>` becomes an element, and
/// one containing a quote closes the attribute it was meant to sit in.
///
/// **This is the boundary.** `MarkdownValidator.validateDangerousPatterns` rejects a dozen
/// lowercased substrings before a file is parsed, and `HTMLSanitizer` strips a few constructs
/// after rendering. Both are defence in depth over a denylist, both are documented as such, and
/// neither is a boundary: `<iframe`, `onpointerover=` and `onerror =` walk past the first, and
/// values read from `config.yaml` never reach it at all. What keeps an author's string out of
/// the markup is that it went through here first.
///
/// There is one function rather than a text one and an attribute one because the two would have
/// been the same function. A value escaped for an attribute is already correct as element text,
/// and the reverse is what goes wrong: the weaker of a pair eventually gets used in the stronger
/// position, and nothing fails until a quote arrives. The caller says *what* to escape; there is
/// no choice left about *how*.
internal enum HTMLEscaping {
    /// The five characters that can change the meaning of surrounding markup, as entities.
    ///
    /// The result is safe both as element text and inside a double- or single-quoted attribute
    /// value. It is *not* safe in an unquoted attribute value (a space still ends it), inside a
    /// `<script>` or `<style>` body, or as a whole URL — for a URL, decide whether the scheme is
    /// allowed first and escape the result.
    ///
    /// `&` is replaced first. Replacing it later would find the ampersands of the entities the
    /// earlier passes just introduced and escape those too, so `"` would come out `&amp;quot;`.
    static func escaped(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Turns markup back into the text it means — the entities ``escaped(_:)`` introduces, plus
    /// the numeric references a Markdown renderer emits.
    ///
    /// For the two places that publish a page's words as data rather than as markup:
    /// `search-index.json`, whose consumer inserts a result with `textContent`, and the feed's
    /// `<description>`, which is escaped again for XML on the way out. Both were handing a reader
    /// `Tom &amp;amp; Jerry`.
    ///
    /// **This is not a general HTML entity decoder.** It knows `&amp;`, `&lt;`, `&gt;`,
    /// `&quot;`, `&#39;`, `&apos;` and numeric references. `&nbsp;`, `&copy;` and the rest of
    /// WHATWG's two-thousand-odd named references are left exactly as they are, as is a
    /// reference without its closing semicolon, which a browser would still expand. Anything
    /// that needs those needs a real parser, not this.
    ///
    /// `&amp;` is restored last, which is the mirror of `escaped(_:)` replacing `&` first: undo
    /// it earlier and `&amp;lt;` — an author writing a literal `&lt;` — would come back as `<`.
    static func unescaped(_ text: String) -> String {
        return decodingNumericReferences(text)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// `&#39;` and `&#x27;`. A reference naming no character — a surrogate, a value past the end
    /// of Unicode, or NUL — is left as written rather than guessed at.
    private static func decodingNumericReferences(_ text: String) -> String {
        guard text.contains("&#") else { return text }
        let pattern = try! NSRegularExpression(
            pattern: "&#(?:([0-9]{1,7})|[xX]([0-9A-Fa-f]{1,6}));"
        )
        let full = NSRange(text.startIndex..., in: text)
        var result = ""
        var cursor = text.startIndex
        for match in pattern.matches(in: text, range: full) {
            guard let matched = Range(match.range, in: text) else { continue }
            let digits = Range(match.range(at: 1), in: text).map { (String(text[$0]), 10) }
                ?? Range(match.range(at: 2), in: text).map { (String(text[$0]), 16) }
            guard let (number, radix) = digits,
                  let value = UInt32(number, radix: radix),
                  value != 0,
                  let scalar = Unicode.Scalar(value) else { continue }
            result += text[cursor..<matched.lowerBound]
            result.unicodeScalars.append(scalar)
            cursor = matched.upperBound
        }
        guard cursor != text.startIndex else { return text }
        result += text[cursor...]
        return result
    }
}

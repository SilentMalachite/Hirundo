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
}

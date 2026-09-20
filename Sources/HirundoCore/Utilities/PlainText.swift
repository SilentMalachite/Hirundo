import Foundation

/// Reducing a rendered page to the words a reader sees.
///
/// Two outputs publish a page's text as data rather than as markup — `search-index.json`, whose
/// consumer inserts a result with `textContent`, and the feed's `<description>`, which is
/// escaped again for XML on the way out. Both took the rendered HTML and cut it, so both shipped
/// tags and entities: a body reading `Tom & Jerry` was indexed as `Tom &amp;amp; Jerry`, which
/// displays wrong and matches no search for what the author wrote.
internal enum PlainText {
    /// The opening of a rendered page, as text.
    ///
    /// The order is the whole point. Tags come off first, because a cut inside one would leave a
    /// fragment. Entities are decoded next, because `&amp;` spends five characters of the budget
    /// on one character of text and a cut landing inside one leaves `&am` at the end. Only then
    /// is the result trimmed to length.
    static func excerpt(fromHTML html: String, maxCharacters: Int) -> String {
        return String(HTMLEscaping.unescaped(strippingTags(html)).prefix(maxCharacters))
    }

    /// Drops anything between angle brackets and squeezes the whitespace that is left.
    ///
    /// A regular expression, which is enough here and only here: the input is markup
    /// `HTMLRenderer` built, where every `<` that is not a tag has already been escaped.
    static func strippingTags(_ html: String) -> String {
        return html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

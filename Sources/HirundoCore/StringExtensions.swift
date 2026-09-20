import Foundation

extension String {
    /// Quotes `self` for a POSIX shell using single quotes.
    /// - Returns: A single-quoted string safe to paste after `cd`.
    public var posixShellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A name for a category, a tag or a file, derived from a title.
    ///
    /// The result is a **name, not a URL**. Non-ASCII survives as itself, and turning it into a
    /// URL component is `URLUtils.encodedComponent`'s job, done once at the point the name
    /// becomes part of a URL. This used to percent-encode here, which put a directory literally
    /// named `%E3%83%86%E3%82%B9%E3%83%88` on disk — and static hosting decodes a request path
    /// before it looks for a file, so every non-ASCII category and tag page 404ed once deployed.
    ///
    /// What it drops is what cannot survive the trip: path separators and `:`, NUL and the other
    /// control characters, the URL delimiters `#`, `?` and `%`, the five characters that can
    /// change the meaning of surrounding markup, and `*` and `|`, which Windows refuses in a file
    /// name. Everything else is kept, so a slug reads as the title did.
    ///
    /// A leading `.` goes too. It would make a hidden directory, which `FileManager`'s enumerator
    /// skips — so the page would be built and then left out of the sitemap — and it is how `.`
    /// and `..` would otherwise survive as names that move the write somewhere else.
    ///
    /// The result is normalized to NFC. macOS compares file names without regard to
    /// normalization, but Linux file systems compare bytes, so a name written as NFD would not be
    /// found by a URL that decodes to NFC.
    ///
    /// - Parameter maxLength: the budget for the result, in **UTF-8 bytes**, which is what a file
    ///   system's `NAME_MAX` counts. Truncation lands on a Character boundary, so it never splits
    ///   a multi-byte character. For an ASCII title this is the same as a count of characters.
    /// - Returns: a non-empty name — `"untitled"` when nothing survives.
    func slugify(maxLength: Int = 100) -> String {
        var slug = String.UnicodeScalarView()
        for scalar in lowercased().unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                slug.append("-")
            } else if Self.slugDropped.contains(scalar) {
                continue
            } else {
                slug.append(scalar)
            }
        }

        var name = String(slug)
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .precomposedStringWithCanonicalMapping

        if name.utf8.count > maxLength {
            var truncated = ""
            var used = 0
            for character in name {
                let size = String(character).utf8.count
                if used + size > maxLength { break }
                truncated.append(character)
                used += size
            }
            // Trim again: a cut inside a run of hyphens would otherwise leave one at the end.
            name = truncated.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        // `..` would make `ArchiveGenerator` ask for `_site/categories/../index.html`, which
        // `OutputPathGuard` refuses — a build failure from a category name that reads fine.
        while name.hasPrefix(".") {
            name.removeFirst()
        }

        // The fallback sits after truncation, not before it. It used to sit before, so the
        // truncating branch returned "" — which reached `ArchiveGenerator` as an empty directory
        // name and published a category at `/categories//`.
        return name.isEmpty ? "untitled" : name
    }

    /// Characters a slug cannot carry: path separators and `:`, control characters, the URL
    /// delimiters, the five that can change the meaning of markup, and the two more Windows
    /// refuses in a file name.
    private static let slugDropped: CharacterSet = {
        var dropped = CharacterSet(charactersIn: "/\\:#?%<>\"'&*|")
        dropped.formUnion(.controlCharacters)
        return dropped
    }()

    func padLeft(toLength: Int, withPad character: Character) -> String {
        let stringLength = self.count
        if stringLength < toLength {
            return String(repeating: character, count: toLength - stringLength) + self
        } else {
            return self
        }
    }
}

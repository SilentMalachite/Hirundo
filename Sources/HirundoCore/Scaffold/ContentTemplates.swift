import Foundation

/// The kind of content `ContentScaffolder` creates.
public enum ContentKind: Sendable {
    case post
    case page

    /// Template written into the `template:` key when the caller does not name one.
    ///
    /// These match what the build falls back to on its own (`PageRenderer`), but the
    /// generated file states them explicitly, the same way `hirundo init` does — so the
    /// user can see which template a file uses without knowing the fallback rules.
    public var defaultTemplate: String {
        switch self {
        case .post: return "post.html"
        case .page: return "default.html"
        }
    }
}

/// Builds the Markdown body of a newly created content file.
enum ContentTemplates {
    /// Formatter for the `date:` key.
    ///
    /// Matches `ScaffoldTemplates.helloWorldPost` so every file Hirundo generates spells
    /// dates the same way.
    private static func formattedDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func yamlArray(_ values: [String]) -> String {
        "[" + values.map { ScaffoldTemplates.yamlQuoted($0) }.joined(separator: ", ") + "]"
    }

    /// Renders a complete Markdown file, front matter included.
    ///
    /// Keys that carry no information are omitted rather than written with a default
    /// value: an absent `draft` means the same as `draft: false`, and an empty
    /// `categories: []` only adds noise to a file the user is about to edit.
    ///
    /// No `slug:` key is ever written. The output URL is derived from the file name
    /// while RSS links are derived from `Post.slug`, so a `slug:` that disagrees with
    /// the file name would make those two point at different URLs.
    static func markdown(
        kind: ContentKind,
        title: String,
        date: Date,
        categories: [String],
        tags: [String],
        draft: Bool,
        template: String
    ) -> String {
        var lines: [String] = ["---"]
        lines.append("title: \(ScaffoldTemplates.yamlQuoted(title))")
        if kind == .post {
            lines.append("date: \(formattedDate(date))")
        }
        if !categories.isEmpty {
            lines.append("categories: \(yamlArray(categories))")
        }
        if !tags.isEmpty {
            lines.append("tags: \(yamlArray(tags))")
        }
        if draft {
            lines.append("draft: true")
        }
        lines.append("template: \(ScaffoldTemplates.yamlQuoted(template))")
        lines.append("---")

        return lines.joined(separator: "\n") + "\n\n# \(title)\n\n"
    }
}

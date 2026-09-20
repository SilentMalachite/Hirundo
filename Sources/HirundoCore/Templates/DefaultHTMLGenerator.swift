import Foundation

/// The archive, category and tag pages Hirundo writes when the site has no template for them.
///
/// This is not a rarely-taken fallback. `hirundo init` scaffolds `base.html`, `default.html` and
/// `post.html` and nothing else (see `SiteScaffolder`), so `archive.html`, `category.html` and
/// `tag.html` are absent from every site until an author writes them — and `SiteTemplateRenderer`
/// reaches here whenever rendering one of those throws. For a site made with `hirundo init --blog`
/// this type *is* the archive, category and tag pages.
///
/// Every interpolated value therefore goes through `HTMLEscaping.escaped`. The values arrive in an
/// untyped `[String: Any]` on a `public` method, and the ones a site actually supplies are a post
/// title and a category or tag name from a Markdown file's front matter, plus `site.title` from
/// `config.yaml`, which is checked for length and nothing else. A `url` is escaped too: it is a
/// site-relative path this module built, not a URL an author wrote, so the question is whether it
/// can break out of the `href` it sits in, not whether its scheme is allowed. It is deliberately
/// *not* passed through `HTMLRenderer`'s `sanitizeURL`, which answers the second question and
/// returns `"#"` for anything `URLComponents` cannot parse — a project path containing a space
/// would turn every link on the page into a fragment.
public class DefaultHTMLGenerator {

    public init() {}

    /// Generates default archive HTML
    public func generateArchiveHTML(context: [String: Any]) -> String {
        guard let site = context["site"] as? [String: Any],
              let posts = context["posts"] as? [[String: Any]] else {
            return "<html><body><h1>Error: Invalid context</h1></body></html>"
        }
        let title = HTMLEscaping.escaped(site["title"] as? String ?? "Site")
        let language = HTMLEscaping.escaped(site["language"] as? String ?? "en")

        return """
        <!DOCTYPE html>
        <html lang="\(language)">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Archive - \(title)</title>
        </head>
        <body>
            <h1>Archive</h1>
            <ul>
        \(postListItems(posts))
            </ul>
        </body>
        </html>
        """
    }

    /// Generates default category HTML
    public func generateCategoryHTML(context: [String: Any]) -> String {
        guard let site = context["site"] as? [String: Any],
              let posts = context["posts"] as? [[String: Any]],
              let rawCategory = context["category"] as? String else {
            return "<html><body><h1>Error: Invalid context</h1></body></html>"
        }
        let title = HTMLEscaping.escaped(site["title"] as? String ?? "Site")
        let language = HTMLEscaping.escaped(site["language"] as? String ?? "en")
        let category = HTMLEscaping.escaped(rawCategory)

        return """
        <!DOCTYPE html>
        <html lang="\(language)">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Category: \(category) - \(title)</title>
        </head>
        <body>
            <h1>Category: \(category)</h1>
            <ul>
        \(postListItems(posts))
            </ul>
        </body>
        </html>
        """
    }

    /// Generates default tag HTML
    public func generateTagHTML(context: [String: Any]) -> String {
        guard let site = context["site"] as? [String: Any],
              let posts = context["posts"] as? [[String: Any]],
              let rawTag = context["tag"] as? String else {
            return "<html><body><h1>Error: Invalid context</h1></body></html>"
        }
        let title = HTMLEscaping.escaped(site["title"] as? String ?? "Site")
        let language = HTMLEscaping.escaped(site["language"] as? String ?? "en")
        let tag = HTMLEscaping.escaped(rawTag)

        return """
        <!DOCTYPE html>
        <html lang="\(language)">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Tag: \(tag) - \(title)</title>
        </head>
        <body>
            <h1>Tag: \(tag)</h1>
            <ul>
        \(postListItems(posts))
            </ul>
        </body>
        </html>
        """
    }

    /// The `<li>` list the three pages share, so the escaping is written once.
    private func postListItems(_ posts: [[String: Any]]) -> String {
        var list = ""
        for post in posts {
            let title = HTMLEscaping.escaped((post["title"] as? String) ?? "Untitled")
            let url = HTMLEscaping.escaped((post["url"] as? String) ?? "#")
            list += "<li><a href=\"\(url)\">\(title)</a></li>\n"
        }
        return list
    }
}

import Foundation

/// Generates default HTML for pages when templates are not available
public class DefaultHTMLGenerator {
    
    public init() {}
    
    /// Generates default archive HTML
    public func generateArchiveHTML(context: [String: Any]) -> String {
        guard let site = context["site"] as? [String: Any],
              let posts = context["posts"] as? [[String: Any]] else {
            return "<html><body><h1>Error: Invalid context</h1></body></html>"
        }
        let title = site["title"] as? String ?? "Site"
        let language = site["language"] as? String ?? "en"

        var list = ""
        for post in posts {
            let pTitle = (post["title"] as? String) ?? "Untitled"
            let pUrl = (post["url"] as? String) ?? "#"
            list += "<li><a href=\"\(pUrl)\">\(pTitle)</a></li>\n"
        }

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
        \(list)
            </ul>
        </body>
        </html>
        """
    }
    
    /// Generates default category HTML
    public func generateCategoryHTML(context: [String: Any]) -> String {
        guard let site = context["site"] as? [String: Any],
              let posts = context["posts"] as? [[String: Any]],
              let category = context["category"] as? String else {
            return "<html><body><h1>Error: Invalid context</h1></body></html>"
        }
        let title = site["title"] as? String ?? "Site"
        let language = site["language"] as? String ?? "en"

        var list = ""
        for post in posts {
            let pTitle = (post["title"] as? String) ?? "Untitled"
            let pUrl = (post["url"] as? String) ?? "#"
            list += "<li><a href=\"\(pUrl)\">\(pTitle)</a></li>\n"
        }

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
        \(list)
            </ul>
        </body>
        </html>
        """
    }
    
    /// Generates default tag HTML
    public func generateTagHTML(context: [String: Any]) -> String {
        guard let site = context["site"] as? [String: Any],
              let posts = context["posts"] as? [[String: Any]],
              let tag = context["tag"] as? String else {
            return "<html><body><h1>Error: Invalid context</h1></body></html>"
        }
        let title = site["title"] as? String ?? "Site"
        let language = site["language"] as? String ?? "en"

        var list = ""
        for post in posts {
            let pTitle = (post["title"] as? String) ?? "Untitled"
            let pUrl = (post["url"] as? String) ?? "#"
            list += "<li><a href=\"\(pUrl)\">\(pTitle)</a></li>\n"
        }

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
        \(list)
            </ul>
        </body>
        </html>
        """
    }
}
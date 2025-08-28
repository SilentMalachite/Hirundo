import Foundation

/// HTMLコンテンツのサニタイゼーションを行うクラス
public class HTMLSanitizer {
    
    /// HTMLをサニタイズ
    /// - Parameter html: サニタイズするHTML文字列
    /// - Returns: サニタイズされたHTML文字列
    public func sanitizeHTML(_ html: String) -> String {
        var sanitized = html
        
        // スクリプトタグとその内容を削除
        sanitized = removeScriptTags(sanitized)
        
        // スタイルタグとその内容を削除
        sanitized = removeStyleTags(sanitized)
        
        // メタタグを削除
        sanitized = removeMetaTags(sanitized)
        
        // 危険なHTML5要素を削除
        sanitized = removeDangerousElements(sanitized)
        
        // 残りのタグをクリーンアップ
        sanitized = cleanTags(sanitized)
        
        // hrefとsrc属性のURLをサニタイズ
        sanitized = sanitizeURLs(sanitized)
        
        // 残りのイベントハンドラーを削除
        sanitized = removeEventHandlers(sanitized)
        
        // テキストコンテンツの危険な文字をエスケープ
        sanitized = escapeTextContent(sanitized)
        
        return sanitized
    }
    
    /// スクリプトタグを削除
    private func removeScriptTags(_ html: String) -> String {
        let scriptPattern = #"<script[^>]*>[\s\S]*?</script>"#
        return html.replacingOccurrences(
            of: scriptPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
    
    /// スタイルタグを削除
    private func removeStyleTags(_ html: String) -> String {
        let stylePattern = #"<style[^>]*>[\s\S]*?</style>"#
        return html.replacingOccurrences(
            of: stylePattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
    
    /// メタタグを削除
    private func removeMetaTags(_ html: String) -> String {
        let metaPattern = #"<meta[^>]*/?>"#
        return html.replacingOccurrences(
            of: metaPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
    
    /// 危険な要素を削除
    private func removeDangerousElements(_ html: String) -> String {
        let dangerousTags = ["iframe", "embed", "object", "link", "svg", "math", "form", "input", "button", "select", "textarea"]
        var result = html
        
        for tag in dangerousTags {
            // 開始タグと終了タグを削除
            let openPattern = #"<\#(tag)(?:\s[^>]*)?"#
            let closePattern = #"</\#(tag)>"#
            
            result = result.replacingOccurrences(
                of: openPattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            result = result.replacingOccurrences(
                of: closePattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        
        return result
    }
    
    /// タグをクリーンアップ
    private func cleanTags(_ html: String) -> String {
        let tagPattern = #"<(/?)(\w+)([^>]*)>"#
        
        guard let regex = try? NSRegularExpression(pattern: tagPattern, options: .caseInsensitive) else {
            return html
        }
        
        let nsString = html as NSString
        var result = html
        var offset = 0
        
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            let fullRange = NSRange(location: match.range.location + offset, length: match.range.length)
            let fullMatch = nsString.substring(with: fullRange)
            
            let isClosing = match.range(at: 1).location != NSNotFound
            let tagName = nsString.substring(with: match.range(at: 2))
            let attributes = match.range(at: 3).location != NSNotFound ? nsString.substring(with: match.range(at: 3)) : ""
            
            // 許可されたタグのみを保持
            let allowedTags = ["p", "br", "strong", "em", "u", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "code", "pre", "a", "img", "table", "thead", "tbody", "tr", "th", "td"]
            
            if allowedTags.contains(tagName.lowercased()) {
                let cleanedAttributes = cleanAttributes(tagName: tagName, attributes: attributes)
                let replacement = "<\(isClosing ? "/" : "")\(tagName)\(cleanedAttributes)>"
                result = result.replacingOccurrences(of: fullMatch, with: replacement)
            } else {
                // 許可されていないタグは削除
                result = result.replacingOccurrences(of: fullMatch, with: "")
                offset -= fullMatch.count
            }
        }
        
        return result
    }
    
    /// 属性をクリーンアップ
    private func cleanAttributes(tagName: String, attributes: String) -> String {
        let allowedAttributes: [String: [String]] = [
            "a": ["href", "title"],
            "img": ["src", "alt", "title", "width", "height"],
            "table": ["border", "cellpadding", "cellspacing"],
            "th": ["colspan", "rowspan"],
            "td": ["colspan", "rowspan"]
        ]
        
        guard let allowedForTag = allowedAttributes[tagName.lowercased()] else {
            return ""
        }
        
        let attributePattern = #"(\w+)\s*=\s*["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: attributePattern, options: .caseInsensitive) else {
            return ""
        }
        
        let matches = regex.matches(in: attributes, options: [], range: NSRange(location: 0, length: attributes.count))
        var cleanedAttributes: [String] = []
        
        for match in matches {
            let attributeName = (attributes as NSString).substring(with: match.range(at: 1))
            let attributeValue = (attributes as NSString).substring(with: match.range(at: 2))
            
            if allowedForTag.contains(attributeName.lowercased()) {
                let sanitizedValue = sanitizeAttributeValue(attributeName: attributeName, value: attributeValue)
                cleanedAttributes.append("\(attributeName)=\"\(sanitizedValue)\"")
            }
        }
        
        return cleanedAttributes.isEmpty ? "" : " " + cleanedAttributes.joined(separator: " ")
    }
    
    /// 属性値をサニタイズ
    private func sanitizeAttributeValue(attributeName: String, value: String) -> String {
        switch attributeName.lowercased() {
        case "href", "src":
            return sanitizeURL(value)
        default:
            return escapeAttribute(value)
        }
    }
    
    /// URLをサニタイズ
    private func sanitizeURL(_ url: String) -> String {
        // 基本的なURL検証
        guard let urlComponents = URLComponents(string: url) else {
            return "#"
        }
        
        // 許可されたスキームのみ
        let allowedSchemes = ["http", "https", "mailto", "tel"]
        if let scheme = urlComponents.scheme?.lowercased() {
            guard allowedSchemes.contains(scheme) else {
                return "#"
            }
        }
        
        // 危険なパターンをチェック
        let lowercasedURL = url.lowercased()
        let dangerousPatterns = ["javascript:", "vbscript:", "data:", "file:"]
        for pattern in dangerousPatterns {
            if lowercasedURL.hasPrefix(pattern) {
                return "#"
            }
        }
        
        return url
    }
    
    /// URLをサニタイズ（HTML内のURL）
    private func sanitizeURLs(_ html: String) -> String {
        let urlPattern = #"(href|src)\s*=\s*["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) else {
            return html
        }
        
        return regex.stringByReplacingMatches(in: html, options: [], range: NSRange(location: 0, length: html.count)) { match, _, _ in
            let attributeName = (html as NSString).substring(with: match.range(at: 1))
            let url = (html as NSString).substring(with: match.range(at: 2))
            let sanitizedURL = sanitizeURL(url)
            return "\(attributeName)=\"\(sanitizedURL)\""
        }
    }
    
    /// イベントハンドラーを削除
    private func removeEventHandlers(_ html: String) -> String {
        let eventHandlerPattern = #"\s+on\w+\s*=\s*["'][^"']*["']"#
        return html.replacingOccurrences(
            of: eventHandlerPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
    
    /// テキストコンテンツをエスケープ
    private func escapeTextContent(_ html: String) -> String {
        // HTMLエンティティをデコードしてから再エスケープ
        let decoded = decodeHTMLEntities(html)
        return decoded
    }
    
    /// HTMLエンティティをデコード
    private func decodeHTMLEntities(_ string: String) -> String {
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " "
        ]
        
        var result = string
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
    
    /// 属性値をエスケープ
    private func escapeAttribute(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
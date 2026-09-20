import Foundation

/// A defence-in-depth pass over HTML that ``HTMLRenderer`` has already built.
///
/// **This is not a general-purpose HTML sanitizer, and must not be used as one.** It is a set of
/// regular expressions over markup produced by ``HTMLRenderer``, which assembles every tag itself
/// from the Markdown tree and has no case for `HTMLBlock` or `InlineHTML` — both are leaves, so
/// raw HTML in a Markdown source renders to nothing. That, not anything here, is why an author
/// cannot inject a tag. What this pass adds is a second look at the handful of shapes the
/// renderer could in principle emit: a stray `<script>`, `<style>` or `<meta>`, a URL in an
/// `href`/`src` that is not http(s)/mailto/tel, and an event-handler attribute.
///
/// Fed arbitrary untrusted HTML it would let plenty through — `<iframe>`, `<object>`, `<form>`
/// and anything using an unquoted attribute value all survive. A whitelist of tags and attributes
/// used to be declared in this file; `sanitizeHTML` never called it, and wiring it up would have
/// meant a second, worse HTML parser rather than any real gain, so it is gone.
public final class HTMLSanitizer: Sendable {
    
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
        
        // hrefとsrc属性のURLをサニタイズ（HTMLRendererで生成される安全な属性を補助的に検証）
        sanitized = sanitizeURLs(sanitized)
        
        // 残りのイベントハンドラーを削除
        sanitized = removeEventHandlers(sanitized)

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
        
        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))

        // Everything here stays in UTF-16, because that is the unit `NSRegularExpression`
        // reports in. Converting a match's location with `String.index(_:offsetBy:)` counts
        // Characters instead, and the two diverge the moment the page holds anything outside
        // the BMP: one emoji is a single Character and two UTF-16 units, so a link after twenty
        // of them was sliced twenty units early, or past the end — `String index is out of
        // bounds`, on a page whose only sin was an emoji before a link.
        let result = NSMutableString(string: html)
        // Replace from end to start so the earlier matches' ranges stay valid.
        for match in matches.reversed() {
            let name = ns.substring(with: match.range(at: 1))
            let url = ns.substring(with: match.range(at: 2))
            result.replaceCharacters(in: match.range, with: "\(name)=\"\(sanitizeURL(url))\"")
        }

        return result as String
    }
    
    /// イベントハンドラーを削除
    ///
    /// `on` の手前は空白とは限らない。属性値のエスケープ漏れがあると `"` が直前に来るため、
    /// 引用符も区切りとして受ける（本筋の修正は `HTMLRenderer` 側のエスケープ）。
    private func removeEventHandlers(_ html: String) -> String {
        let eventHandlerPattern = #"[\s"']+on\w+\s*=\s*["'][^"']*["']"#
        return html.replacingOccurrences(
            of: eventHandlerPattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}

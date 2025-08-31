import Foundation
import Stencil
import Markdown

/// Manages template filters for Stencil
public class TemplateFilters {
    
    public init() {}
    
    /// Registers static filters that don't depend on site configuration
    public static func registerStaticFilters(to ext: inout Extension) {
        // Date formatting filter
        ext.registerFilter("date") { (value: Any?, arguments: [Any?]) in
            guard let date = value as? Date else { return value }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX") // Set locale for consistent formatting

            if var formatString = arguments.first as? String {
                // Basic translation from strftime to DateFormatter format
                let translations = [
                    "%Y": "yyyy", "%y": "yy",
                    "%m": "MM", "%B": "MMMM", "%b": "MMM",
                    "%d": "dd",
                    "%A": "EEEE", "%a": "EEE",
                    "%H": "HH", "%I": "hh", "%p": "a",
                    "%M": "mm",
                    "%S": "ss",
                    "%Z": "zzz"
                ]
                for (strftime, icu) in translations {
                    formatString = formatString.replacingOccurrences(of: strftime, with: icu)
                }
                formatter.dateFormat = formatString
            } else {
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
            }
            
            return formatter.string(from: date)
        }
        
        // Slugify filter
        ext.registerFilter("slugify") { (value: Any?) in
            guard let string = value as? String else { return value }
            return string.slugify()
        }
        
        // Excerpt filter (character-based for language-agnostic behavior)
        ext.registerFilter("excerpt") { (value: Any?, arguments: [Any?]) in
            guard let string = value as? String else { return value }
            let maxLength = arguments.first as? Int ?? 100
            if string.count <= maxLength {
                return string
            }
            let endIndex = string.index(string.startIndex, offsetBy: maxLength)
            return String(string[..<endIndex]) + "..."
        }
        
        // Markdown filter
        ext.registerFilter("markdown") { (value: Any?) in
            guard let string = value as? String else { return value }
            // Use the standard library parser for correct and safe HTML rendering.
            let document = Document(parsing: string)
            return document.htmlString
        }
        
        // Array join filter
        ext.registerFilter("join") { (value: Any?, arguments: [Any?]) in
            guard let array = value as? [Any] else { return value }
            let separator = arguments.first as? String ?? ", "
            return array.map { "\($0)" }.joined(separator: separator)
        }
        
        // Array length filter
        ext.registerFilter("length") { (value: Any?) in
            if let array = value as? [Any] {
                return array.count
            } else if let string = value as? String {
                return string.count
            }
            return 0
        }
        
        // Array first filter
        ext.registerFilter("first") { (value: Any?) in
            guard let array = value as? [Any], !array.isEmpty else { return nil }
            return array.first
        }
        
        // Array last filter
        ext.registerFilter("last") { (value: Any?) in
            guard let array = value as? [Any], !array.isEmpty else { return nil }
            return array.last
        }
        
        // Array slice filter
        ext.registerFilter("slice") { (value: Any?, arguments: [Any?]) in
            guard let array = value as? [Any] else { return value }
            let start = arguments.first as? Int ?? 0
            let end = arguments.count > 1 ? arguments[1] as? Int : nil
            
            if let end = end {
                return Array(array[start..<min(end, array.count)])
            } else {
                return Array(array[start...])
            }
        }
        
        // String truncate filter
        ext.registerFilter("truncate") { (value: Any?, arguments: [Any?]) in
            guard let string = value as? String else { return value }
            let length = arguments.first as? Int ?? 50
            let suffix = arguments.count > 1 ? (arguments[1] as? String) ?? "..." : "..."
            
            if string.count <= length {
                return string
            }
            return String(string.prefix(length)) + suffix
        }
        
        // String strip filter
        ext.registerFilter("strip") { (value: Any?) in
            guard let string = value as? String else { return value }
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // String replace filter
        ext.registerFilter("replace") { (value: Any?, arguments: [Any?]) in
            guard let string = value as? String,
                  let search = arguments.first as? String else { return value }
            let replacement = arguments.count > 1 ? (arguments[1] as? String) ?? "" : ""
            return string.replacingOccurrences(of: search, with: replacement)
        }
        
        // String split filter
        ext.registerFilter("split") { (value: Any?, arguments: [Any?]) in
            guard let string = value as? String else { return value }
            let separator = arguments.first as? String ?? " "
            return string.components(separatedBy: separator)
        }
        
        // Number format filter
        ext.registerFilter("number") { (value: Any?) in
            guard let number = value as? NSNumber else { return value }
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter.string(from: number) ?? "\(number)"
        }
        
        // Default value filter
        ext.registerFilter("default") { (value: Any?, arguments: [Any?]) in
            if value == nil || (value is String && (value as? String)?.isEmpty == true) {
                return arguments.first ?? nil
            }
            return value
        }
    }
    
    /// Registers dynamic filters that depend on site configuration
    public static func registerDynamicFilters(to ext: inout Extension, siteConfig: Site) {
        // Absolute URL filter
        ext.registerFilter("absolute_url") { (value: Any?) in
            guard let path = value as? String else { return value }
            if path.hasPrefix("http") {
                return path
            }
            let baseURL = siteConfig.url.hasSuffix("/") ? siteConfig.url : siteConfig.url + "/"
            let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
            return baseURL + cleanPath
        }
        
        // Relative URL filter
        ext.registerFilter("relative_url") { (value: Any?) in
            guard let path = value as? String else { return value }
            if path.hasPrefix("http") {
                return path
            }
            return path.hasPrefix("/") ? path : "/" + path
        }
        
        // Site URL filter
        ext.registerFilter("site_url") { (value: Any?) in
            return siteConfig.url
        }
        
        // Site title filter
        ext.registerFilter("site_title") { (value: Any?) in
            return siteConfig.title
        }
        
        // Site description filter
        ext.registerFilter("site_description") { (value: Any?) in
            return siteConfig.description ?? ""
        }
    }
}

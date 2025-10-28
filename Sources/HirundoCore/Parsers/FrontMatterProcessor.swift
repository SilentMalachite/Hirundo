import Foundation
import Yams

/// フロントマターの処理を行うクラス
public final class FrontMatterProcessor: Sendable {
    private let limits: Limits
    
    public init(limits: Limits = Limits()) {
        self.limits = limits
    }
    
    /// コンテンツからフロントマターを抽出
    /// - Parameter content: マークダウンコンテンツ
    /// - Returns: フロントマター（辞書形式）と残りのマークダウンコンテンツ
    public func extractFrontMatter(from content: String) throws -> (frontMatter: [String: Any]?, markdownContent: String, excerpt: String?) {
        var markdownContent = content
        var frontMatter: [String: Any]?
        var excerpt: String?
        
        // フロントマターが存在するかチェック
        if content.hasPrefix("---\n") {
            // 終了デリミタを探す
            let patterns = ["\n---\n", "\n---$"]
            var endRange: Range<String.Index>? = nil
            var endPatternLength = 0
            
            for pattern in patterns {
                if pattern.hasSuffix("$") {
                    // 文字列終端パターンの処理
                    let actualPattern = String(pattern.dropLast())
                    if content.hasSuffix(actualPattern) {
                        endRange = content.range(of: actualPattern, options: .backwards)
                        endPatternLength = actualPattern.count
                        break
                    }
                } else {
                    if let range = content.range(of: pattern) {
                        endRange = range
                        endPatternLength = pattern.count
                        break
                    }
                }
            }
            
            if let endRange = endRange {
                let yamlString = String(content[content.index(content.startIndex, offsetBy: 4)..<endRange.lowerBound])
                let remainderStartIndex = content.index(endRange.lowerBound, offsetBy: endPatternLength)
                markdownContent = remainderStartIndex < content.endIndex ? String(content[remainderStartIndex...]) : ""
                
                // YAMLフロントマターサイズの検証
                guard yamlString.count <= limits.maxFrontMatterSize else {
                    let maxSizeKB = limits.maxFrontMatterSize / 1_000
                    throw MarkdownError.frontMatterTooLarge("Front matter exceeds \(maxSizeKB)KB limit")
                }
                
                do {
                    frontMatter = try Yams.load(yaml: yamlString) as? [String: Any]
                    
                    // フロントマターコンテンツの検証
                    if let fm = frontMatter {
                        try validateFrontMatter(fm)
                        
                        // フロントマターから抜粋を抽出
                        if let excerptValue = fm["excerpt"] as? String {
                            excerpt = excerptValue
                        }
                    }
                } catch let error as MarkdownError {
                    throw error
                } catch {
                    throw MarkdownError.invalidFrontMatter(error.localizedDescription)
                }
            }
        }
        
        return (frontMatter, markdownContent, excerpt)
    }
    
    /// フロントマターの内容を検証
    /// - Parameter frontMatter: 検証するフロントマター
    private func validateFrontMatter(_ frontMatter: [String: Any]) throws {
        func validateValue(_ value: Any, depth: Int = 0) throws {
            // 再帰の深さ制限（DoS攻撃防止）
            guard depth < 10 else {
                throw MarkdownError.invalidFrontMatter("Front matter nesting too deep")
            }
            
            switch value {
            case let string as String:
                // 文字列長の検証
                guard string.count <= 10000 else {
                    throw MarkdownError.invalidFrontMatter("String value too long in front matter")
                }
            case let array as [Any]:
                // 配列サイズの検証
                guard array.count <= 1000 else {
                    throw MarkdownError.invalidFrontMatter("Array too large in front matter")
                }
                // 配列の各要素を再帰的に検証
                for item in array {
                    try validateValue(item, depth: depth + 1)
                }
            case let dictionary as [String: Any]:
                // 辞書サイズの検証
                guard dictionary.count <= 100 else {
                    throw MarkdownError.invalidFrontMatter("Dictionary too large in front matter")
                }
                // 辞書の各値を再帰的に検証
                for (key, value) in dictionary {
                    // キーの長さ検証
                    guard key.count <= 100 else {
                        throw MarkdownError.invalidFrontMatter("Key too long in front matter: \(key)")
                    }
                    try validateValue(value, depth: depth + 1)
                }
            case is Int, is Double, is Bool:
                // 数値とブール値は安全
                break
            case is Date:
                // 日付型も安全
                break
            case is NSNull:
                // null値も安全
                break
            default:
                throw MarkdownError.invalidFrontMatter("Unsupported type in front matter: \(type(of: value))")
            }
        }
        
        try validateValue(frontMatter)
    }
}
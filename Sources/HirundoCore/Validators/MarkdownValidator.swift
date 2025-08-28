import Foundation

/// マークダウンコンテンツのセキュリティ検証を行うクラス
public class MarkdownValidator {
    private let limits: Limits
    private let skipContentValidation: Bool
    
    public init(limits: Limits = Limits(), skipContentValidation: Bool = false) {
        self.limits = limits
        self.skipContentValidation = skipContentValidation
    }
    
    /// マークダウンコンテンツを検証
    /// - Parameter content: 検証するマークダウンコンテンツ
    /// - Throws: MarkdownError 検証に失敗した場合
    public func validateMarkdownContent(_ content: String) throws {
        // 過度なネスト構造のチェック（DoS攻撃防止）
        try validateNestingLevel(content)
        
        // 危険なHTMLパターンのチェック
        if !skipContentValidation {
            try validateDangerousPatterns(content)
        }
        
        // 過度な文字の繰り返しチェック（DoS攻撃防止）
        try validateExcessiveRepetition(content)
    }
    
    /// ネストレベルの検証
    private func validateNestingLevel(_ content: String) throws {
        let maxNestingLevel = 20
        var currentNestingLevel = 0
        var maxObservedNesting = 0
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // マークダウンのネストインジケーターをカウント
            if trimmed.hasPrefix("#") {
                let headingLevel = trimmed.prefix(while: { $0 == "#" }).count
                currentNestingLevel = headingLevel
            } else if trimmed.hasPrefix(">") {
                let blockquoteLevel = trimmed.prefix(while: { $0 == ">" }).count
                currentNestingLevel = blockquoteLevel
            } else if trimmed.hasPrefix("  ") || trimmed.hasPrefix("\t") {
                // インデントされたコンテンツ
                let indentLevel = trimmed.prefix(while: { $0 == " " || $0 == "\t" }).count
                currentNestingLevel = indentLevel / 2 // 概算のネストレベル
            } else {
                currentNestingLevel = 0
            }
            
            maxObservedNesting = max(maxObservedNesting, currentNestingLevel)
            
            if maxObservedNesting > maxNestingLevel {
                throw MarkdownError.excessiveNesting("Markdown nesting exceeds maximum allowed level of \(maxNestingLevel)")
            }
        }
    }
    
    /// 危険なパターンの検証
    private func validateDangerousPatterns(_ content: String) throws {
        let dangerousPatterns = [
            "<script", "</script>", "javascript:", "vbscript:", "onload=", "onerror=",
            "onclick=", "onmouseover=", "onfocus=", "onblur=", "onchange=", "onsubmit="
        ]
        
        let lowerContent = content.lowercased()
        for pattern in dangerousPatterns {
            if lowerContent.contains(pattern) {
                throw MarkdownError.dangerousContent("Potentially dangerous HTML pattern detected: \(pattern)")
            }
        }
    }
    
    /// 過度な文字の繰り返しの検証
    private func validateExcessiveRepetition(_ content: String) throws {
        let maxRepeatedChars = 1000
        for char in ["-", "=", "*", "#", "`", "~"] {
            let pattern = String(repeating: char, count: maxRepeatedChars + 1)
            if content.contains(pattern) {
                throw MarkdownError.excessiveRepetition("Excessive repeated character '\(char)' detected")
            }
        }
    }
}
import Foundation

/// Markdown ファイルを読んだ直後に走る検査。
///
/// 中身は3つ。過度なネスト、危険パターンの denylist、同一文字の過剰な繰り返し。1つめと3つめは
/// パーサを守るための上限で、2つめは**セキュリティ境界ではない**（`validateDangerousPatterns`
/// の doc を参照）。
///
/// 検査を通らない経路が2つある。`MarkdownParser.parseFile(at:extractOnly: true)` は `parse` を
/// 通らずフロントマターだけを取り出す。`StreamingMarkdownParser.parseFile` はこの型を使わない。
/// 現在のビルド経路は `ContentProcessor` 経由なのでどちらも通らないが、境界をここに置けない
/// 理由のひとつではある。
public final class MarkdownValidator: Sendable {
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
    
    /// 危険なパターンの検証。**これは境界ではない。**
    ///
    /// 小文字化した本文に対して12個の部分文字列を `contains` するだけの denylist で、素通りする
    /// ものを数え上げることはできない。確実に通るものだけでも `<iframe`、`<object`、`<embed`、
    /// `onpointerover=`、`ontoggle=`、`onwheel=`、`=` の前に空白を置いた `onerror =` がある。
    /// HTML の属性名は仕様が増えるたびに増えるので、リストを伸ばしても追いつかない。伸ばすほど
    /// 誤検知も増える——`onclick=` という**文字列**が出てくるだけの記事（XSS の解説記事など）が
    /// ビルドを落とす。
    ///
    /// 見てすらいない入力もある。`config.yaml` の `site.title` / `site.author.name` はここを
    /// 一度も通らず（この型は Markdown しか見ない）、ファイル名も通らない。macOS のファイル名に
    /// は `"` が使えるので、`content/a"onmouseover="alert(1).md` という名前は、この検査を素通り
    /// したうえで属性値に届く。
    ///
    /// **境界は出力側にある。** `HTMLRenderer` が `HTMLBlock` / `InlineHTML` に case を持たず
    /// タグを自分で組み立てること、`HTMLEscaping.escaped` がノード由来の文字列をすべて通ること、
    /// テンプレートの `escape` フィルタ。この検査はビルドを早めに落とす tripwire であって、その
    /// 代わりではない。f67aa05 が `HTMLSanitizer` に対して書いたのと同じ関係。
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
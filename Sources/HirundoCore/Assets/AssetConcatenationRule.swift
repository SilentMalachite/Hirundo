import Foundation

/// アセット連結ルール
public struct AssetConcatenationRule {
    public let pattern: String
    public let output: String
    public let separator: String
    
    public init(pattern: String, output: String, separator: String = "\n") {
        self.pattern = pattern
        self.output = output
        self.separator = separator
    }
}
import Foundation

/// CSS処理オプション
public struct CSSProcessingOptions {
    public var minify: Bool = false
    public var autoprefixer: Bool = false

    public init(minify: Bool = false, autoprefixer: Bool = false) {
        self.minify = minify
        self.autoprefixer = autoprefixer
    }
}

/// JavaScript処理オプション
///
/// トランスパイルは提供しない。正規表現でのトランスパイルは壊れやすく、
/// 必要なら Babel や esbuild を使う。
public struct JSProcessingOptions {
    public var minify: Bool = false

    public init(minify: Bool = false) {
        self.minify = minify
    }
}

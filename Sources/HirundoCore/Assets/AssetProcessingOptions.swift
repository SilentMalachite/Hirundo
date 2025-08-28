import Foundation

/// CSS処理オプション
public struct CSSProcessingOptions {
    public var minify: Bool = false
    public var autoprefixer: Bool = false
    public var sourceMap: Bool = false
    
    public init(minify: Bool = false, autoprefixer: Bool = false, sourceMap: Bool = false) {
        self.minify = minify
        self.autoprefixer = autoprefixer
        self.sourceMap = sourceMap
    }
}

/// JavaScript処理オプション
public struct JSProcessingOptions {
    public var minify: Bool = false
    public var transpile: Bool = false
    public var sourceMap: Bool = false
    public var target: String = "es2020"
    
    public init(minify: Bool = false, transpile: Bool = false, sourceMap: Bool = false, target: String = "es2020") {
        self.minify = minify
        self.transpile = transpile
        self.sourceMap = sourceMap
        self.target = target
    }
}
import Foundation
import CryptoKit

/// 静的アセットの処理を行うアセットパイプライン
public class AssetPipeline {
    private let pluginManager: PluginManager
    private let fileManager = FileManager.default
    
    // 設定
    public var enableFingerprinting: Bool = false
    public var enableSourceMaps: Bool = false
    public var excludePatterns: [String] = []
    public var concatenationRules: [AssetConcatenationRule] = []
    public var cssOptions: CSSProcessingOptions = CSSProcessingOptions()
    public var jsOptions: JSProcessingOptions = JSProcessingOptions()
    
    public init(pluginManager: PluginManager) {
        self.pluginManager = pluginManager
    }
    
    /// ソースからデスティネーションにすべてのアセットを処理
    /// - Parameters:
    ///   - sourcePath: ソースパス
    ///   - destinationPath: デスティネーションパス
    /// - Returns: マニフェスト（ファイル名のマッピング）
    /// - Throws: AssetPipelineError 処理に失敗した場合
    public func processAssets(from sourcePath: String, to destinationPath: String) throws -> [String: String] {
        var manifest: [String: String] = [:]
        
        // デスティネーションディレクトリを作成
        try fileManager.createDirectory(
            atPath: destinationPath,
            withIntermediateDirectories: true
        )
        
        // まず、連結ルールを処理
        if !concatenationRules.isEmpty {
            try processConcatenationRules(
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                manifest: &manifest
            )
        }
        
        // 個別のアセットを処理
        let sourceURL = URL(fileURLWithPath: sourcePath)
        try processDirectory(
            sourceURL,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            manifest: &manifest
        )
        
        return manifest
    }
    
    /// ファイル名からアセットタイプを検出
    /// - Parameter filename: ファイル名
    /// - Returns: アセットタイプ
    public func detectAssetType(for filename: String) -> AssetItem.AssetType {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        
        switch ext {
        case "css":
            return .css
        case "js":
            return .javascript
        case "png", "jpg", "jpeg", "gif", "svg", "webp":
            return .image
        case "woff", "woff2", "ttf", "otf", "eot":
            return .font
        default:
            return .other
        }
    }
    
    /// マニフェストを保存
    /// - Parameters:
    ///   - manifest: マニフェスト
    ///   - path: 保存先パス
    /// - Throws: AssetPipelineError 保存に失敗した場合
    public func saveManifest(_ manifest: [String: String], to path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: path))
    }
    
    /// マニフェストを読み込み
    /// - Parameter path: マニフェストファイルのパス
    /// - Returns: マニフェスト
    /// - Throws: AssetPipelineError 読み込みに失敗した場合
    public func loadManifest(from path: String) throws -> [String: String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw AssetPipelineError.processingFailed("Invalid manifest format")
        }
        return manifest
    }
    
    /// CSSを処理
    /// - Parameters:
    ///   - content: CSSコンテンツ
    ///   - options: CSS処理オプション
    /// - Returns: 処理されたCSS
    public func processCSS(_ content: String, options: CSSProcessingOptions = CSSProcessingOptions()) -> String {
        var processed = content
        
        // ミニファイ
        if options.minify {
            processed = minifyCSS(processed)
        }
        
        // オートプレフィクサー（簡易実装）
        if options.autoprefixer {
            processed = addVendorPrefixes(processed)
        }
        
        return processed
    }
    
    /// JavaScriptを処理
    /// - Parameters:
    ///   - content: JavaScriptコンテンツ
    ///   - options: JavaScript処理オプション
    /// - Returns: 処理されたJavaScript
    public func processJS(_ content: String, options: JSProcessingOptions = JSProcessingOptions()) -> String {
        var processed = content
        
        // ミニファイ
        if options.minify {
            processed = minifyJS(processed)
        }
        
        // トランスパイル（簡易実装）
        if options.transpile {
            processed = transpileJS(processed, target: options.target)
        }
        
        return processed
    }
    
    // MARK: - Private Methods
    
    /// 連結ルールを処理
    private func processConcatenationRules(
        sourcePath: String,
        destinationPath: String,
        manifest: inout [String: String]
    ) throws {
        for rule in concatenationRules {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let files = try findFiles(matching: rule.pattern, in: sourceURL)
            
            var concatenatedContent = ""
            for file in files {
                let content = try String(contentsOf: file, encoding: .utf8)
                concatenatedContent += content + rule.separator
            }
            
            let outputPath = URL(fileURLWithPath: destinationPath).appendingPathComponent(rule.output)
            try concatenatedContent.write(to: outputPath, atomically: true, encoding: .utf8)
            
            // マニフェストに追加
            manifest[rule.output] = rule.output
        }
    }
    
    /// ディレクトリを処理
    private func processDirectory(
        _ sourceURL: URL,
        sourcePath: String,
        destinationPath: String,
        manifest: inout [String: String]
    ) throws {
        let contents = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
        
        for item in contents {
            let relativePath = item.path.replacingOccurrences(of: sourcePath + "/", with: "")
            
            // 除外パターンをチェック
            if shouldExclude(relativePath) {
                continue
            }
            
            if item.hasDirectoryPath {
                // サブディレクトリを再帰的に処理
                let subDestination = URL(fileURLWithPath: destinationPath).appendingPathComponent(item.lastPathComponent)
                try processDirectory(item, sourcePath: sourcePath, destinationPath: subDestination.path, manifest: &manifest)
            } else {
                // ファイルを処理
                try processFile(item, sourcePath: sourcePath, destinationPath: destinationPath, manifest: &manifest)
            }
        }
    }
    
    /// ファイルを処理
    private func processFile(
        _ sourceURL: URL,
        sourcePath: String,
        destinationPath: String,
        manifest: inout [String: String]
    ) throws {
        let relativePath = sourceURL.path.replacingOccurrences(of: sourcePath + "/", with: "")
        let assetType = detectAssetType(for: sourceURL.lastPathComponent)
        
        var content = try String(contentsOf: sourceURL, encoding: .utf8)
        var outputFilename = sourceURL.lastPathComponent
        
        // アセットタイプに応じて処理
        switch assetType {
        case .css:
            content = processCSS(content, options: cssOptions)
        case .javascript:
            content = processJS(content, options: jsOptions)
        case .image, .font, .other:
            // バイナリファイルはそのままコピー
            let data = try Data(contentsOf: sourceURL)
            let outputURL = URL(fileURLWithPath: destinationPath).appendingPathComponent(outputFilename)
            try data.write(to: outputURL)
            manifest[relativePath] = outputFilename
            return
        }
        
        // フィンガープリンティング
        if enableFingerprinting {
            outputFilename = addFingerprint(to: outputFilename, content: content)
        }
        
        // ファイルを書き込み
        let outputURL = URL(fileURLWithPath: destinationPath).appendingPathComponent(outputFilename)
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
        
        manifest[relativePath] = outputFilename
    }
    
    /// 除外すべきかチェック
    private func shouldExclude(_ path: String) -> Bool {
        for pattern in excludePatterns {
            if path.contains(pattern) {
                return true
            }
        }
        return false
    }
    
    /// パターンに一致するファイルを検索
    private func findFiles(matching pattern: String, in directory: URL) throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return contents.filter { $0.lastPathComponent.contains(pattern) }
    }
    
    /// CSSをミニファイ
    private func minifyCSS(_ css: String) -> String {
        // 簡易的なCSSミニファイ
        return css
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: ";\\s*}", with: "}", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// JavaScriptをミニファイ
    private func minifyJS(_ js: String) -> String {
        // 簡易的なJavaScriptミニファイ
        return js
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// ベンダープレフィックスを追加
    private func addVendorPrefixes(_ css: String) -> String {
        // 簡易的なベンダープレフィックス追加
        return css
    }
    
    /// JavaScriptをトランスパイル
    private func transpileJS(_ js: String, target: String) -> String {
        // 簡易的なJavaScriptトランスパイル
        return js
    }
    
    /// フィンガープリントを追加
    private func addFingerprint(to filename: String, content: String) -> String {
        let hash = SHA256.hash(data: content.data(using: .utf8) ?? Data())
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        let shortHash = String(hashString.prefix(8))
        
        let components = filename.components(separatedBy: ".")
        if components.count > 1 {
            let name = components.dropLast().joined(separator: ".")
            let ext = components.last!
            return "\(name).\(shortHash).\(ext)"
        } else {
            return "\(filename).\(shortHash)"
        }
    }
}
import Foundation

/// Asset pipeline for processing static assets.
public class AssetPipeline {
    private let fileManager = FileManager.default

    // Component managers
    private let processor: AssetProcessor
    private let fileManagerHelper: AssetFileManager

    // Configuration
    public var enableFingerprinting: Bool = false
    public var excludePatterns: [String] = []
    public var cssOptions: CSSProcessingOptions = CSSProcessingOptions()
    public var jsOptions: JSProcessingOptions = JSProcessingOptions()

    public init() {
        self.processor = AssetProcessor()
        self.fileManagerHelper = AssetFileManager()
    }

    /// static ディレクトリの中身を出力ディレクトリへ処理して書き出し、マニフェストを返す。
    ///
    /// 3つのパスに分かれる。CSS の最終バイト列は `url(...)` を書き換えた後にしか確定せず、
    /// その書き換えには参照先のハッシュ名が既に決まっている必要があるため、順序に依存がある。
    ///
    /// 1. CSS 以外（画像・JS・その他）を処理し、ハッシュして書き出す
    /// 2. CSS を処理し、1で確定したマニフェストで `url(...)` を書き換えてからハッシュする
    /// 3. HTML の書き換え。これはこのクラスの外、`SiteGenerator` の finalization ステップ
    ///
    /// - Returns: キーが static からの相対パス、値が出力ディレクトリからの相対パスのマニフェスト。
    ///   フィンガープリントが無効なときも全アセットを載せる。
    public func processAssets(from sourcePath: String, to destinationPath: String) throws -> AssetManifest {
        var manifest = AssetManifest()

        try fileManager.createDirectory(
            atPath: destinationPath,
            withIntermediateDirectories: true
        )

        let sourceURL = URL(fileURLWithPath: sourcePath)
        var stylesheets: [(url: URL, relativePath: String)] = []

        // パス1: CSS 以外。
        try fileManagerHelper.processDirectory(
            sourceURL,
            sourcePath: sourcePath,
            excludePatterns: excludePatterns
        ) { fileURL, relativePath in
            if self.processor.detectAssetType(for: fileURL.lastPathComponent) == .css {
                stylesheets.append((fileURL, relativePath))
                return
            }
            try self.processNonStylesheet(
                fileURL,
                relativePath: relativePath,
                destinationPath: destinationPath,
                manifest: &manifest
            )
        }

        // パス2: CSS。
        for stylesheet in stylesheets {
            try processStylesheet(
                stylesheet.url,
                relativePath: stylesheet.relativePath,
                destinationPath: destinationPath,
                manifest: &manifest
            )
        }

        return manifest
    }

    // Detect asset type from filename
    public func detectAssetType(for filename: String) -> AssetItem.AssetType {
        return processor.detectAssetType(for: filename)
    }

    // Save manifest to file
    public func saveManifest(_ manifest: AssetManifest, to path: String) throws {
        try fileManagerHelper.saveManifest(manifest, to: path)
    }

    // Load manifest from file
    public func loadManifest(from path: String) throws -> AssetManifest {
        return try fileManagerHelper.loadManifest(from: path)
    }

    // MARK: - Private

    /// 画像・JS・その他。画像とその他はコピーのみなのでソースバイト = 出力バイト。
    /// メモリマップで読むので、大きな画像でも常駐メモリを食わない。
    private func processNonStylesheet(
        _ fileURL: URL,
        relativePath: String,
        destinationPath: String,
        manifest: inout AssetManifest
    ) throws {
        let data: Data
        switch processor.detectAssetType(for: fileURL.lastPathComponent) {
        case .javascript:
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            data = Data(processor.processJS(content, options: jsOptions).utf8)
        default:
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        }
        try write(data, relativePath: relativePath, destinationPath: destinationPath, manifest: &manifest)
    }

    /// CSS。最小化してから `url(...)` を書き換え、**その結果**をハッシュする。
    private func processStylesheet(
        _ fileURL: URL,
        relativePath: String,
        destinationPath: String,
        manifest: inout AssetManifest
    ) throws {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let processed = processor.processCSS(content, options: cssOptions)
        let result = AssetReferenceRewriter.rewriteCSS(
            processed,
            manifest: manifest,
            inDirectory: AssetManifest.parentDirectory(of: relativePath)
        )

        for reference in result.unresolvedStylesheetReferences {
            warn("\(relativePath): url(\(reference)) points at another stylesheet; "
                 + "fingerprinting does not rewrite CSS-to-CSS references")
        }

        try write(
            Data(result.content.utf8),
            relativePath: relativePath,
            destinationPath: destinationPath,
            manifest: &manifest
        )
    }

    /// 出力先の閉じ込め、ハッシュ、書き込み、マニフェストへの登録。
    private func write(
        _ data: Data,
        relativePath: String,
        destinationPath: String,
        manifest: inout AssetManifest
    ) throws {
        let destinationRootURL = URL(fileURLWithPath: destinationPath).resolvingSymlinksInPath()
        let candidateURL = destinationRootURL
            .appendingPathComponent(relativePath)
            .resolvingSymlinksInPath()

        let rootPath = destinationRootURL.path.hasSuffix("/")
            ? destinationRootURL.path
            : destinationRootURL.path + "/"
        guard candidateURL.path == destinationRootURL.path || candidateURL.path.hasPrefix(rootPath) else {
            throw AssetPipelineError.processingFailed(
                "Output path escapes destination directory: \(candidateURL.path)"
            )
        }

        var outputURL = candidateURL
        var outputRelativePath = relativePath
        if enableFingerprinting {
            let fingerprint = processor.generateFingerprint(for: data)
            outputURL = URL(fileURLWithPath: processor.addFingerprint(to: candidateURL.path, fingerprint: fingerprint))
            let directory = AssetManifest.parentDirectory(of: relativePath)
            outputRelativePath = directory.isEmpty
                ? outputURL.lastPathComponent
                : directory + "/" + outputURL.lastPathComponent
        }

        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(atPath: outputURL.path)
        }
        try data.write(to: outputURL)

        manifest[relativePath] = outputRelativePath
    }

    private func warn(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("⚠️  \(message)\n".utf8))
    }

    // Process CSS content
    public func processCSS(_ content: String, options: CSSProcessingOptions = CSSProcessingOptions()) -> String {
        return processor.processCSS(content, options: options)
    }

    // Process JavaScript content
    public func processJS(_ content: String, options: JSProcessingOptions = JSProcessingOptions()) -> String {
        return processor.processJS(content, options: options)
    }
}

// AssetPipelineError is defined in Assets/AssetPipelineError.swift

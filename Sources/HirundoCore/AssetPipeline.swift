import Foundation

/// static ディレクトリのアセットを処理して出力ディレクトリへ書き出す。
///
/// `config.yaml` から届く設定は `features.minify` と `features.fingerprint` の2つ。
/// `excludePatterns` はライブラリ利用者向けの面で、パターンは**ファイル名**にのみ照合される。
///
/// フィンガープリントを有効にすると、出力名は `<name>-<16桁のハッシュ>.<ext>` になり、
/// ハッシュはそのファイルの**最終的な出力バイト列**に対して取られる。CSS の最終バイト列は
/// `url(...)` を書き換えた後にしか確定しないため、処理は「CSS 以外 → CSS」の2パスに分かれる。
/// 生成された HTML の書き換えは `SiteGenerator` の `asset references` ステップが行う。
public class AssetPipeline {
    private let fileManager = FileManager.default

    // Component managers
    private let processor: AssetProcessor
    private let fileManagerHelper: AssetFileManager

    // Configuration
    public var enableFingerprinting: Bool = false

    /// **コピーそのものをしない**ファイルのパターン。一致したファイルは出力ディレクトリに
    /// 一切現れず、マニフェストにも載らない。
    ///
    /// `AssetFileManager.matchesPattern` の五択（`*`、`*x*`、`*x`、`x*`、完全一致）だけを
    /// 理解する簡易マッチャーで、`shouldExclude` がパターンをファイル名（ディレクトリ部分を
    /// 落とした最後の要素）にのみ照合する ── ディレクトリを含むパターン（`images/*.png` など）
    /// は意図どおりに効かない。`/` の有無で挙動を変える `fingerprintExclusions` とは別物なので
    /// 混同しないこと。「コピーするがハッシュしない」ファイルには代わりに `fingerprintExclusions`
    /// を使う。
    public var excludePatterns: [String] = []

    /// **コピーはするがフィンガープリントだけ外す**ファイル。`enableFingerprinting` が true
    /// でも、ここに一致するファイルは元の名前のまま書き出す（`write` 内の唯一のハッシュ判定
    /// 箇所で参照する）。
    ///
    /// `AssetFingerprintExclusions.matches` というセグメント対応のマッチャーを使う。パターンに
    /// `/` を含むかどうかでファイル名一致とパス全体一致を切り替え、`*` と `**` を理解する ──
    /// `excludePatterns` の五択マッチャーより表現力が高い。「一切コピーしない」ファイルには
    /// 代わりに `excludePatterns` を使う。
    public var fingerprintExclusions: AssetFingerprintExclusions = AssetFingerprintExclusions()
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
    /// この処理にロールバックは無い。途中で throw すると、その時点までに処理し終えたアセットは
    /// 既に（フィンガープリント有効時はハッシュ付きの名前で）出力ディレクトリに書き出されており、
    /// 呼び出し側はマニフェストを受け取れない。中途半端な出力ツリーが残るということであり、
    /// 直し方はクリーンビルド（`--clean`）のやり直しになる。
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

        // パス2: CSS。全 CSS を同時に扱うため、あるスタイルシートが処理順で先に来た別の
        // スタイルシートを `url(...)` で参照していても、そのハッシュ名はまだ決まっていない
        // （CSS→CSS参照は解決しない、が仕様）。パス1完了時点のマニフェストを固定して使うことで、
        // 列挙順に処理結果が左右されないようにする。
        let pass1Manifest = manifest
        for stylesheet in stylesheets {
            try processStylesheet(
                stylesheet.url,
                relativePath: stylesheet.relativePath,
                destinationPath: destinationPath,
                pass1Manifest: pass1Manifest,
                manifest: &manifest
            )
        }

        return manifest
    }

    // Detect asset type from filename
    public func detectAssetType(for filename: String) -> AssetType {
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

    /// `write` に渡す元データ。インメモリの `Data` か、コピー元を指す `URL` のどちらか。
    ///
    /// 2つに分けているのは、画像などのパススルーアセットで `FileManager.copyItem` を使うため。
    /// `copyItem` はパーミッションや拡張属性を保ったまま、APFS では実体コピーすらせずクローンする。
    /// バイト列を経由すると両方失うので、この場合は `Data` を作らない。
    private enum AssetContent {
        case data(Data)
        case file(URL)
    }

    /// 画像・その他。コピーのみなのでソースバイト＝出力バイト。
    ///
    /// `FileManager.copyItem` でコピーする（パーミッション・拡張属性を保ち、APFS ではクローンに
    /// なる）。ハッシュが要る場合も、コピー元をストリーミングで読んで計算するので、まるごと
    /// メモリに載せることはない。JS だけは中身を書き換える必要があるためテキストとして読む。
    private func processNonStylesheet(
        _ fileURL: URL,
        relativePath: String,
        destinationPath: String,
        manifest: inout AssetManifest
    ) throws {
        switch processor.detectAssetType(for: fileURL.lastPathComponent) {
        case .javascript:
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let data = Data(processor.processJS(content, options: jsOptions).utf8)
            try write(.data(data), relativePath: relativePath, destinationPath: destinationPath, manifest: &manifest)
        default:
            try write(.file(fileURL), relativePath: relativePath, destinationPath: destinationPath, manifest: &manifest)
        }
    }

    /// CSS。最小化してから `url(...)` を書き換え、**その結果**をハッシュする。
    ///
    /// `url(...)` の書き換えは、フィンガープリントが無効なときは必ず no-op（マニフェストの
    /// 値はすべてキーと等しいので `AssetManifest.rewrite` は常に `nil` を返す）。それにも
    /// 関わらず書き換えと警告を無条件に走らせると、フィンガープリントを有効にしていない
    /// 既定のビルドでも「CSS→CSS 参照は解決できない」という無関係な警告が出てしまうため、
    /// ここで `enableFingerprinting` を見て丸ごとスキップする。
    private func processStylesheet(
        _ fileURL: URL,
        relativePath: String,
        destinationPath: String,
        pass1Manifest: AssetManifest,
        manifest: inout AssetManifest
    ) throws {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let processed = processor.processCSS(content, options: cssOptions)

        let finalContent: String
        if enableFingerprinting {
            let result = AssetReferenceRewriter.rewriteCSS(
                processed,
                manifest: pass1Manifest,
                inDirectory: AssetManifest.parentDirectory(of: relativePath)
            )

            for reference in result.unresolvedStylesheetReferences {
                warn("\(relativePath): url(\(reference)) points at another stylesheet; "
                     + "fingerprinting does not rewrite CSS-to-CSS references")
            }

            finalContent = result.content
        } else {
            finalContent = processed
        }

        try write(
            .data(Data(finalContent.utf8)),
            relativePath: relativePath,
            destinationPath: destinationPath,
            manifest: &manifest
        )
    }

    /// 出力先の閉じ込め、ハッシュ、書き込み、マニフェストへの登録。
    ///
    /// ハッシュ・書き込み・マニフェスト登録が1箇所に集まっているのが不変条件。「書き込んだバイト
    /// 以外の何か」をハッシュすることが構造的にできないのはこれのおかげなので、`AssetContent`
    /// で入力の形（メモリ上のデータか、コピー元ファイルか）を分けても、ハッシュ計算・書き込み・
    /// 登録という処理そのものは分岐させず、ここに置いたままにする。
    private func write(
        _ content: AssetContent,
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
        if enableFingerprinting && !fingerprintExclusions.excludes(relativePath) {
            let fingerprint: String
            switch content {
            case .data(let data):
                fingerprint = processor.generateFingerprint(for: data)
            case .file(let fileURL):
                // ソースをストリーミングで読んでハッシュする。まるごとメモリに載せない。
                fingerprint = try processor.generateFingerprint(for: fileURL)
            }
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

        switch content {
        case .data(let data):
            try data.write(to: outputURL, options: .atomic)
        case .file(let fileURL):
            // `copyItem` はパーミッションと拡張属性を保ち、APFS では実体コピーせずクローンする。
            // ただし `copyItem` はシンボリックリンクをリンクのままコピーする。ソースが
            // シンボリックリンク（`static/img/logo.png -> ../../shared/logo.png` のような
            // ベンダリング）だと、出力もリンクになってしまい、以下の問題を引き起こす。
            //
            // - `_site` を単体で持ち出す（アーカイブ・アップロードなど）と、相対リンクの
            //   解決先が存在せず画像が失われる。
            // - フィンガープリント有効時、上のハッシュは `FileHandle` 経由でリンク先の
            //   実体を読んで計算する一方、書き込まれるのはリンクそのものなので、
            //   「ハッシュは書き込んだバイト列を覆う」という不変条件が壊れる。
            // - 次の非クリーンビルドで、このリンクが `write` 冒頭の閉じ込め判定に
            //   `resolvingSymlinksInPath()` 済みの候補パスとして通り、リンク先が出力先の
            //   外を指していれば `Output path escapes destination directory` で落ちる
            //   （`removeItem` が走らないので自己修復もできない）。
            //
            // そのためコピー元は必ず解決してから読む。
            //
            // 加えて、`removeItem` の後に `copyItem` する2段階だと、コピーが失敗した時点で
            // 直前の良い出力を失い、`serve` から見ればファイルが存在しない瞬間ができる
            // （パイプライン内の他の書き込みはすべて `.atomic` なのに、ここだけそうでない）。
            // 一時名へコピーしてから `replaceItemAt` で原子的に差し替えることで、パーミッション・
            // 拡張属性を保つという `copyItem` を選んだ理由を残したまま、両方を直す。
            let source = fileURL.resolvingSymlinksInPath()
            let staging = outputURL.deletingLastPathComponent()
                .appendingPathComponent(".hirundo-\(UUID().uuidString)")
            defer {
                // 成功時は `replaceItemAt` が消費して既に存在しない。throw で抜けた場合だけ
                // 残っているので、原子的な差し替えの体裁を保つために掃除する。
                if fileManager.fileExists(atPath: staging.path) {
                    try? fileManager.removeItem(at: staging)
                }
            }
            try fileManager.copyItem(at: source, to: staging)
            _ = try fileManager.replaceItemAt(outputURL, withItemAt: staging)
        }

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

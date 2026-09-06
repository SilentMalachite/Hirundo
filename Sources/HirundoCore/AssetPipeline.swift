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
///
/// 例外が2つある。どちらも「参照を書き換えられないので名前を変えると壊れる」ものに限る。
///
/// - `AssetNamePolicy` が挙げる固定 URL のアセット（`robots.txt`、`.well-known/**` など）
/// - 互いに（あるいは自分自身を）参照しあうスタイルシート
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
    /// 2. CSS を依存順（参照される側が先）に処理し、`url(...)` と `@import` を書き換えてから
    ///    ハッシュする
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

        // パス2: CSS。参照先のハッシュ名が先に決まっている必要があるため、スタイルシート同士の
        // 依存関係をたどって参照される側から順に処理する。
        try processStylesheets(stylesheets, destinationPath: destinationPath, manifest: &manifest)

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

    /// CSS を依存順に処理する。
    ///
    /// あるスタイルシートの `url(...)` / `@import` を書き換えるには、参照先のスタイルシートの
    /// ハッシュ名が既に決まっていなければならない。参照される側から順に処理すればそれが満たせる。
    ///
    /// 互いに参照しあう（あるいは自分自身を参照する）スタイルシートだけは、どう並べても満たせない。
    /// そこだけはフィンガープリントを諦めて元の名前で出力する。参照は書き換えられないまま残るが、
    /// 参照先も元の名前で出力されるので壊れない。
    private func processStylesheets(
        _ stylesheets: [(url: URL, relativePath: String)],
        destinationPath: String,
        manifest: inout AssetManifest
    ) throws {
        // 最小化まで済ませた内容を持ち回る。依存関係の抽出と書き換えが同じバイト列を見るため。
        var contents: [String: String] = [:]
        var keys: [String] = []
        for stylesheet in stylesheets {
            let raw = try String(contentsOf: stylesheet.url, encoding: .utf8)
            contents[stylesheet.relativePath] = processor.processCSS(raw, options: cssOptions)
            keys.append(stylesheet.relativePath)
        }

        var dependencies: [String: [String]] = [:]
        for key in keys {
            let directory = AssetManifest.parentDirectory(of: key)
            dependencies[key] = AssetReferenceRewriter.cssReferences(in: contents[key] ?? "")
                .compactMap { AssetManifest.resolveKey(reference: $0, inDirectory: directory) }
                .filter { contents[$0] != nil }
        }

        let (order, cyclic) = Self.dependencyOrder(of: keys, dependencies: dependencies)
        if enableFingerprinting && !cyclic.isEmpty {
            warn("stylesheets import each other (\(cyclic.sorted().joined(separator: ", "))); "
                 + "they keep their original names")
        }

        let knownStylesheets = Set(keys)
        for key in order {
            guard let content = contents[key] else { continue }
            try processStylesheet(
                content,
                relativePath: key,
                destinationPath: destinationPath,
                allowFingerprint: !cyclic.contains(key),
                knownStylesheets: knownStylesheets,
                manifest: &manifest
            )
        }
    }

    /// 参照される側が先に来る順序と、順序では解決できない（閉路にいる）キーの集合。
    private static func dependencyOrder(
        of keys: [String],
        dependencies: [String: [String]]
    ) -> (order: [String], cyclic: Set<String>) {
        enum Mark { case visiting, done }
        var marks: [String: Mark] = [:]
        var order: [String] = []
        var cyclic: Set<String> = []
        var stack: [String] = []

        func visit(_ key: String) {
            switch marks[key] {
            case .done:
                return
            case .visiting:
                // 後退辺。スタックの key 以降がまるごと閉路。
                if let start = stack.firstIndex(of: key) {
                    cyclic.formUnion(stack[start...])
                }
                return
            case nil:
                break
            }

            marks[key] = .visiting
            stack.append(key)
            for dependency in dependencies[key] ?? [] {
                visit(dependency)
            }
            stack.removeLast()
            marks[key] = .done
            order.append(key)
        }

        for key in keys { visit(key) }
        return (order, cyclic)
    }

    /// 最小化済みの CSS の参照を書き換え、**その結果**をハッシュして書き出す。
    ///
    /// `url(...)` の書き換えは、フィンガープリントが無効なときは必ず no-op（マニフェストの
    /// 値はすべてキーと等しいので `AssetManifest.rewrite` は常に `nil` を返す）。それにも
    /// 関わらず書き換えと警告を無条件に走らせると、フィンガープリントを有効にしていない
    /// 既定のビルドでも無関係な警告が出てしまうため、ここで `enableFingerprinting` を見て
    /// 丸ごとスキップする。
    private func processStylesheet(
        _ content: String,
        relativePath: String,
        destinationPath: String,
        allowFingerprint: Bool,
        knownStylesheets: Set<String>,
        manifest: inout AssetManifest
    ) throws {
        let finalContent: String
        if enableFingerprinting {
            let directory = AssetManifest.parentDirectory(of: relativePath)
            let result = AssetReferenceRewriter.rewriteCSS(
                content,
                manifest: manifest,
                inDirectory: directory
            )

            // 閉路にいるスタイルシートへの参照もここに現れるが、それは上で1度報告済みで、かつ
            // 参照先も元の名前で出るので壊れていない。報告するのは行き先が無い参照だけ。
            for reference in result.unresolvedStylesheetReferences {
                let key = AssetManifest.resolveKey(reference: reference, inDirectory: directory)
                guard key == nil || !knownStylesheets.contains(key!) else { continue }
                warn("\(relativePath): \(reference) does not resolve to a stylesheet in "
                     + "the static directory; left unchanged")
            }

            finalContent = result.content
        } else {
            finalContent = content
        }

        try write(
            Data(finalContent.utf8),
            relativePath: relativePath,
            destinationPath: destinationPath,
            allowFingerprint: allowFingerprint,
            manifest: &manifest
        )
    }

    /// 出力先の閉じ込め、ハッシュ、書き込み、マニフェストへの登録。
    private func write(
        _ data: Data,
        relativePath: String,
        destinationPath: String,
        allowFingerprint: Bool = true,
        manifest: inout AssetManifest
    ) throws {
        let destinationRootURL = URL(fileURLWithPath: destinationPath).resolvingSymlinksInPath()
        let candidateURL = destinationRootURL
            .appendingPathComponent(relativePath)
            .resolvingSymlinksInPath()

        guard AssetPruner.relativePath(of: candidateURL, under: destinationRootURL) != nil else {
            throw AssetPipelineError.processingFailed(
                "Output path escapes destination directory: \(candidateURL.path)"
            )
        }

        var outputURL = candidateURL
        if enableFingerprinting && allowFingerprint && !AssetNamePolicy.requiresStableName(relativePath) {
            let fingerprint = processor.generateFingerprint(for: data)
            outputURL = URL(fileURLWithPath: processor.addFingerprint(to: candidateURL.path, fingerprint: fingerprint))
        }

        // マニフェストの値は「実際に書いた場所」でなければならない。出力ツリーの中に
        // シンボリックリンクがあると書き込み先はソースの相対パスからは導けないので、
        // 確定した書き込み先から逆算する。
        guard let outputRelativePath = AssetPruner.relativePath(of: outputURL, under: destinationRootURL) else {
            throw AssetPipelineError.processingFailed(
                "Output path escapes destination directory: \(outputURL.path)"
            )
        }

        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)

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

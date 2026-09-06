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
/// - `AssetFingerprintExclusions` に一致するアセット（`robots.txt`、`.well-known/**` など、
///   固定 URL で取得されるもの。`assets.fingerprintExclude` で追加できる）
/// - 互いに（あるいは自分自身を）参照しあうスタイルシート
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
    /// 2. CSS を依存順（参照される側が先）に処理し、`url(...)` と `@import` を書き換えてから
    ///    ハッシュする
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

        // パス2: CSS。参照先のハッシュ名が先に決まっている必要があるため、スタイルシート同士の
        // 依存関係をたどって参照される側から順に処理する。
        try processStylesheets(stylesheets, destinationPath: destinationPath, manifest: &manifest)

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
            .data(Data(finalContent.utf8)),
            relativePath: relativePath,
            destinationPath: destinationPath,
            allowFingerprint: allowFingerprint,
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
        allowFingerprint: Bool = true,
        manifest: inout AssetManifest
    ) throws {
        let destinationRootURL = URL(fileURLWithPath: destinationPath).resolvingSymlinksInPath()
        let rawCandidateURL = destinationRootURL.appendingPathComponent(relativePath)

        // 閉じ込めの判定は親ディレクトリまでを解決して行い、最後の要素は解決しない。最後の要素は
        // これから置き換える対象であって辿る対象ではないためで、辿ってしまうと前回のビルドが
        // 残したシンボリックリンク（以前のバージョンが書き出した `_site` がまさにそれ）の
        // 解決先が出力先の外だという理由でビルドが落ち、自己修復できなくなる。
        // 途中のディレクトリが出力先の外を指すリンクだった場合は、親の解決で弾かれる。
        let lastComponent = rawCandidateURL.lastPathComponent
        let parentURL = rawCandidateURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let candidateURL = parentURL.appendingPathComponent(lastComponent)

        guard lastComponent != "." && lastComponent != "..",
              let outputDirectory = Self.relativeDirectory(of: parentURL, under: destinationRootURL) else {
            throw AssetPipelineError.processingFailed(
                "Output path escapes destination directory: \(candidateURL.path)"
            )
        }

        var outputURL = candidateURL
        if enableFingerprinting && allowFingerprint && !fingerprintExclusions.excludes(relativePath) {
            let fingerprint: String
            switch content {
            case .data(let data):
                fingerprint = processor.generateFingerprint(for: data)
            case .file(let fileURL):
                // ソースをストリーミングで読んでハッシュする。まるごとメモリに載せない。
                fingerprint = try processor.generateFingerprint(for: fileURL)
            }
            outputURL = URL(fileURLWithPath: processor.addFingerprint(to: candidateURL.path, fingerprint: fingerprint))
        }

        // マニフェストの値は「実際に書いた場所」でなければならない。途中のディレクトリが
        // 出力ツリー内のシンボリックリンクなら、値は解決先（実体）の側になる ── 掃除
        // （`AssetPruner`）も同じく実体側の相対パスで「残すもの」を判定するため、ここで
        // 食い違うと書いたばかりのファイルが掃除で消える。
        let outputRelativePath = outputDirectory.isEmpty
            ? outputURL.lastPathComponent
            : outputDirectory + "/" + outputURL.lastPathComponent

        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 出力先にシンボリックリンクが残っていると（以前のバージョンが書き出した `_site` が
        // まさにそれ）、`replaceItemAt` は "file doesn't exist" で失敗する。最後の要素は
        // 置き換える対象であって辿る対象ではないので、どちらの書き込み経路でも先に取り除いて
        // おき、非クリーン再ビルドで自己修復させる。`attributesOfItem` は `lstat` 相当で
        // リンクを辿らないため、壊れたリンクも判定できる。
        if let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path),
           attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            try fileManager.removeItem(at: outputURL)
        }

        switch content {
        case .data(let data):
            try data.write(to: outputURL, options: .atomic)
        case .file(let fileURL):
            // `copyItem` はパーミッションと拡張属性を保ち、APFS では実体コピーせずクローンする。
            // ただし `copyItem` はシンボリックリンクをリンクのままコピーする。`static/` の中で
            // 完結するリンク（`AssetFileManager` が通すのはこれだけ）でも、出力側がリンクに
            // なると以下の問題を引き起こす。
            //
            // - `_site` を単体で持ち出す（アーカイブ・アップロードなど）と、リンクの解決先が
            //   出力ツリーの中にあるとは限らず、ファイルが失われる。
            // - フィンガープリント有効時、上のハッシュは `FileHandle` 経由でリンク先の
            //   実体を読んで計算する一方、書き込まれるのはリンクそのものなので、
            //   「ハッシュは書き込んだバイト列を覆う」という不変条件が壊れる。
            //
            // そのためコピー元は必ず解決してから読む。
            //
            // 加えて、`removeItem` の後に `copyItem` する2段階だと、コピーが失敗した時点で
            // 直前の良い出力を失い、`serve` から見ればファイルが存在しない瞬間ができる
            // （パイプライン内の他の書き込みはすべて `.atomic` なのに、ここだけそうでない）。
            // 一時名へコピーしてから `replaceItemAt` で原子的に差し替えることで、パーミッション・
            // 拡張属性を保つという `copyItem` を選んだ理由を残したまま、両方を直す。
            let source = fileURL.resolvingSymlinksInPath()
            // `resolvingSymlinksInPath` は最後の要素が解決できない壊れたリンクには何もしない。
            // そのまま `copyItem` するとリンクのままコピーされ、上の問題がそっくり再現する。
            // 修正前の `Data(contentsOf:)` はここで失敗していたので、同じく失敗させる。
            guard fileManager.fileExists(atPath: source.path) else {
                throw AssetPipelineError.processingFailed(
                    "Asset source is not readable (broken symlink?): \(fileURL.path)"
                )
            }
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
            // 既定では差し替え先（＝前回の出力）のメタデータが引き継がれるため、`static/` 側で
            // パーミッションを変えても非クリーン再ビルドに反映されない。`copyItem` が運んできた
            // ソース由来のメタデータを使う。
            _ = try fileManager.replaceItemAt(
                outputURL,
                withItemAt: staging,
                options: .usingNewMetadataOnly
            )
        }

        manifest[relativePath] = outputRelativePath
    }

    /// 解決済みの親ディレクトリの、出力ルートからの相対パス。ルート直下なら空文字列、
    /// ルートの外なら `nil`。
    ///
    /// 相対化するのはディレクトリだけで、最後の要素は呼び出し側が未解決のまま足す。
    /// パス全体を解決してしまうと、置き換える予定の出力側リンクを辿った先を
    /// マニフェストに書いてしまう。
    private static func relativeDirectory(of directory: URL, under root: URL) -> String? {
        let rootPath = root.path
        if directory.path == rootPath { return "" }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard directory.path.hasPrefix(prefix) else { return nil }
        return String(directory.path.dropFirst(prefix.count))
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

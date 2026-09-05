# AssetPipeline フィンガープリントと参照書き換え 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `features.fingerprint` を追加し、アセットに内容ハッシュを付けたうえで HTML と CSS の参照をそのハッシュ名に書き換える。あわせて結合・ソースマップ・JS トランスパイルという未到達コードを削除する。

**Architecture:** アセット処理を3パスに分ける。パス1で CSS 以外を処理・ハッシュし、パス2で CSS を最小化してから `url(...)` を書き換え、その結果をハッシュする（CSS の最終バイト列は書き換え後にしか確定しないため）。パス3は `finalizationSteps` の新しいステップとして出力ツリーの HTML を書き換える。書き換えの中核は I/O を持たない純粋関数に切り出し、ファイルシステム無しでテストできるようにする。

**Tech Stack:** Swift 5.9+、XCTest、CryptoKit（SHA-256、既存）、Yams（設定、既存）。新しい依存は追加しない。

**Spec:** `docs/superpowers/specs/2026-09-06-asset-pipeline-fingerprinting-design.md`

## Global Constraints

- 対応 OS は macOS 12+、Swift 5.9+。新しい外部依存を追加しない
- 出力ハッシュは SHA-256 の先頭 16 桁の小文字 hex。出力名は `<name>-<hash>.<ext>`
- マニフェストのキーは static ディレクトリからの相対パス、値は出力ディレクトリからの相対パス。区切りは常に `/`
- `features.fingerprint` のデフォルトは `false`。既存の `config.yaml` の意味を変えない
- 書き換え器は入力を逐語的にコピーし、マニフェストのキーに解決できた値だけを差し替える。HTML を再シリアライズしない
- 新規ソースは `Sources/HirundoCore/Assets/` に置く。テストは `Tests/HirundoTests/` に置く
- コミットは Conventional Commits 形式（`feat:` / `fix:` / `refactor:` / `docs:` / `test:`）

## File Structure

| ファイル | 責務 |
|---|---|
| `Sources/HirundoCore/Assets/AssetManifest.swift`（新規） | キー/値の保持、参照文字列の解決とキー照合。I/O 無しの純粋な型 |
| `Sources/HirundoCore/Assets/AssetReferenceRewriter.swift`（新規） | HTML / CSS の文字列を受け取り書き換えた文字列を返す。I/O 無し |
| `Sources/HirundoCore/Assets/AssetPruner.swift`（新規） | 出力ツリーから、現在のマニフェストに無いフィンガープリント名のファイルを削除 |
| `Sources/HirundoCore/AssetPipeline.swift`（変更） | 3パスの司令塔。ハッシュ・書き込み・出力先の閉じ込め |
| `Sources/HirundoCore/Assets/AssetProcessor.swift`（変更） | 処理結果を返す API に変更。`transpileJS` を削除 |
| `Sources/HirundoCore/Assets/AssetFileManager.swift`（変更） | ディレクトリ走査とマニフェスト保存のみに縮小 |
| `Sources/HirundoCore/Assets/AssetProcessingOptions.swift`（変更） | `sourceMap` / `transpile` / `target` を削除 |
| `Sources/HirundoCore/Assets/AssetConcatenator.swift`（削除） | 結合機能ごと削除 |
| `Sources/HirundoCore/Assets/AssetConcatenationRule.swift`（削除） | 同上 |
| `Sources/HirundoCore/Models/Features.swift`（変更） | `fingerprint` フラグ追加 |
| `Sources/HirundoCore/SiteGenerator.swift`（変更） | `asset references` ステップ追加、prune 呼び出し、マニフェスト保持 |
| `Sources/HirundoCore/Scaffold/ScaffoldTemplates.swift`（変更） | `hirundo init` の config に1行追加 |

## タスク一覧

1. 未到達コードの削除（結合・ソースマップ・トランスパイル）
2. `AssetManifest` — 参照解決の純粋ロジック
3. `AssetReferenceRewriter` — CSS の `url(...)`
4. `AssetReferenceRewriter` — HTML の属性
5. `AssetPipeline` の3パス化とハッシュ対象の修正
6. `AssetPruner` — 古い出力の削除
7. `features.fingerprint` の設定面
8. `SiteGenerator` の配線（prune と `asset references` ステップ）
9. 統合テスト
10. ドキュメント更新

---

### Task 1: 未到達コードの削除（結合・ソースマップ・トランスパイル）

先に消す。後続のタスクが触るファイルが小さくなり、書き換え対象の見通しが良くなる。

**Files:**
- Delete: `Sources/HirundoCore/Assets/AssetConcatenator.swift`
- Delete: `Sources/HirundoCore/Assets/AssetConcatenationRule.swift`
- Modify: `Sources/HirundoCore/Assets/AssetProcessingOptions.swift`
- Modify: `Sources/HirundoCore/Assets/AssetProcessor.swift`
- Modify: `Sources/HirundoCore/Assets/AssetFileManager.swift`
- Modify: `Sources/HirundoCore/AssetPipeline.swift`
- Test: `Tests/HirundoTests/AssetPipelineTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `CSSProcessingOptions(minify:autoprefixer:)`、`JSProcessingOptions(minify:)`、`AssetFileManager.processDirectory(_:sourcePath:excludePatterns:onFile:)`

- [ ] **Step 1: 結合のテストを削除する**

`Tests/HirundoTests/AssetPipelineTests.swift` から `testAssetConcatenation()` を丸ごと削除する（`func testAssetConcatenation() throws {` から対応する閉じ括弧まで）。

- [ ] **Step 2: 結合の2ファイルを削除する**

```bash
git rm Sources/HirundoCore/Assets/AssetConcatenator.swift Sources/HirundoCore/Assets/AssetConcatenationRule.swift
```

- [ ] **Step 3: 処理オプションから未到達のプロパティを削除する**

`Sources/HirundoCore/Assets/AssetProcessingOptions.swift` の全体を次で置き換える。

```swift
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
```

- [ ] **Step 4: `AssetProcessor` からトランスパイルを削除する**

`Sources/HirundoCore/Assets/AssetProcessor.swift` の `processJS` から `transpile` 分岐を落とす。

```swift
    /// Processes JavaScript content
    public func processJS(_ content: String, options: JSProcessingOptions = JSProcessingOptions()) -> String {
        var processed = content

        if options.minify {
            processed = minifyJS(processed)
        }

        return processed
    }
```

同ファイル末尾の `transpileJS(_:target:)` メソッドを丸ごと削除する（`/// JavaScript transpilation (disabled for safety)` のコメント行から対応する閉じ括弧まで）。

- [ ] **Step 5: `AssetFileManager` から結合まわりを削除する**

`findFiles(matching:in:)` と `isConcatenatedFile(_:rules:)` を削除し、`processDirectory` のシグネチャから `destinationPath`（どこにも使われていない）と `concatenationRules` を落とす。

```swift
    /// Processes a directory recursively
    public func processDirectory(
        _ directoryURL: URL,
        sourcePath: String,
        excludePatterns: [String],
        onFile: (URL, String) throws -> Void
    ) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for itemURL in contents {
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDirectory {
                try processDirectory(
                    itemURL,
                    sourcePath: sourcePath,
                    excludePatterns: excludePatterns,
                    onFile: onFile
                )
            } else {
                let standardizedItemPath = itemURL.standardizedFileURL.path
                let standardizedSourcePath = URL(fileURLWithPath: sourcePath).standardizedFileURL.path
                let relativePath = standardizedItemPath.replacingOccurrences(of: standardizedSourcePath + "/", with: "")

                if shouldExclude(path: relativePath, patterns: excludePatterns) {
                    continue
                }

                try onFile(itemURL, relativePath)
            }
        }
    }
```

`shouldExclude` の直前のドキュメントコメントを、ファイル名にしか照合しない事実が読み取れるように直す。

```swift
    /// Checks if path should be excluded.
    ///
    /// パターンは**ファイル名**にのみ照合される。`css/*.tmp` のようなディレクトリ付きの
    /// パターンは意図どおりには効かない。
    private func shouldExclude(path: String, patterns: [String]) -> Bool {
```

- [ ] **Step 6: `AssetPipeline` から結合とソースマップを削除する**

`Sources/HirundoCore/AssetPipeline.swift` から次を削除する。

- ファイル冒頭の欠陥リストのドキュメントコメント全体（`/// Asset pipeline for processing static assets.` から `///   is generated by any code path.` まで）と、その上の `// AssetConcatenationRule is defined in ...` 行
- `private let concatenator: AssetConcatenator` と `init` 内の `self.concatenator = AssetConcatenator()`
- `public var enableSourceMaps: Bool = false`
- `public var concatenationRules: [AssetConcatenationRule] = []`
- `processAssets` 内の `if !concatenationRules.isEmpty { ... }` ブロック全体

`processAssets` 内の `fileManagerHelper.processDirectory` の呼び出しから `destinationPath:` と `concatenationRules:` の引数を落とす。クラス宣言の直前には次の暫定コメントを置く（Task 10 で最終版に差し替える）。

```swift
/// Asset pipeline for processing static assets.
public class AssetPipeline {
```

- [ ] **Step 7: ビルドとテストが通ることを確認する**

```bash
swift build 2>&1 | tail -20
swift test --filter AssetPipelineTests 2>&1 | tail -20
```

Expected: ビルド成功。`AssetPipelineTests` が9件パス（`testAssetConcatenation` が消えて10→9件）。

- [ ] **Step 8: コミット**

```bash
git add -A Sources/HirundoCore/Assets Sources/HirundoCore/AssetPipeline.swift Tests/HirundoTests/AssetPipelineTests.swift
git commit -m "refactor: delete the asset pipeline code no configuration could reach

Concatenation, source maps and the JS transpiler were library surface with
no path from config.yaml. The concatenation matcher disagreed with its own
file finder, no source map was generated anywhere, and transpileJS printed a
warning and returned its input unchanged."
```

---

### Task 2: `AssetManifest` — 参照解決の純粋ロジック

**Files:**
- Create: `Sources/HirundoCore/Assets/AssetManifest.swift`
- Test: `Tests/HirundoTests/AssetManifestTests.swift`

**Interfaces:**
- Consumes: なし
- Produces:
  - `AssetManifest.init(_ entries: [String: String] = [:])`
  - `subscript(key: String) -> String?`（get/set）
  - `var isEmpty: Bool`、`var outputPaths: Set<String>`、`var dictionary: [String: String]`
  - `func rewrite(reference: String, inDirectory directory: String) -> String?`
  - `static func parentDirectory(of relativePath: String) -> String`
  - `Equatable`、`Codable` 準拠

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/AssetManifestTests.swift` を新規作成する。

```swift
import XCTest
@testable import HirundoCore

final class AssetManifestTests: XCTestCase {

    private let manifest = AssetManifest([
        "css/style.css": "css/style-9f2a1c04b7e3d5a1.css",
        "images/logo.png": "images/logo-1b4d0f77c2ae8e93.png",
        "robots.txt": "robots.txt"
    ])

    // MARK: - ルート絶対参照

    func testRewritesRootRelativeReference() {
        XCTAssertEqual(
            manifest.rewrite(reference: "/css/style.css", inDirectory: ""),
            "/css/style-9f2a1c04b7e3d5a1.css"
        )
    }

    func testRootRelativeReferenceIsIndependentOfTheReferringDirectory() {
        XCTAssertEqual(
            manifest.rewrite(reference: "/css/style.css", inDirectory: "posts/hello"),
            "/css/style-9f2a1c04b7e3d5a1.css"
        )
    }

    // MARK: - 相対参照

    func testRewritesRelativeReferenceAndKeepsItRelative() {
        XCTAssertEqual(
            manifest.rewrite(reference: "../../css/style.css", inDirectory: "posts/hello"),
            "../../css/style-9f2a1c04b7e3d5a1.css"
        )
    }

    func testRewritesSiblingRelativeReference() {
        XCTAssertEqual(
            manifest.rewrite(reference: "logo.png", inDirectory: "images"),
            "logo-1b4d0f77c2ae8e93.png"
        )
    }

    func testResolvesDotSegments() {
        XCTAssertEqual(
            manifest.rewrite(reference: "./logo.png", inDirectory: "images"),
            "logo-1b4d0f77c2ae8e93.png"
        )
    }

    func testSkipsReferenceThatEscapesTheOutputRoot() {
        XCTAssertNil(manifest.rewrite(reference: "../../../etc/passwd", inDirectory: "css"))
    }

    // MARK: - クエリとフラグメント

    func testKeepsQueryString() {
        XCTAssertEqual(
            manifest.rewrite(reference: "/css/style.css?v=1", inDirectory: ""),
            "/css/style-9f2a1c04b7e3d5a1.css?v=1"
        )
    }

    func testKeepsFragment() {
        XCTAssertEqual(
            manifest.rewrite(reference: "/images/logo.png#icon", inDirectory: ""),
            "/images/logo-1b4d0f77c2ae8e93.png#icon"
        )
    }

    // MARK: - 触らない参照

    func testSkipsAbsoluteURLs() {
        XCTAssertNil(manifest.rewrite(reference: "https://cdn.example.com/css/style.css", inDirectory: ""))
        XCTAssertNil(manifest.rewrite(reference: "http://example.com/css/style.css", inDirectory: ""))
    }

    func testSkipsProtocolRelativeURLs() {
        XCTAssertNil(manifest.rewrite(reference: "//cdn.example.com/css/style.css", inDirectory: ""))
    }

    func testSkipsDataAndMailtoURLs() {
        XCTAssertNil(manifest.rewrite(reference: "data:text/css,body{}", inDirectory: ""))
        XCTAssertNil(manifest.rewrite(reference: "mailto:someone@example.com", inDirectory: ""))
    }

    func testSkipsFragmentOnlyReference() {
        XCTAssertNil(manifest.rewrite(reference: "#main", inDirectory: ""))
    }

    func testSkipsEmptyReference() {
        XCTAssertNil(manifest.rewrite(reference: "", inDirectory: ""))
    }

    func testSkipsUnknownReference() {
        XCTAssertNil(manifest.rewrite(reference: "/css/missing.css", inDirectory: ""))
    }

    func testSkipsEntryWhoseValueEqualsItsKey() {
        // フィンガープリント無効時はすべての値がキーと等しくなる。書き換えは no-op であるべき。
        XCTAssertNil(manifest.rewrite(reference: "/robots.txt", inDirectory: ""))
    }

    // MARK: - 補助

    func testParentDirectory() {
        XCTAssertEqual(AssetManifest.parentDirectory(of: "css/style.css"), "css")
        XCTAssertEqual(AssetManifest.parentDirectory(of: "a/b/c.png"), "a/b")
        XCTAssertEqual(AssetManifest.parentDirectory(of: "robots.txt"), "")
    }

    func testOutputPaths() {
        XCTAssertEqual(
            manifest.outputPaths,
            ["css/style-9f2a1c04b7e3d5a1.css", "images/logo-1b4d0f77c2ae8e93.png", "robots.txt"]
        )
    }

    func testRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(manifest)
        XCTAssertEqual(try JSONDecoder().decode(AssetManifest.self, from: data), manifest)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
swift test --filter AssetManifestTests 2>&1 | tail -20
```

Expected: コンパイルエラー `cannot find 'AssetManifest' in scope`。

- [ ] **Step 3: `AssetManifest` を実装する**

`Sources/HirundoCore/Assets/AssetManifest.swift` を新規作成する。

```swift
import Foundation

/// static ディレクトリからの相対パスを、ビルドが実際に書いた出力ディレクトリからの相対パスに
/// 対応づける。
///
/// 両辺とも相対パスで、区切りは常に `/`。フィンガープリントが無効なときはすべての値がキーと
/// 等しくなるが、マニフェストは省略せず全アセットを載せる。参照の書き換えと古い出力の掃除は
/// どちらも「マニフェストが static の出力の完全な目録である」ことに依存している。
public struct AssetManifest: Equatable, Codable {
    private var entries: [String: String]

    public init(_ entries: [String: String] = [:]) {
        self.entries = entries
    }

    public init(from decoder: Decoder) throws {
        entries = try [String: String](from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try entries.encode(to: encoder)
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// 出力ディレクトリからの相対パスの集合。掃除の「残すもの」の判定に使う。
    public var outputPaths: Set<String> { Set(entries.values) }

    public var dictionary: [String: String] { entries }

    public subscript(key: String) -> String? {
        get { entries[key] }
        set { entries[key] = newValue }
    }

    /// `directory`（出力ディレクトリからの相対ディレクトリ、ルート直下なら空文字列）にある
    /// ファイルの中で見つかった参照を書き換える。
    ///
    /// 書き換えないときは `nil` を返す。呼び出し側は元の文字列をそのまま残すこと。外部 URL、
    /// マニフェストに無い参照、値がキーと等しい参照はすべて `nil` になる。
    public func rewrite(reference: String, inDirectory directory: String) -> String? {
        let (path, suffix) = Self.splitSuffix(reference)
        guard !path.isEmpty else { return nil }
        guard !path.hasPrefix("//"), !Self.hasScheme(path) else { return nil }

        let isRootRelative = path.hasPrefix("/")
        let candidate = isRootRelative
            ? String(path.dropFirst())
            : (directory.isEmpty ? path : directory + "/" + path)

        guard let key = Self.normalize(candidate),
              let value = entries[key],
              value != key else { return nil }

        if isRootRelative {
            return "/" + value + suffix
        }
        return Self.relativePath(from: directory, to: value) + suffix
    }

    /// 相対パスの親ディレクトリ。ルート直下なら空文字列。
    public static func parentDirectory(of relativePath: String) -> String {
        var components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return "" }
        components.removeLast()
        return components.joined(separator: "/")
    }

    // MARK: - Private

    /// `a.css?v=1#x` を `("a.css", "?v=1#x")` に分ける。
    private static func splitSuffix(_ reference: String) -> (path: String, suffix: String) {
        guard let index = reference.firstIndex(where: { $0 == "?" || $0 == "#" }) else {
            return (reference, "")
        }
        return (String(reference[reference.startIndex..<index]), String(reference[index...]))
    }

    /// 最初の `/` `?` `#` より前に `:` が現れ、その前が正しいスキーム名になっているか。
    private static func hasScheme(_ path: String) -> Bool {
        for (offset, character) in path.enumerated() {
            if character == ":" { return offset > 0 }
            if character == "/" || character == "?" || character == "#" { return false }
            if offset == 0 {
                if !character.isLetter { return false }
            } else if !(character.isLetter || character.isNumber
                        || character == "+" || character == "-" || character == ".") {
                return false
            }
        }
        return false
    }

    /// `.` と `..` を解決する。出力ルートの外に出る場合は `nil`。
    private static func normalize(_ path: String) -> String? {
        var stack: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if stack.isEmpty { return nil }
                stack.removeLast()
            default:
                stack.append(String(component))
            }
        }
        return stack.isEmpty ? nil : stack.joined(separator: "/")
    }

    /// `directory` から `target` への相対パス。どちらも出力ディレクトリからの相対。
    private static func relativePath(from directory: String, to target: String) -> String {
        let from = directory.split(separator: "/").map(String.init)
        let to = target.split(separator: "/").map(String.init)
        var common = 0
        while common < from.count, common < to.count, from[common] == to[common] {
            common += 1
        }
        let ups = Array(repeating: "..", count: from.count - common)
        return (ups + to[common...]).joined(separator: "/")
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
swift test --filter AssetManifestTests 2>&1 | tail -20
```

Expected: 18件パス、0 failures。

- [ ] **Step 5: コミット**

```bash
git add Sources/HirundoCore/Assets/AssetManifest.swift Tests/HirundoTests/AssetManifestTests.swift
git commit -m "feat: add AssetManifest, which resolves a reference to its fingerprinted path

The manifest's value is now an output-relative path rather than a bare
filename, which is what a rewriter needs to reconstruct a reference."
```

---

### Task 3: `AssetReferenceRewriter` — CSS の `url(...)`

**Files:**
- Create: `Sources/HirundoCore/Assets/AssetReferenceRewriter.swift`
- Test: `Tests/HirundoTests/AssetReferenceRewriterTests.swift`

**Interfaces:**
- Consumes: `AssetManifest.rewrite(reference:inDirectory:)`
- Produces:
  - `AssetReferenceRewriter.CSSResult`（`content: String`、`unresolvedStylesheetReferences: [String]`）
  - `static func rewriteCSS(_ css: String, manifest: AssetManifest, inDirectory directory: String) -> CSSResult`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/AssetReferenceRewriterTests.swift` を新規作成する。

```swift
import XCTest
@testable import HirundoCore

final class AssetReferenceRewriterTests: XCTestCase {

    private let manifest = AssetManifest([
        "css/style.css": "css/style-9f2a1c04b7e3d5a1.css",
        "images/logo.png": "images/logo-1b4d0f77c2ae8e93.png",
        "images/bg.png": "images/bg-5c3e9a21d0f4b678.png",
        "js/app.js": "js/app-77bb1e9c4a02d3f5.js"
    ])

    // MARK: - CSS

    func testRewritesUnquotedURL() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: url(/images/bg.png); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "body { background: url(/images/bg-5c3e9a21d0f4b678.png); }")
    }

    func testRewritesDoubleQuotedURL() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: url(\"/images/bg.png\"); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "body { background: url(\"/images/bg-5c3e9a21d0f4b678.png\"); }")
    }

    func testRewritesSingleQuotedURL() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: url('/images/bg.png'); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "body { background: url('/images/bg-5c3e9a21d0f4b678.png'); }")
    }

    func testRewritesRelativeURLFromNestedStylesheet() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: url(../images/bg.png); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "body { background: url(../images/bg-5c3e9a21d0f4b678.png); }")
    }

    func testIsCaseInsensitiveAboutTheURLToken() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: URL(/images/bg.png); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "body { background: URL(/images/bg-5c3e9a21d0f4b678.png); }")
    }

    func testLeavesExternalURLAlone() {
        let css = "body { background: url(https://cdn.example.com/bg.png); }"
        XCTAssertEqual(AssetReferenceRewriter.rewriteCSS(css, manifest: manifest, inDirectory: "css").content, css)
    }

    func testLeavesDataURIAlone() {
        let css = "body { background: url(data:image/gif;base64,R0lGOD); }"
        XCTAssertEqual(AssetReferenceRewriter.rewriteCSS(css, manifest: manifest, inDirectory: "css").content, css)
    }

    func testLeavesUnknownReferenceAlone() {
        let css = "body { background: url(/images/missing.png); }"
        XCTAssertEqual(AssetReferenceRewriter.rewriteCSS(css, manifest: manifest, inDirectory: "css").content, css)
    }

    func testRewritesEveryURLInTheFile() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "a{background:url(/images/bg.png)}b{background:url(/images/logo.png)}",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertEqual(
            result.content,
            "a{background:url(/images/bg-5c3e9a21d0f4b678.png)}"
                + "b{background:url(/images/logo-1b4d0f77c2ae8e93.png)}"
        )
    }

    func testHandlesUnterminatedURLWithoutLosingContent() {
        let css = "body { background: url(/images/bg.png"
        XCTAssertEqual(AssetReferenceRewriter.rewriteCSS(css, manifest: manifest, inDirectory: "css").content, css)
    }

    // MARK: - CSS から CSS への参照

    func testReportsStylesheetReferenceItCannotResolve() {
        // パス2の時点では他の CSS はまだマニフェストに載っていない。
        let passTwoManifest = AssetManifest(["images/bg.png": "images/bg-5c3e9a21d0f4b678.png"])
        let result = AssetReferenceRewriter.rewriteCSS(
            "@import url(\"other.css\");",
            manifest: passTwoManifest,
            inDirectory: "css"
        )
        XCTAssertEqual(result.content, "@import url(\"other.css\");", "書き換えてはならない")
        XCTAssertEqual(result.unresolvedStylesheetReferences, ["other.css"])
    }

    func testDoesNotReportUnresolvedNonStylesheetReference() {
        let result = AssetReferenceRewriter.rewriteCSS(
            "body { background: url(/images/missing.png); }",
            manifest: manifest,
            inDirectory: "css"
        )
        XCTAssertTrue(result.unresolvedStylesheetReferences.isEmpty)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
swift test --filter AssetReferenceRewriterTests 2>&1 | tail -20
```

Expected: コンパイルエラー `cannot find 'AssetReferenceRewriter' in scope`。

- [ ] **Step 3: CSS の書き換えを実装する**

`Sources/HirundoCore/Assets/AssetReferenceRewriter.swift` を新規作成する。

```swift
import Foundation

/// 生成済みの HTML と CSS の中のアセット参照を、フィンガープリント済みの名前に差し替える。
///
/// この型は入力を**逐語的にコピー**し、マニフェストのキーに解決できた参照だけを差し替える。
/// HTML を構文木に読み込んで書き戻すことはしない。したがって走査が誤っても、起こり得るのは
/// 「書き換えそこねる」か「本来対象でない文字列を書き換える」だけで、無関係なバイトが壊れる
/// ことは構造上あり得ない。
public enum AssetReferenceRewriter {

    public struct CSSResult: Equatable {
        public let content: String
        /// マニフェストで解決できなかった `.css` への参照。パス2は全 CSS を同時に扱うため、
        /// CSS から CSS への `@import url(...)` はここで必ず未解決になる。呼び出し側が
        /// 警告を出すために報告する。
        public let unresolvedStylesheetReferences: [String]
    }

    /// CSS の `url(...)` を書き換える。
    public static func rewriteCSS(
        _ css: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> CSSResult {
        var result = ""
        var unresolved: [String] = []
        var index = css.startIndex

        while let token = css.range(of: "url(", options: [.caseInsensitive], range: index..<css.endIndex) {
            result += css[index..<token.upperBound]
            var cursor = token.upperBound

            while cursor < css.endIndex, css[cursor].isWhitespace {
                result.append(css[cursor])
                cursor = css.index(after: cursor)
            }
            guard cursor < css.endIndex else {
                index = cursor
                break
            }

            var quote: Character?
            if css[cursor] == "\"" || css[cursor] == "'" {
                quote = css[cursor]
                result.append(css[cursor])
                cursor = css.index(after: cursor)
            }

            let terminator = quote ?? ")"
            let valueStart = cursor
            while cursor < css.endIndex, css[cursor] != terminator {
                cursor = css.index(after: cursor)
            }
            guard cursor < css.endIndex else {
                // 閉じられていない `url(`。残りをそのまま出して終える。
                result += css[valueStart...]
                index = css.endIndex
                break
            }

            let rawValue = String(css[valueStart..<cursor])
            let reference = rawValue.trimmingCharacters(in: .whitespaces)
            if let rewritten = manifest.rewrite(reference: reference, inDirectory: directory) {
                result += rewritten
            } else {
                result += rawValue
                if isUnresolvedStylesheet(reference, manifest: manifest, inDirectory: directory) {
                    unresolved.append(reference)
                }
            }
            index = cursor
        }

        result += css[index...]
        return CSSResult(content: result, unresolvedStylesheetReferences: unresolved)
    }

    /// 書き換えられなかった参照が、ローカルの `.css` を指しているか。
    private static func isUnresolvedStylesheet(
        _ reference: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> Bool {
        let path = reference.split(separator: "?").first.map(String.init) ?? reference
        let withoutFragment = path.split(separator: "#").first.map(String.init) ?? path
        guard withoutFragment.lowercased().hasSuffix(".css") else { return false }
        guard !withoutFragment.hasPrefix("//"), !withoutFragment.contains(":") else { return false }
        return true
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
swift test --filter AssetReferenceRewriterTests 2>&1 | tail -20
```

Expected: 12件パス、0 failures。

- [ ] **Step 5: コミット**

```bash
git add Sources/HirundoCore/Assets/AssetReferenceRewriter.swift Tests/HirundoTests/AssetReferenceRewriterTests.swift
git commit -m "feat: rewrite url(...) references in CSS against the asset manifest"
```

---

### Task 4: `AssetReferenceRewriter` — HTML の属性

**Files:**
- Modify: `Sources/HirundoCore/Assets/AssetReferenceRewriter.swift`
- Test: `Tests/HirundoTests/AssetReferenceRewriterTests.swift`

**Interfaces:**
- Consumes: `AssetManifest.rewrite(reference:inDirectory:)`、`AssetReferenceRewriter.rewriteCSS`
- Produces: `static func rewriteHTML(_ html: String, manifest: AssetManifest, inDirectory directory: String) -> String`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/AssetReferenceRewriterTests.swift` の `// MARK: - CSS から CSS への参照` セクションの後、クラスの閉じ括弧の前に次を追加する。

```swift
    // MARK: - HTML

    func testRewritesLinkHref() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<link rel=\"stylesheet\" href=\"/css/style.css\">",
                manifest: manifest,
                inDirectory: ""
            ),
            "<link rel=\"stylesheet\" href=\"/css/style-9f2a1c04b7e3d5a1.css\">"
        )
    }

    func testRewritesScriptSrc() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<script src=\"/js/app.js\"></script>",
                manifest: manifest,
                inDirectory: ""
            ),
            "<script src=\"/js/app-77bb1e9c4a02d3f5.js\"></script>"
        )
    }

    func testRewritesUnquotedAttributeValue() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML("<img src=/images/logo.png>", manifest: manifest, inDirectory: ""),
            "<img src=/images/logo-1b4d0f77c2ae8e93.png>"
        )
    }

    func testRewritesRelativeReferenceFromNestedPage() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<link href=\"../../css/style.css\">",
                manifest: manifest,
                inDirectory: "posts/hello"
            ),
            "<link href=\"../../css/style-9f2a1c04b7e3d5a1.css\">"
        )
    }

    func testLeavesAnchorHrefToAPageAlone() {
        let html = "<a href=\"/about/\">About</a>"
        XCTAssertEqual(AssetReferenceRewriter.rewriteHTML(html, manifest: manifest, inDirectory: ""), html)
    }

    func testLeavesExternalHrefAlone() {
        let html = "<a href=\"https://example.com/css/style.css\">x</a>"
        XCTAssertEqual(AssetReferenceRewriter.rewriteHTML(html, manifest: manifest, inDirectory: ""), html)
    }

    func testRewritesEverySrcsetCandidateAndKeepsDescriptors() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<img srcset=\"/images/logo.png 1x, /images/bg.png 2x\">",
                manifest: manifest,
                inDirectory: ""
            ),
            "<img srcset=\"/images/logo-1b4d0f77c2ae8e93.png 1x, /images/bg-5c3e9a21d0f4b678.png 2x\">"
        )
    }

    func testRewritesURLInStyleAttribute() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<div style=\"background: url(/images/bg.png)\"></div>",
                manifest: manifest,
                inDirectory: ""
            ),
            "<div style=\"background: url(/images/bg-5c3e9a21d0f4b678.png)\"></div>"
        )
    }

    func testRewritesURLInStyleElementBody() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<style>body{background:url(/images/bg.png)}</style>",
                manifest: manifest,
                inDirectory: ""
            ),
            "<style>body{background:url(/images/bg-5c3e9a21d0f4b678.png)}</style>"
        )
    }

    func testLeavesScriptBodyAlone() {
        let html = "<script>var a = \"/images/logo.png\"; if (a<b) {}</script>"
        XCTAssertEqual(AssetReferenceRewriter.rewriteHTML(html, manifest: manifest, inDirectory: ""), html)
    }

    func testLeavesCommentsAlone() {
        let html = "<!-- <link href=\"/css/style.css\"> -->"
        XCTAssertEqual(AssetReferenceRewriter.rewriteHTML(html, manifest: manifest, inDirectory: ""), html)
    }

    func testPreservesDoctypeAndSurroundingText() {
        let html = """
        <!DOCTYPE html>
        <html><head><link href="/css/style.css"></head><body>a < b and 3 > 2</body></html>
        """
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(html, manifest: manifest, inDirectory: ""),
            html.replacingOccurrences(of: "/css/style.css", with: "/css/style-9f2a1c04b7e3d5a1.css")
        )
    }

    func testKeepsQueryStringOnAnAttribute() {
        XCTAssertEqual(
            AssetReferenceRewriter.rewriteHTML(
                "<link href=\"/css/style.css?v=2\">",
                manifest: manifest,
                inDirectory: ""
            ),
            "<link href=\"/css/style-9f2a1c04b7e3d5a1.css?v=2\">"
        )
    }

    func testDoesNotRewriteJavaScriptFilesAtAll() {
        // rewriteHTML / rewriteCSS しか公開していないので、JS は呼び出し側が対象から外す。
        // ここでは HTML として渡された JS ソースが壊れないことだけを確認する。
        let js = "fetch(\"/images/logo.png\");"
        XCTAssertEqual(AssetReferenceRewriter.rewriteHTML(js, manifest: manifest, inDirectory: ""), js)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
swift test --filter AssetReferenceRewriterTests 2>&1 | tail -20
```

Expected: コンパイルエラー `type 'AssetReferenceRewriter' has no member 'rewriteHTML'`。

- [ ] **Step 3: HTML の書き換えを実装する**

`Sources/HirundoCore/Assets/AssetReferenceRewriter.swift` の `rewriteCSS` の**前**（`CSSResult` の宣言の後）に次を追加する。

```swift
    /// アセット参照を持つ HTML 属性。`style` だけは URL ではなく CSS として扱う。
    private static let urlAttributes: Set<String> = ["href", "src"]

    /// HTML の `href` / `src` / `srcset` 属性と、`style` 属性・`<style>` 本文の `url(...)` を
    /// 書き換える。
    ///
    /// `<script>` の本文と HTML コメントは走査しない。本文中の `a<b` をタグの開始と誤認する
    /// 余地を減らすためで、同時に JS の文字列リテラルを書き換えないことも保証する。
    public static func rewriteHTML(
        _ html: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> String {
        var result = ""
        var index = html.startIndex

        while index < html.endIndex {
            guard let open = html[index...].firstIndex(of: "<") else {
                result += html[index...]
                index = html.endIndex
                break
            }
            result += html[index..<open]
            index = open

            if html[index...].hasPrefix("<!--") {
                if let close = html.range(of: "-->", range: index..<html.endIndex) {
                    result += html[index..<close.upperBound]
                    index = close.upperBound
                } else {
                    result += html[index...]
                    index = html.endIndex
                }
                continue
            }

            let afterOpen = html.index(after: index)
            guard afterOpen < html.endIndex,
                  html[afterOpen].isLetter || html[afterOpen] == "/" || html[afterOpen] == "!",
                  let close = findTagEnd(in: html, from: index) else {
                result.append("<")
                index = afterOpen
                continue
            }

            let tag = String(html[index...close])
            result += rewriteTag(tag, manifest: manifest, inDirectory: directory)
            index = html.index(after: close)

            let name = tagName(of: tag)
            guard name == "script" || name == "style" else { continue }

            if let closing = html.range(of: "</\(name)", options: [.caseInsensitive], range: index..<html.endIndex) {
                let body = String(html[index..<closing.lowerBound])
                result += name == "style"
                    ? rewriteCSS(body, manifest: manifest, inDirectory: directory).content
                    : body
                index = closing.lowerBound
            } else {
                result += html[index...]
                index = html.endIndex
            }
        }

        return result
    }

    // MARK: - HTML の走査

    /// 引用符の中の `>` を無視してタグの終わりを探す。
    private static func findTagEnd(in html: String, from start: String.Index) -> String.Index? {
        var index = start
        var quote: Character?
        while index < html.endIndex {
            let character = html[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }
            index = html.index(after: index)
        }
        return nil
    }

    /// 開始タグの名前（小文字）。終了タグや `<!DOCTYPE` では空文字列。
    private static func tagName(of tag: String) -> String {
        var index = tag.index(after: tag.startIndex)
        let start = index
        while index < tag.endIndex, tag[index].isLetter || tag[index].isNumber {
            index = tag.index(after: index)
        }
        return tag[start..<index].lowercased()
    }

    /// `<` と `>` を含むタグ1つ分を受け取り、対象の属性値だけを差し替えて返す。
    private static func rewriteTag(
        _ tag: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> String {
        var result = ""
        var index = tag.startIndex

        // `<` とタグ名を写す。
        while index < tag.endIndex, !tag[index].isWhitespace {
            result.append(tag[index])
            index = tag.index(after: index)
        }

        while index < tag.endIndex {
            if tag[index].isWhitespace || tag[index] == ">" || tag[index] == "/" {
                result.append(tag[index])
                index = tag.index(after: index)
                continue
            }

            let nameStart = index
            while index < tag.endIndex, !tag[index].isWhitespace,
                  tag[index] != "=", tag[index] != ">", tag[index] != "/" {
                index = tag.index(after: index)
            }
            let name = tag[nameStart..<index].lowercased()
            result += tag[nameStart..<index]

            guard index < tag.endIndex, tag[index] == "=" else { continue }
            result.append("=")
            index = tag.index(after: index)

            var quote: Character?
            if index < tag.endIndex, tag[index] == "\"" || tag[index] == "'" {
                quote = tag[index]
                result.append(tag[index])
                index = tag.index(after: index)
            }

            let valueStart = index
            if let open = quote {
                while index < tag.endIndex, tag[index] != open {
                    index = tag.index(after: index)
                }
            } else {
                while index < tag.endIndex, !tag[index].isWhitespace, tag[index] != ">" {
                    index = tag.index(after: index)
                }
            }

            let value = String(tag[valueStart..<index])
            result += rewriteAttributeValue(value, named: name, manifest: manifest, inDirectory: directory)

            if let open = quote, index < tag.endIndex, tag[index] == open {
                result.append(open)
                index = tag.index(after: index)
            }
        }

        return result
    }

    private static func rewriteAttributeValue(
        _ value: String,
        named name: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> String {
        if urlAttributes.contains(name) {
            return manifest.rewrite(reference: value, inDirectory: directory) ?? value
        }
        if name == "srcset" {
            return rewriteSrcset(value, manifest: manifest, inDirectory: directory)
        }
        if name == "style" {
            return rewriteCSS(value, manifest: manifest, inDirectory: directory).content
        }
        return value
    }

    /// `srcset` はカンマ区切りの候補列。各候補の先頭の URL だけを書き換え、`1.5x` や `800w`
    /// といった記述子はそのまま残す。
    private static func rewriteSrcset(
        _ value: String,
        manifest: AssetManifest,
        inDirectory directory: String
    ) -> String {
        let candidates = value.split(separator: ",", omittingEmptySubsequences: false)
        return candidates.map { candidate -> String in
            let text = String(candidate)
            let leading = String(text.prefix(while: { $0.isWhitespace }))
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return text }

            var parts = trimmed.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let url = parts.first,
                  let rewritten = manifest.rewrite(reference: url, inDirectory: directory) else {
                return text
            }
            parts[0] = rewritten
            return leading + parts.joined(separator: " ")
        }.joined(separator: ",")
    }
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
swift test --filter AssetReferenceRewriterTests 2>&1 | tail -20
```

Expected: 26件パス（CSS 12 + HTML 14）、0 failures。

- [ ] **Step 5: コミット**

```bash
git add Sources/HirundoCore/Assets/AssetReferenceRewriter.swift Tests/HirundoTests/AssetReferenceRewriterTests.swift
git commit -m "feat: rewrite href/src/srcset and inline CSS references in generated HTML"
```

---

### Task 5: `AssetPipeline` の3パス化とハッシュ対象の修正

**Files:**
- Modify: `Sources/HirundoCore/AssetPipeline.swift`
- Modify: `Sources/HirundoCore/Assets/AssetProcessor.swift`
- Modify: `Sources/HirundoCore/Assets/AssetFileManager.swift`
- Test: `Tests/HirundoTests/AssetPipelineTests.swift`

**Interfaces:**
- Consumes: `AssetManifest`、`AssetReferenceRewriter.rewriteCSS`
- Produces:
  - `AssetPipeline.processAssets(from:to:) throws -> AssetManifest`
  - `AssetPipeline.saveManifest(_ manifest: AssetManifest, to path: String) throws`
  - `AssetPipeline.loadManifest(from path: String) throws -> AssetManifest`
  - `AssetProcessor.processedData(for:type:cssOptions:jsOptions:) throws -> Data` は導入せず、`AssetPipeline` が `processor.processCSS` / `processor.processJS` を直接呼ぶ

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/AssetPipelineTests.swift` から既存の `testAssetFingerprinting` /
`testAssetManifest` / `testAssetPipelineIntegration` の3つを削除し、次の6つを追加する。

```swift
    func testAssetFingerprinting() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        pipeline.enableFingerprinting = true

        let cssFile = sourceDir.appendingPathComponent("style.css")
        let cssContent = "body { color: blue; }"
        try cssContent.write(to: cssFile, atomically: true, encoding: .utf8)

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        let fingerprintedPath = try XCTUnwrap(manifest["style.css"])
        XCTAssertTrue(fingerprintedPath.contains("-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent(fingerprintedPath).path))

        let processedContent = try String(contentsOf: destDir.appendingPathComponent(fingerprintedPath), encoding: .utf8)
        XCTAssertEqual(processedContent, cssContent)
    }

    func testManifestValueKeepsItsDirectory() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent("css"),
            withIntermediateDirectories: true
        )
        pipeline.enableFingerprinting = true
        try "body{}".write(to: sourceDir.appendingPathComponent("css/style.css"), atomically: true, encoding: .utf8)

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        let value = try XCTUnwrap(manifest["css/style.css"])
        XCTAssertTrue(value.hasPrefix("css/"), "値は出力相対パスであるべき。実際: \(value)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.appendingPathComponent(value).path))
    }

    func testManifestIsCompleteWithoutFingerprinting() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "body{}".write(to: sourceDir.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        try Data().write(to: sourceDir.appendingPathComponent("logo.png"))

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        XCTAssertEqual(manifest["style.css"], "style.css")
        XCTAssertEqual(manifest["logo.png"], "logo.png")
    }

    func testManifestRoundTripsThroughDisk() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent("css"),
            withIntermediateDirectories: true
        )
        pipeline.enableFingerprinting = true
        try "body{}".write(to: sourceDir.appendingPathComponent("css/style.css"), atomically: true, encoding: .utf8)

        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        let path = destDir.appendingPathComponent("asset-manifest.json").path
        try pipeline.saveManifest(manifest, to: path)

        XCTAssertEqual(try pipeline.loadManifest(from: path), manifest)
    }

    func testFingerprintCoversTheProcessedBytesNotTheSource() throws {
        // 同じソースを、最小化あり・なしで別々の出力に処理する。ハッシュが処理後のバイト列に
        // 対して取られていれば、ふたつの出力名は違うものになる。
        let sourceDir = tempDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try "body {\n  color: red;\n}\n".write(
            to: sourceDir.appendingPathComponent("style.css"),
            atomically: true,
            encoding: .utf8
        )

        let plain = AssetPipeline()
        plain.enableFingerprinting = true
        let plainManifest = try plain.processAssets(
            from: sourceDir.path,
            to: tempDir.appendingPathComponent("dest-plain").path
        )

        let minified = AssetPipeline()
        minified.enableFingerprinting = true
        minified.cssOptions.minify = true
        let minifiedManifest = try minified.processAssets(
            from: sourceDir.path,
            to: tempDir.appendingPathComponent("dest-minified").path
        )

        XCTAssertNotEqual(
            plainManifest["style.css"],
            minifiedManifest["style.css"],
            "最小化でバイト列が変わったのにハッシュが同じなのは、ソースをハッシュしている証拠"
        )
    }

    func testCSSHashCoversTheRewrittenBytes() throws {
        // CSS が参照する画像の中身だけを変える。画像のハッシュが変われば、書き換え後の CSS の
        // バイト列も変わり、CSS 自身のハッシュも変わらなければならない。
        func build(imageBytes: Data, into name: String) throws -> AssetManifest {
            let sourceDir = tempDir.appendingPathComponent("source-\(name)")
            try FileManager.default.createDirectory(
                at: sourceDir.appendingPathComponent("css"),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: sourceDir.appendingPathComponent("images"),
                withIntermediateDirectories: true
            )
            try "body{background:url(../images/bg.png)}".write(
                to: sourceDir.appendingPathComponent("css/style.css"),
                atomically: true,
                encoding: .utf8
            )
            try imageBytes.write(to: sourceDir.appendingPathComponent("images/bg.png"))

            let pipeline = AssetPipeline()
            pipeline.enableFingerprinting = true
            return try pipeline.processAssets(
                from: sourceDir.path,
                to: tempDir.appendingPathComponent("dest-\(name)").path
            )
        }

        let first = try build(imageBytes: Data("one".utf8), into: "first")
        let second = try build(imageBytes: Data("two".utf8), into: "second")

        XCTAssertNotEqual(first["images/bg.png"], second["images/bg.png"], "前提: 画像のハッシュは変わる")
        XCTAssertNotEqual(
            first["css/style.css"],
            second["css/style.css"],
            "CSS のハッシュは url(...) を書き換えた後のバイト列に対して取られるべき"
        )
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
swift test --filter AssetPipelineTests 2>&1 | tail -30
```

Expected: `testManifestValueKeepsItsDirectory` が「値が `css/` で始まらない」で失敗、`testFingerprintCoversTheProcessedBytesNotTheSource` と `testCSSHashCoversTheRewrittenBytes` がハッシュ一致で失敗、`testManifestIsCompleteWithoutFingerprinting` が nil で失敗。

- [ ] **Step 3: `AssetProcessor` から「書き込む API」を外す**

`Sources/HirundoCore/Assets/AssetProcessor.swift` から `processAssetContent(_:cssOptions:jsOptions:)`、`processCSSThroughPipeline(_:options:)`、`processJSThroughPipeline(_:options:)` の3つを削除する。`processCSS` / `processJS` / `generateFingerprint` / `addFingerprint` / `detectAssetType` は残す。

- [ ] **Step 4: `AssetPipeline` を3パス構成に書き換える**

`Sources/HirundoCore/AssetPipeline.swift` の `processAssets` 以降を次で置き換える。

```swift
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
```

- [ ] **Step 5: `AssetFileManager` のマニフェスト保存を新しい型に合わせる**

```swift
    /// Saves manifest to file
    public func saveManifest(_ manifest: AssetManifest, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Loads manifest from file
    public func loadManifest(from path: String) throws -> AssetManifest {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(AssetManifest.self, from: data)
    }
```

- [ ] **Step 6: 既存テストのマニフェスト参照を直す**

`Tests/HirundoTests/AssetPipelineTests.swift` の `testAssetPipelineIntegration` は Step 1 で削除済み。残る `testBasicAssetCopy` / `testDirectoryStructurePreservation` / `testAssetTypeDetection` / `testAssetMinification` / `testImageOptimization` / `testAssetFiltering` は戻り値を捨てているのでそのまま通る。`manifest.count` を使っている箇所が残っていれば `manifest.dictionary.count` に直す。

- [ ] **Step 7: ビルドとテストが通ることを確認する**

```bash
swift build 2>&1 | tail -20
swift test --filter AssetPipelineTests 2>&1 | tail -20
```

Expected: ビルド成功、`AssetPipelineTests` が12件（Task 1 後の9件 − 3件 + 6件）パス、0 failures。

- [ ] **Step 8: コミット**

```bash
git add Sources/HirundoCore/AssetPipeline.swift Sources/HirundoCore/Assets Tests/HirundoTests/AssetPipelineTests.swift
git commit -m "fix: hash an asset's final output bytes, not its source bytes

The fingerprint hashed the source and wrote the processed bytes, so the hash
did not identify what it named. Processing now runs in two passes: everything
but CSS first, then CSS, whose bytes only settle once url(...) has been
rewritten against the manifest the first pass produced.

The manifest's value is an output-relative path rather than a bare filename,
and every asset is listed even when fingerprinting is off."
```

---

### Task 6: `AssetPruner` — 古い出力の削除

**Files:**
- Create: `Sources/HirundoCore/Assets/AssetPruner.swift`
- Test: `Tests/HirundoTests/AssetPrunerTests.swift`

**Interfaces:**
- Consumes: `AssetManifest.outputPaths`
- Produces:
  - `AssetPruner.isFingerprintedName(_ name: String) -> Bool`
  - `AssetPruner.prune(outputDirectory:staticDirectory:keeping:fileManager:) throws`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/AssetPrunerTests.swift` を新規作成する。

```swift
import XCTest
@testable import HirundoCore

final class AssetPrunerTests: XCTestCase {

    private var tempDir: URL!
    private var outputDir: URL!
    private var staticDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("asset-pruner-test-\(UUID().uuidString)")
        outputDir = tempDir.appendingPathComponent("_site")
        staticDir = tempDir.appendingPathComponent("static")
        try? FileManager.default.createDirectory(at: staticDir.appendingPathComponent("css"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: outputDir.appendingPathComponent("css"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func write(_ contents: String, to relativePath: String, under root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(relativePath).path)
    }

    // MARK: - 名前の判定

    func testRecognizesFingerprintedNames() {
        XCTAssertTrue(AssetPruner.isFingerprintedName("style-9f2a1c04b7e3d5a1.css"))
        XCTAssertTrue(AssetPruner.isFingerprintedName("my-logo-1b4d0f77c2ae8e93.png"))
    }

    func testRejectsNonFingerprintedNames() {
        XCTAssertFalse(AssetPruner.isFingerprintedName("style.css"))
        XCTAssertFalse(AssetPruner.isFingerprintedName("index.html"))
        XCTAssertFalse(AssetPruner.isFingerprintedName("sitemap.xml"))
        XCTAssertFalse(AssetPruner.isFingerprintedName("my-logo.png"), "ハッシュが16桁でない")
        XCTAssertFalse(AssetPruner.isFingerprintedName("style-9F2A1C04B7E3D5A1.css"), "大文字は使わない")
        XCTAssertFalse(AssetPruner.isFingerprintedName("style-9f2a1c04b7e3d5a1"), "拡張子が無い")
        XCTAssertFalse(AssetPruner.isFingerprintedName("style-zzzzzzzzzzzzzzzz.css"), "16進数でない")
    }

    // MARK: - 削除

    func testRemovesStaleFingerprintedAsset() throws {
        try write("old", to: "css/style-0000000000000000.css", under: outputDir)
        try write("new", to: "css/style-9f2a1c04b7e3d5a1.css", under: outputDir)

        try AssetPruner.prune(
            outputDirectory: outputDir,
            staticDirectory: staticDir,
            keeping: AssetManifest(["css/style.css": "css/style-9f2a1c04b7e3d5a1.css"])
        )

        XCTAssertFalse(exists("css/style-0000000000000000.css"))
        XCTAssertTrue(exists("css/style-9f2a1c04b7e3d5a1.css"))
    }

    func testKeepsNonFingerprintedFilesInScope() throws {
        try write("keep", to: "css/README.txt", under: outputDir)

        try AssetPruner.prune(
            outputDirectory: outputDir,
            staticDirectory: staticDir,
            keeping: AssetManifest()
        )

        XCTAssertTrue(exists("css/README.txt"))
    }

    func testKeepsPageOutputThatCollidesWithAStaticTopLevelName() throws {
        // content/css/foo.md が _site/css/foo/index.html を生む場合。フィンガープリント名では
        // ないので、掃除の対象にならない。
        try write("<html></html>", to: "css/foo/index.html", under: outputDir)

        try AssetPruner.prune(
            outputDirectory: outputDir,
            staticDirectory: staticDir,
            keeping: AssetManifest()
        )

        XCTAssertTrue(exists("css/foo/index.html"))
    }

    func testDoesNotTouchAnythingOutsideStaticTopLevelNames() throws {
        try write("<html></html>", to: "index.html", under: outputDir)
        try write("<urlset/>", to: "sitemap.xml", under: outputDir)
        // static/ に posts/ は無いので、_site/posts は対象外。
        try write("stale", to: "posts/orphan-0000000000000000.css", under: outputDir)

        try AssetPruner.prune(
            outputDirectory: outputDir,
            staticDirectory: staticDir,
            keeping: AssetManifest()
        )

        XCTAssertTrue(exists("index.html"))
        XCTAssertTrue(exists("sitemap.xml"))
        XCTAssertTrue(exists("posts/orphan-0000000000000000.css"))
    }

    func testPrunesATopLevelFileFromStatic() throws {
        try "User-agent: *".write(to: staticDir.appendingPathComponent("robots.txt"), atomically: true, encoding: .utf8)
        try write("stale", to: "robots-0000000000000000.txt", under: outputDir)

        try AssetPruner.prune(
            outputDirectory: outputDir,
            staticDirectory: staticDir,
            keeping: AssetManifest(["robots.txt": "robots-9f2a1c04b7e3d5a1.txt"])
        )

        XCTAssertFalse(exists("robots-0000000000000000.txt"))
    }
}
```

`testPrunesATopLevelFileFromStatic` は、static のトップレベル**ファイル**（`robots.txt`）が
出力ではフィンガープリント名（`robots-<hash>.txt`）になるため、スコープの判定をファイル名の
完全一致ではなく「static のトップレベル名から拡張子を除いた語幹で始まる出力ルート直下の
ファイル」で行う必要があることを示す。実装は Step 3 でこれを満たすこと。

- [ ] **Step 2: テストが失敗することを確認する**

```bash
swift test --filter AssetPrunerTests 2>&1 | tail -20
```

Expected: コンパイルエラー `cannot find 'AssetPruner' in scope`。

- [ ] **Step 3: `AssetPruner` を実装する**

`Sources/HirundoCore/Assets/AssetPruner.swift` を新規作成する。

```swift
import Foundation

/// 出力ツリーから、今回のビルドが生成しなかったフィンガープリント済みアセットを取り除く。
///
/// `hirundo serve` は clean せずに再ビルドするため、これが無いとハッシュ名の出力が世代ごとに
/// 積み上がっていく。
///
/// 削除するのは次の3つを**すべて**満たすファイルだけ。
///
/// 1. `static/` のトップレベル要素に対応する出力の範囲にあること
/// 2. 名前がフィンガープリント形（`<name>-<16桁の小文字16進数>.<ext>`）であること
/// 3. 現在のマニフェストの値に含まれないこと
///
/// 条件2があるため、`content/css/foo.md` が `_site/css/foo/index.html` を生むようなパスの
/// 衝突があってもページ出力を消すことは構造上あり得ない。
public enum AssetPruner {

    /// `<name>-<16桁の小文字16進数>.<ext>` か。
    public static func isFingerprintedName(_ name: String) -> Bool {
        let url = URL(fileURLWithPath: name)
        guard !url.pathExtension.isEmpty else { return false }

        let stem = url.deletingPathExtension().lastPathComponent
        guard let dash = stem.lastIndex(of: "-") else { return false }

        let hash = stem[stem.index(after: dash)...]
        guard hash.count == 16 else { return false }
        return hash.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    public static func prune(
        outputDirectory: URL,
        staticDirectory: URL,
        keeping manifest: AssetManifest,
        fileManager: FileManager = .default
    ) throws {
        let keep = manifest.outputPaths
        let topLevel = (try? fileManager.contentsOfDirectory(atPath: staticDirectory.path)) ?? []

        for entry in topLevel {
            var isDirectory: ObjCBool = false
            let sourceEntry = staticDirectory.appendingPathComponent(entry)
            guard fileManager.fileExists(atPath: sourceEntry.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                let scope = outputDirectory.appendingPathComponent(entry)
                guard fileManager.fileExists(atPath: scope.path),
                      let walker = fileManager.enumerator(
                        at: scope,
                        includingPropertiesForKeys: [.isRegularFileKey]
                      ) else { continue }

                for case let fileURL as URL in walker {
                    guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                    else { continue }
                    try pruneIfStale(fileURL, outputDirectory: outputDirectory, keep: keep, fileManager: fileManager)
                }
            } else {
                // トップレベルのファイルは出力でハッシュ名になっているので、名前の完全一致では
                // 見つからない。語幹が一致する出力ルート直下のファイルを候補にする。
                let stem = URL(fileURLWithPath: entry).deletingPathExtension().lastPathComponent
                let siblings = (try? fileManager.contentsOfDirectory(atPath: outputDirectory.path)) ?? []
                for sibling in siblings where sibling.hasPrefix(stem + "-") {
                    try pruneIfStale(
                        outputDirectory.appendingPathComponent(sibling),
                        outputDirectory: outputDirectory,
                        keep: keep,
                        fileManager: fileManager
                    )
                }
            }
        }
    }

    private static func pruneIfStale(
        _ fileURL: URL,
        outputDirectory: URL,
        keep: Set<String>,
        fileManager: FileManager
    ) throws {
        guard isFingerprintedName(fileURL.lastPathComponent) else { return }
        guard let relativePath = relativePath(of: fileURL, under: outputDirectory) else { return }
        guard !keep.contains(relativePath) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private static func relativePath(of fileURL: URL, under root: URL) -> String? {
        let filePath = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
swift test --filter AssetPrunerTests 2>&1 | tail -20
```

Expected: 7件パス、0 failures。

- [ ] **Step 5: コミット**

```bash
git add Sources/HirundoCore/Assets/AssetPruner.swift Tests/HirundoTests/AssetPrunerTests.swift
git commit -m "feat: remove stale fingerprinted assets from the output tree

serve rebuilds without cleaning, so without this the output accumulates one
hashed copy of every asset per edit. Only names of the shape
<name>-<16 hex>.<ext> under a static-derived path are eligible, which is why
a page output can never be deleted."
```

---

### Task 7: `features.fingerprint` の設定面

**Files:**
- Modify: `Sources/HirundoCore/Models/Features.swift`
- Modify: `Sources/HirundoCore/Scaffold/ScaffoldTemplates.swift`
- Test: `Tests/HirundoTests/ConfigDecodingTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `Features.fingerprint: Bool`（デフォルト `false`）、`Features.init(sitemap:rss:searchIndex:minify:fingerprint:)`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/ConfigDecodingTests.swift` の末尾（クラスの閉じ括弧の前）に次を追加する。

```swift
    func testFingerprintDefaultsToOff() throws {
        let yaml = """
        site:
          title: "Test"
          url: "https://example.com"
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertFalse(config.features.fingerprint)
    }

    func testFingerprintCanBeEnabledOnItsOwn() throws {
        let yaml = """
        site:
          title: "Test"
          url: "https://example.com"

        features:
          fingerprint: true
        """
        let config = try HirundoConfig.parse(from: yaml)
        XCTAssertTrue(config.features.fingerprint)
        XCTAssertFalse(config.features.sitemap, "他のフラグは既定の false のまま")
    }

    func testValidateDoesNotWarnAboutFingerprint() throws {
        let yaml = """
        site:
          title: "Test"
          url: "https://example.com"

        features:
          fingerprint: true
        """
        let report = try ConfigDiagnostics.inspect(yaml: yaml)
        XCTAssertFalse(
            report.warnings.contains { $0.contains("fingerprint") },
            "既知のキーなので警告してはならない: \(report.warnings)"
        )
    }
```

`HirundoConfig.parse` と `ConfigDiagnostics.inspect(yaml:)` の正確な名前は
`Tests/HirundoTests/ConfigDecodingTests.swift` と `Tests/HirundoTests/ConfigDiagnosticsTests.swift`
の既存テストに合わせること。

- [ ] **Step 2: テストが失敗することを確認する**

```bash
swift test --filter ConfigDecodingTests 2>&1 | tail -20
```

Expected: コンパイルエラー `value of type 'Features' has no member 'fingerprint'`。

- [ ] **Step 3: `Features` にフラグを足す**

`Sources/HirundoCore/Models/Features.swift` を次で置き換える。

```swift
import Foundation

/// Built-in feature toggles (stage 1: internalize plugins as features)
public struct Features: Codable, Sendable, Equatable {
    public var sitemap: Bool
    public var rss: Bool
    public var searchIndex: Bool
    public var minify: Bool
    /// アセットに内容ハッシュを付け、HTML と CSS の参照をそのハッシュ名に書き換える。
    public var fingerprint: Bool

    public init(
        sitemap: Bool = false,
        rss: Bool = false,
        searchIndex: Bool = false,
        minify: Bool = false,
        fingerprint: Bool = false
    ) {
        self.sitemap = sitemap
        self.rss = rss
        self.searchIndex = searchIndex
        self.minify = minify
        self.fingerprint = fingerprint
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case sitemap, rss, searchIndex, minify, fingerprint
    }

    /// Decodes every flag independently, defaulting to off.
    ///
    /// The synthesized decoder would require all keys, so `features:` with a single flag
    /// under it failed the whole configuration parse. Every other optional block (`build`,
    /// `server`, `blog`, `limits`) defaults its missing keys, and so does this one.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sitemap = try container.decodeIfPresent(Bool.self, forKey: .sitemap) ?? false
        self.rss = try container.decodeIfPresent(Bool.self, forKey: .rss) ?? false
        self.searchIndex = try container.decodeIfPresent(Bool.self, forKey: .searchIndex) ?? false
        self.minify = try container.decodeIfPresent(Bool.self, forKey: .minify) ?? false
        self.fingerprint = try container.decodeIfPresent(Bool.self, forKey: .fingerprint) ?? false
    }
}
```

`ConfigDiagnostics` は鍵集合を `Features.CodingKeys.allCases` から導出しているので、
`hirundo validate` 側の変更は要らない。

- [ ] **Step 4: `hirundo init` の生成する config に足す**

`Sources/HirundoCore/Scaffold/ScaffoldTemplates.swift` の `features:` ブロックを次にする。

```
        features:
          sitemap: true
          rss: \(blogFlag)
          searchIndex: false
          minify: false
          fingerprint: false
```

- [ ] **Step 5: テストが通ることを確認する**

```bash
swift test --filter ConfigDecodingTests 2>&1 | tail -20
swift test --filter SiteScaffolderTests 2>&1 | tail -20
```

Expected: 両方とも全件パス。`SiteScaffolderTests` が生成 config の中身を文字列で照合していたら、
`fingerprint: false` の行を期待値に足す。

- [ ] **Step 6: コミット**

```bash
git add Sources/HirundoCore/Models/Features.swift Sources/HirundoCore/Scaffold/ScaffoldTemplates.swift Tests/HirundoTests/ConfigDecodingTests.swift
git commit -m "feat: add the features.fingerprint flag"
```

---

### Task 8: `SiteGenerator` の配線

**Files:**
- Modify: `Sources/HirundoCore/SiteGenerator.swift`
- Test: `Tests/HirundoTests/BuildWithRecoveryCompletenessTests.swift`

**Interfaces:**
- Consumes: `AssetPipeline.processAssets`、`AssetPruner.prune`、`AssetReferenceRewriter.rewriteHTML` / `rewriteCSS`、`Features.fingerprint`
- Produces: `finalizationSteps` に `"asset references"` という名前のステップ

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/BuildWithRecoveryCompletenessTests.swift` の `setUp` の `config` から
`features:` ブロックを消し、代わりに各テストが自分で config を書けるようにする……のではなく、
既存の `setUp` はそのままに、次のテストをクラス末尾に追加する。テンプレートに CSS への参照が
必要なので、テスト内で上書きする。

```swift
    func testRecoveryBuildRewritesAssetReferencesWhenFingerprintingIsOn() async throws {
        let config = """
        site:
          title: "Recovery Site"
          url: "https://example.com"

        features:
          fingerprint: true
        """
        try write(config, to: "config.yaml")
        try write("""
        <!DOCTYPE html>
        <html><head><link rel="stylesheet" href="/css/style.css"></head><body>{{ content }}</body></html>
        """, to: "templates/default.html")

        let generator = try SiteGenerator(projectPath: projectPath)
        let result = try await generator.buildWithRecovery()
        XCTAssertTrue(result.success, "Build reported failures: \(result.errors)")

        let html = try String(contentsOf: outputURL.appendingPathComponent("index.html"), encoding: .utf8)
        XCTAssertFalse(html.contains("/css/style.css"), "元のパスが残っている: \(html)")

        // 書き換え先が実在すること。これが今まさに壊れている挙動。
        let manifest = try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: outputURL.appendingPathComponent("asset-manifest.json"))
        )
        let fingerprinted = try XCTUnwrap(manifest["css/style.css"])
        XCTAssertTrue(html.contains("/" + fingerprinted), "書き換え後のパスが HTML に無い: \(html)")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent(fingerprinted).path),
            "HTML が実在しないファイルを指している"
        )
    }

    func testRepeatedRebuildKeepsOnlyOneGenerationOfEachAsset() async throws {
        let config = """
        site:
          title: "Recovery Site"
          url: "https://example.com"

        features:
          fingerprint: true
        """
        try write(config, to: "config.yaml")

        let generator = try SiteGenerator(projectPath: projectPath)
        _ = try await generator.buildWithRecovery()

        try write("body { color: blue; }\n", to: "static/css/style.css")
        _ = try await generator.buildWithRecovery()

        let cssFiles = try FileManager.default
            .contentsOfDirectory(atPath: outputURL.appendingPathComponent("css").path)
            .filter { $0.hasSuffix(".css") }
        XCTAssertEqual(cssFiles.count, 1, "古い世代が残っている: \(cssFiles)")
    }

    func testFingerprintingIsOffByDefault() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)
        _ = try await generator.buildWithRecovery()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("css/style.css").path),
            "既定ではハッシュを付けない"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("asset-manifest.json").path),
            "既定ではマニフェストを書かない"
        )
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
swift test --filter BuildWithRecoveryCompletenessTests 2>&1 | tail -30
```

Expected: `testRecoveryBuildRewritesAssetReferencesWhenFingerprintingIsOn` が
「元のパスが残っている」で失敗。

- [ ] **Step 3: マニフェストを保持し、prune を呼ぶ**

`Sources/HirundoCore/SiteGenerator.swift` のプロパティ宣言（`private let assetPipeline: AssetPipeline` の下）に追加する。

```swift
    /// 直近の `processStaticAssets` が作ったマニフェスト。`asset references` ステップが読む。
    private var assetManifest = AssetManifest()
```

`processStaticAssets` を次で置き換える。

```swift
    private func processStaticAssets(outputURL: URL) throws {
        let staticURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(config.build.staticDirectory)

        guard siteFileManager.fileExists(at: staticURL.path) else {
            assetManifest = AssetManifest()
            return
        }

        configureAssetPipeline()

        let manifest = try assetPipeline.processAssets(
            from: staticURL.path,
            to: outputURL.path
        )
        assetManifest = manifest

        guard config.features.fingerprint else { return }

        // 前の世代のハッシュ名の出力を落とす。serve は clean せずに再ビルドする。
        try AssetPruner.prune(
            outputDirectory: outputURL,
            staticDirectory: staticURL,
            keeping: manifest
        )

        try assetPipeline.saveManifest(
            manifest,
            to: outputURL.appendingPathComponent("asset-manifest.json").path
        )
    }

    private func configureAssetPipeline() {
        if config.features.minify {
            assetPipeline.cssOptions.minify = true
            assetPipeline.jsOptions.minify = true
        }
        assetPipeline.enableFingerprinting = config.features.fingerprint
    }
```

- [ ] **Step 4: `asset references` ステップを足す**

`finalizationSteps` の中、`var steps: [FinalizationStep] = [ ... ]` の閉じ括弧の直後、
`if config.features.sitemap {` の**前**に挿入する。

```swift
        if config.features.fingerprint {
            steps.append(FinalizationStep(name: "asset references") {
                try self.rewriteAssetReferences(outputURL: outputURL)
            })
        }
```

- [ ] **Step 5: 書き換えステップの本体を実装する**

`processStaticAssets` の直後に追加する。

```swift
    /// 出力ツリーの HTML（と、パイプラインが作ったのではない CSS）の参照を、フィンガープリント
    /// 済みの名前に差し替える。
    ///
    /// アセットパイプライン自身が生成したファイルは**書き換えない**。書き換えるとパス2で確定した
    /// ハッシュがその中身を指さなくなる。具体的には、この時点ではマニフェストに全 CSS が載って
    /// いるため、パス2で解決を見送った `@import url("other.css")` がここで解決してしまう。
    private func rewriteAssetReferences(outputURL: URL) throws {
        let manifest = assetManifest
        guard !manifest.isEmpty else { return }
        let generated = manifest.outputPaths

        guard let walker = FileManager.default.enumerator(
            at: outputURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in walker {
            try Task.checkCancellation()
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }

            let ext = fileURL.pathExtension.lowercased()
            guard ext == "html" || ext == "htm" || ext == "css" else { continue }

            guard let relativePath = Self.outputRelativePath(of: fileURL, under: outputURL),
                  !generated.contains(relativePath) else { continue }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let directory = AssetManifest.parentDirectory(of: relativePath)
            let rewritten = ext == "css"
                ? AssetReferenceRewriter.rewriteCSS(content, manifest: manifest, inDirectory: directory).content
                : AssetReferenceRewriter.rewriteHTML(content, manifest: manifest, inDirectory: directory)

            guard rewritten != content else { continue }
            try siteFileManager.writeFile(content: rewritten, to: fileURL)
        }
    }

    /// 出力ディレクトリからの相対パス。出力の外なら `nil`。
    private static func outputRelativePath(of fileURL: URL, under root: URL) -> String? {
        let filePath = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }
```

- [ ] **Step 6: テストが通ることを確認する**

```bash
swift build 2>&1 | tail -20
swift test --filter BuildWithRecoveryCompletenessTests 2>&1 | tail -20
```

Expected: 全件パス。

- [ ] **Step 7: コミット**

```bash
git add Sources/HirundoCore/SiteGenerator.swift Tests/HirundoTests/BuildWithRecoveryCompletenessTests.swift
git commit -m "feat: rewrite asset references in the built site

Adds an 'asset references' finalization step, so both hirundo build and every
hirundo serve rebuild leave the generated HTML pointing at files that exist.
The step is only added when features.fingerprint is on, and it skips the files
the asset pipeline itself hashed."
```

---

### Task 9: 統合テスト

**Files:**
- Create: `Tests/HirundoTests/AssetFingerprintIntegrationTests.swift`

**Interfaces:**
- Consumes: `SiteGenerator.build(clean:includeDrafts:environment:)`
- Produces: なし

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/AssetFingerprintIntegrationTests.swift` を新規作成する。

```swift
import XCTest
@testable import HirundoCore

/// `hirundo build` の出力を、ブラウザが見るのと同じ目で確かめる。
///
/// フィンガープリントの本当の合格条件はハッシュが付くことではなく、**生成された HTML が実在
/// するファイルを指していること**である。これが長らく壊れていた。
final class AssetFingerprintIntegrationTests: XCTestCase {

    private var tempDirectory: URL!
    private var projectPath: String!
    private var outputURL: URL!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hirundo-fingerprint-\(UUID().uuidString)")
        projectPath = tempDirectory.path
        outputURL = tempDirectory.appendingPathComponent("_site")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        try write("""
        site:
          title: "Fingerprint Site"
          url: "https://example.com"

        features:
          fingerprint: true
          minify: true
        """, to: "config.yaml")

        try write("""
        <!DOCTYPE html>
        <html>
        <head><link rel="stylesheet" href="/css/style.css"></head>
        <body>
          <img src="/images/logo.png" alt="logo">
          <script src="/js/app.js"></script>
          {{ content }}
        </body>
        </html>
        """, to: "templates/default.html")

        try write("---\ntitle: Home\n---\n# Home\n", to: "content/index.md")
        try write("---\ntitle: Deep\n---\n# Deep\n", to: "content/guides/deep.md")

        try write("body{background:url(../images/logo.png)}", to: "static/css/style.css")
        try write("console.log('hi');", to: "static/js/app.js")
        try write("not really a png", to: "static/images/logo.png")
    }

    override func tearDown() async throws {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    private func write(_ contents: String, to relativePath: String) throws {
        let url = tempDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func manifest() throws -> [String: String] {
        try JSONDecoder().decode(
            [String: String].self,
            from: Data(contentsOf: outputURL.appendingPathComponent("asset-manifest.json"))
        )
    }

    /// HTML と CSS のローカルなアセット参照が、出力に実在するファイルを指しているか。
    ///
    /// ルート絶対（`/css/x.css`）と、そのファイルからの相対（`../images/x.png`）の両方を辿る。
    private func assertEveryReferenceResolves(in relativePath: String) throws {
        let fileURL = outputURL.appendingPathComponent(relativePath)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"(?:href|src)="([^"]+)"|url\(([^)"']+)\)"#)
        let range = NSRange(content.startIndex..., in: content)
        let directory = fileURL.deletingLastPathComponent()

        var checked = 0
        for match in regex.matches(in: content, range: range) {
            for group in 1...2 {
                guard let r = Range(match.range(at: group), in: content) else { continue }
                let reference = String(content[r]).trimmingCharacters(in: .whitespaces)
                guard reference.hasSuffix(".css") || reference.hasSuffix(".js") || reference.hasSuffix(".png")
                else { continue }
                guard !reference.contains(":"), !reference.hasPrefix("//") else { continue }

                let target = reference.hasPrefix("/")
                    ? outputURL.appendingPathComponent(String(reference.dropFirst()))
                    : directory.appendingPathComponent(reference).standardizedFileURL
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: target.path),
                    "\(relativePath) が実在しない \(reference) を指している"
                )
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0, "\(relativePath) に検査対象の参照が無い")
    }

    func testBuiltSiteOnlyReferencesFilesThatExist() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build()

        try assertEveryReferenceResolves(in: "index.html")
        try assertEveryReferenceResolves(in: "guides/deep/index.html")

        let stylesheet = try XCTUnwrap(manifest()["css/style.css"])
        try assertEveryReferenceResolves(in: stylesheet)
    }

    func testEveryAssetIsFingerprinted() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build()

        let manifest = try manifest()
        for key in ["css/style.css", "js/app.js", "images/logo.png"] {
            let value = try XCTUnwrap(manifest[key], "\(key) がマニフェストに無い")
            XCTAssertNotEqual(value, key, "\(key) にハッシュが付いていない")
            XCTAssertTrue(AssetPruner.isFingerprintedName(URL(fileURLWithPath: value).lastPathComponent))
        }
    }

    func testCleanBuildLeavesNoUnfingerprintedAssetBehind() async throws {
        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build(clean: true)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("css/style.css").path),
            "ハッシュ無しの名前でも出力されている"
        )
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
swift test --filter AssetFingerprintIntegrationTests 2>&1 | tail -30
```

Expected: Task 1〜8 が済んでいれば全件パスする。失敗する場合は、そのタスクの実装に穴がある。

- [ ] **Step 3: 失敗した項目を直す**

失敗が出た場合は、該当する Task の実装に戻って直す。統合テストの期待値を緩めてはならない。

- [ ] **Step 4: 全テストを走らせる**

```bash
swift test 2>&1 | grep -E "Executed [0-9]+ tests|error:" | tail -5
```

Expected: `0 failures`。

- [ ] **Step 5: コミット**

```bash
git add Tests/HirundoTests/AssetFingerprintIntegrationTests.swift
git commit -m "test: assert the built site only references files that exist"
```

---

### Task 10: ドキュメント更新

**Files:**
- Modify: `Sources/HirundoCore/AssetPipeline.swift`（クラスのドキュメントコメント）
- Modify: `README.ja.md`
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: なし
- Produces: なし

- [ ] **Step 1: `AssetPipeline` のドキュメントコメントを最終版にする**

Task 1 で置いた暫定コメントを次で置き換える。

```swift
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
```

- [ ] **Step 2: `README.ja.md` の「未実装の項目」を書き直す**

「アセットのフィンガープリント、ソースマップ、JS/CSSの結合」の項目を削除し、代わりに次を置く。

```markdown
- **アセットの結合とソースマップ**。JS/CSSの結合とソースマップ生成は削除されました。
  結合は `AssetConcatenator` ごと、ソースマップは `sourceMap` オプションごと消えています。
  JSのトランスパイル（`transpile` / `target`）も同様です。ES6+の変換には Babel や esbuild を
  使ってください。
```

`features` の表（`minify` の行の後）に次を追加する。

```markdown
| `fingerprint` | アセット名に内容ハッシュを付け、HTMLとCSSの参照を書き換えます |
```

`minify` の説明の後に、`fingerprint` の説明と制限を追加する。

```markdown
`fingerprint` を有効にすると、`static/` のアセットは `style-9f2a1c04b7e3d5a1.css` のような
内容ハッシュ付きの名前で出力され、生成されたHTMLの `href` / `src` / `srcset`、CSSの `url(...)`、
`<style>` の本文と `style` 属性がその名前を指すように書き換えられます。対応表は
`_site/asset-manifest.json` に書き出されます。古い世代のハッシュ名のファイルはビルドのたびに
削除されるため、`hirundo serve` を回し続けても出力が膨れません。

制限が2つあります。

- **JavaScript内の参照は書き換えません。** `fetch("/images/logo.png")` のような文字列が参照
  かどうかは静的には判定できないためです。JSからアセットを参照する場合は
  `asset-manifest.json` を読んでください。
- **CSSからCSSへの `@import url(...)` は書き換えません。** 参照先のハッシュがまだ確定していない
  ためです。この形の参照を見つけると警告を出します。
```

- [ ] **Step 3: `README.md` に同じ変更を英語で入れる**

`README.ja.md` で触った3箇所（未実装の項目、`features` の表、`fingerprint` の説明と制限）に
対応する英語版の箇所を同じ内容に直す。

- [ ] **Step 4: `CLAUDE.md` を更新する**

「機能フラグ（features）」の箇条書きに追加する。

```markdown
- **fingerprint**: アセット名への内容ハッシュ付与と、HTML/CSSの参照書き換え
```

同ファイルの `config.yaml` の例の `features` ブロックに `fingerprint: false` を追加し、
「`hirundo init` は `features` までを書き出し」の記述が生成内容と合っているか確認する。

- [ ] **Step 5: `CHANGELOG.md` の `[Unreleased]` に追記する**

`### Added` に追加。

```markdown
- `features.fingerprint` — アセット名に内容ハッシュを付け、生成されたHTMLの `href` / `src` /
  `srcset`、CSSの `url(...)`、`<style>` 本文と `style` 属性の参照を書き換える。対応表は
  `_site/asset-manifest.json`。古い世代のハッシュ名の出力はビルドのたびに削除されるので、
  clean せずに再ビルドする `hirundo serve` でも出力が膨れない。JS内の文字列とCSSからCSSへの
  `@import url(...)` は書き換えない（後者は警告を出す）
```

`### Fixed` に追加。

```markdown
- **CRITICAL**: フィンガープリントは**ソース**のバイト列をハッシュして**処理後**のバイト列を
  書いていたため、ハッシュが名前の対象を識別していなかった。`features.minify` の切り替えが
  ハッシュに反映されず、最小化の有無が違う2つの出力が同じ名前になり得た。ハッシュは常に最終的な
  出力バイト列に対して取られるようになった。CSSは `url(...)` を書き換えた後のバイト列を対象に
  するため、アセット処理は「CSS以外 → CSS」の2パスに分かれる
- マニフェストの値がディレクトリの落ちたファイル名（`style-abc.css`）だったため、参照の書き換えに
  使えなかった。出力ディレクトリからの相対パス（`css/style-abc.css`）になった
```

`### Removed`（無ければ `### Changed` の後に新設）に追加。

```markdown
- **BREAKING**: `AssetConcatenator` と `AssetConcatenationRule` を削除。`AssetPipeline` の
  `concatenationRules` と `enableSourceMaps`、`CSSProcessingOptions.sourceMap`、
  `JSProcessingOptions` の `sourceMap` / `transpile` / `target`、`AssetFileManager.findFiles` も
  削除した。いずれも `config.yaml` から到達できないライブラリ面で、結合はルールの照合が
  `findFiles` と `isConcatenatedFile` で食い違っており（`js/*.js` は束ねた上で元ファイルも出力し、
  `*.js` は元ファイルを全部落とす）、ソースマップはどの経路でも生成されず、`transpileJS` は
  警告を出して入力をそのまま返すだけだった。ES6+の変換には Babel や esbuild を使うこと
- **BREAKING**: `AssetPipeline.processAssets` / `saveManifest` / `loadManifest` が
  `[String: String]` ではなく `AssetManifest` を扱うようになった。`AssetProcessor` の
  `processAssetContent`（処理して書き込む）は削除され、書き込みは `AssetPipeline` が行う
- **BREAKING**: `AssetFileManager.processDirectory` から、使われていなかった `destinationPath`
  引数と `concatenationRules` 引数を削除した
```

- [ ] **Step 6: 全テストとビルドを確認する**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | grep -E "Executed [0-9]+ tests|error:" | tail -5
```

Expected: ビルド成功、`0 failures`。

- [ ] **Step 7: ドキュメントに残った古い記述が無いか確認する**

```bash
grep -rn "concatenat\|sourceMap\|source map\|transpile" --include="*.md" . --exclude-dir=.git --exclude-dir=docs | grep -v CHANGELOG
```

Expected: 出力なし（CHANGELOG の削除記録だけが残る）。ヒットしたら、その記述を直す。

- [ ] **Step 8: コミット**

```bash
git add README.md README.ja.md CLAUDE.md CHANGELOG.md Sources/HirundoCore/AssetPipeline.swift
git commit -m "docs: document features.fingerprint and the removal of concatenation"
```

---

## 完了の条件

- [ ] `swift build` が成功する
- [ ] `swift test` が 0 failures（Task 1 で1件削除、Task 2〜9 で約60件追加）
- [ ] `features.fingerprint: true` でビルドした `_site` の HTML が、実在するファイルだけを指す
- [ ] `features.fingerprint` を書かない既存の `config.yaml` の出力が、この変更の前後で変わらない
- [ ] `hirundo validate` が `features.fingerprint` を警告しない
- [ ] `grep -rn "AssetConcatenator\|enableSourceMaps\|transpileJS" Sources` が空

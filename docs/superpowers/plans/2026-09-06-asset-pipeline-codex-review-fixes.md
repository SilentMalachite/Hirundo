# アセットパイプライン Codex レビュー対応 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `docs/reviews/2026-09-06-fingerprint-exclusions-codex-review.md` の指摘 5 件（HIGH 1 / MEDIUM 2 / LOW 2）をすべて解消し、空振りしていた 2 つのテストを本物の回帰テストに直す。

**Architecture:** パススルーアセットの処理順を「ハッシュ → 解決 → コピー」から「解決＋閉じ込め判定＋識別情報の記録 → ステージングへコピー → 識別情報を照合 → **ステージングファイルをハッシュ** → 差し替え」に変える。ソースを読むすべての経路（JS・CSS・パススルー）は読む直前に `resolveConfinedSource` で閉じ込めを判定し直す。`**` の照合は `(パターン添字, パス添字)` をメモ化する DP に置き換える。`AssetItem` は deprecated シムとして復活させる。

**Tech Stack:** Swift 5.9+、XCTest、Foundation（`FileManager.attributesOfItem` の `.systemNumber` / `.systemFileNumber`）。新しい依存は追加しない。

**Spec:** `docs/reviews/2026-09-06-fingerprint-exclusions-codex-review.md`

## Global Constraints

- 対応 OS は macOS 12+、Swift 5.9+。新しい外部依存を追加しない
- 出力ハッシュは SHA-256 の先頭 16 桁の小文字 hex。出力名は `<name>-<hash>.<ext>`（変更しない）
- パススルーアセットは引き続き `FileManager.copyItem` でコピーし（パーミッション・拡張属性を保ち、APFS ではクローン）、`replaceItemAt(_:withItemAt:options: .usingNewMetadataOnly)` で原子的に差し替える。`Data(contentsOf:)` で丸ごとメモリに載せる形へ戻さない
- 「ハッシュは書き込んだバイト列を覆う」を不変条件として維持する。ハッシュ・書き込み・マニフェスト登録は `AssetPipeline.write` の中に留める
- `config.yaml` のスキーマは変えない
- 新規ソースは `Sources/HirundoCore/Assets/` に置く。テストは `Tests/HirundoTests/` に置く
- 各タスクの最後に `swift build 2>&1 | grep -E "warning|error"` を実行し、新しい警告を増やさない（`-warn-concurrency` が有効。deprecated 警告はタスク 4 のテスト内で `@available(*, deprecated)` により抑える）
- CHANGELOG は英語（既存エントリに合わせる）。ソースのコメントは日本語
- コミットは Conventional Commits 形式（`fix:` / `test:` / `perf:` / `refactor:` / `docs:`）
- 作業ブランチ: `fix/asset-pipeline-codex-review`（`main` から切る）

## File Structure

| ファイル | 責務 | タスク |
|---------|------|-------|
| `Tests/HirundoTests/AssetPipelineTests.swift` | 空振りしていた symlink 2回ビルドテストの修正、H-1 の競合テスト | 1, 6, 7 |
| `Tests/HirundoTests/AssetFingerprintIntegrationTests.swift` | 設定配線テストの修正と対照ケース | 2 |
| `Sources/HirundoCore/Assets/AssetFingerprintExclusions.swift` | `matchSegments` を DP 化 | 3 |
| `Tests/HirundoTests/AssetFingerprintExclusionsTests.swift` | 計算量テスト | 3 |
| `Sources/HirundoCore/ContentModels.swift` | deprecated な `AssetItem` シム | 4 |
| `Tests/HirundoTests/AssetItemCompatibilityTests.swift`（新規） | シムのコンパイル互換テスト | 4 |
| `Sources/HirundoCore/Assets/FileIdentity.swift`（新規） | コピー前後の同一性照合に使う識別情報 | 5 |
| `Tests/HirundoTests/FileIdentityTests.swift`（新規） | 識別情報の単体テスト | 5 |
| `Sources/HirundoCore/AssetPipeline.swift` | `resolveConfinedSource`、読み込み経路の配線、`write` の再構成 | 6, 7 |
| `CHANGELOG.md` | 各修正の記録 | 3, 4, 7 |

## 依存関係

- タスク 1〜4 は互いに独立（順不同で実行可）
- タスク 5 → 6 → 7 はこの順（6 は 5 の `FileIdentity` を、7 は 6 の `ConfinedSource` を使う）
- タスク 1 はタスク 7 より前に終えること（7 で `write` を変えたとき、1 で直したテストが本物の回帰検出器として働く）

---

### Task 1: L-2 — symlink 2回ビルドテストを本物にする

**Files:**
- Modify: `Tests/HirundoTests/AssetPipelineTests.swift:273-303`（`testSecondBuildAfterASymlinkedAssetDoesNotThrow`）

**Interfaces:**
- Consumes: `AssetPipeline.processAssets(from:to:) throws -> AssetManifest`、`AssetManifest.subscript(key:) -> String?`
- Produces: なし（テストのみ）

**背景:** 現在のテストはリンク先を `tempDir/shared`（`source` の兄弟 ＝ ソースルートの外）に置いている。`AssetFileManager` は外を指すリンクを列挙の時点で飛ばすので、1回目も2回目も `write` に届かず、`XCTAssertNoThrow` は何も検証していない。

- [ ] **Step 1: テストを書き換える**

`AssetPipelineTests.swift` の `testSecondBuildAfterASymlinkedAssetDoesNotThrow` を、doc コメントごと次に置き換える：

```swift
    /// レビューで見つかった Critical の回帰の核心: シンボリックリンクをリンクのまま書き出すと、
    /// `write` 冒頭の閉じ込め判定は候補パスを `resolvingSymlinksInPath()` で解決するため、
    /// 次の非クリーンビルド（`hirundo serve` の再ビルド相当）でそのリンクの解決先が出力先の
    /// 外だと判定され、ビルドが `Output path escapes destination directory` で落ちる。
    ///
    /// リンク先は **static の中** に置く。外を指すリンクは `AssetFileManager` が列挙の時点で
    /// 飛ばすので、外に置くと両方のビルドで `write` に届かず、このテストは何も検証しない
    /// （以前はそうなっていた）。`XCTUnwrap(first["img/logo.png"])` が、リンクが実際に処理
    /// されたことの証拠になる。
    func testSecondBuildAfterASymlinkedAssetDoesNotThrow() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(
            at: sourceDir.appendingPathComponent("img"),
            withIntermediateDirectories: true
        )

        let sharedDir = sourceDir.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        let targetContent = Data("this is the real image bytes".utf8)
        let targetFile = sharedDir.appendingPathComponent("logo-real.png")
        try targetContent.write(to: targetFile)

        let logoLink = sourceDir.appendingPathComponent("img/logo.png")
        try FileManager.default.createSymbolicLink(at: logoLink, withDestinationURL: targetFile)

        // 1回目: リンクが実体として書き出されていること。リンクのまま出ると、2回目の閉じ込め
        // 判定がその解決先を見て落ちる。フィンガープリント無効でも壊れる経路なので無効のまま。
        let first = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)
        let firstOutput = destDir.appendingPathComponent(try XCTUnwrap(first["img/logo.png"]))
        XCTAssertNotEqual(
            try firstOutput.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true,
            "1回目のビルドがシンボリックリンクのまま書き出している: \(firstOutput.path)"
        )

        // 2回目: `hirundo serve` はクリーンせずに同じ出力先へ再ビルドする。
        var second = AssetManifest()
        XCTAssertNoThrow(
            second = try pipeline.processAssets(from: sourceDir.path, to: destDir.path),
            "1回目のビルドが残した出力の上に2回目のビルドが書けない"
        )
        XCTAssertEqual(second["img/logo.png"], "img/logo.png")
        XCTAssertEqual(
            try Data(contentsOf: firstOutput), targetContent,
            "2回目のビルド後の出力がリンク先の実体と一致しない"
        )
    }
```

- [ ] **Step 2: テストが対象を本当に通ることを確かめる（RED 相当）**

`Sources/HirundoCore/AssetPipeline.swift` の `write` 内、`.file` 分岐の `let source = fileURL.resolvingSymlinksInPath()` を**一時的に** `let source = fileURL` に変える（リンクをリンクのままコピーする、修正前の挙動）。

Run: `swift test --filter AssetPipelineTests/testSecondBuildAfterASymlinkedAssetDoesNotThrow 2>&1 | tail -20`
Expected: FAIL（「1回目のビルドがシンボリックリンクのまま書き出している」か、2回目の `XCTAssertNoThrow` のどちらか）。旧テストならこの改変でも通っていた ── それが空振りの証明。

- [ ] **Step 3: 一時変更を戻す**

`let source = fileURL.resolvingSymlinksInPath()` に戻す。`git diff Sources/` が空であることを確認する。

- [ ] **Step 4: テストが通ることを確かめる**

Run: `swift test --filter AssetPipelineTests/testSecondBuildAfterASymlinkedAssetDoesNotThrow 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
git add Tests/HirundoTests/AssetPipelineTests.swift
git commit -m "test: point the symlinked-asset rebuild test at a link that is actually processed

The link target lived outside the source root, so the enumerator skipped it
on both builds and the test never reached write(). Move the target inside
static/ and assert on the manifest entry so a skipped link fails the test."
```

---

### Task 2: L-1 — 設定配線テストを組み込み除外と重複しない名前にする

**Files:**
- Modify: `Tests/HirundoTests/AssetFingerprintIntegrationTests.swift:189-224`（`testConfigSuppliedFingerprintExcludePatternExemptsAFileEndToEnd`）

**Interfaces:**
- Consumes: `SiteGenerator(projectPath:)`、`SiteGenerator.build()`、`AssetPruner.isFingerprintedName(_:) -> Bool`
- Produces: なし（テストのみ）

**背景:** テストは `ads.txt` が組み込みパターンに無い前提で書かれているが、`AssetFingerprintExclusions.builtIn` に `ads.txt` は含まれる（`AssetFingerprintExclusions.swift:29`）。`SiteGenerator.configureAssetPipeline` の配線（`SiteGenerator.swift:447-449`）を消しても通る。

- [ ] **Step 1: 既存テストを書き換え、対照テストを追加する**

`testConfigSuppliedFingerprintExcludePatternExemptsAFileEndToEnd` を doc コメントごと次に置き換え、その直後に `testAFileNotListedInFingerprintExcludeIsHashed` を追加する：

```swift
    /// `config.assets.fingerprintExclude` から `assetPipeline.fingerprintExclusions` への配線
    /// （`SiteGenerator.configureAssetPipeline`）を、実際に `config.yaml` を経由して検証する。
    /// `keep-stable.custom` は組み込みパターン（`AssetFingerprintExclusions.builtIn`）のどれにも
    /// 一致しないので、これが除外されるのは配線が効いている場合に限られる ── その配線を消せば
    /// このテストは落ちる。
    ///
    /// 以前は `ads.txt` を使っていたが、`ads.txt` は組み込みに含まれるため、配線を消しても
    /// 通ってしまっていた。
    func testConfigSuppliedFingerprintExcludePatternExemptsAFileEndToEnd() async throws {
        try write("""
        site:
          title: "Fingerprint Site"
          url: "https://example.com"

        features:
          fingerprint: true
          minify: true

        assets:
          fingerprintExclude:
            - "keep-stable.custom"
        """, to: "config.yaml")
        try write("stable\n", to: "static/keep-stable.custom")

        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.appendingPathComponent("keep-stable.custom").path),
            "keep-stable.custom が元の名前で出力されていない"
        )
        let builtManifest = try manifest()
        XCTAssertEqual(builtManifest["keep-stable.custom"], "keep-stable.custom")

        // 同じビルドの中で、除外対象ではない通常のアセットは変わらずハッシュされるべき。
        // (この後半のアサーションが無いと、フィンガープリント自体が丸ごと無効化されていても
        // このテストは通ってしまう。)
        let hashedStylesheet = try XCTUnwrap(builtManifest["css/style.css"])
        XCTAssertNotEqual(hashedStylesheet, "css/style.css", "除外対象ではないアセットはハッシュされるべき")
    }

    /// 上の対照: 同じファイルを `assets.fingerprintExclude` 無しでビルドするとハッシュされる。
    /// これが無いと、上のテストは「`keep-stable.custom` が何らかの理由で常に除外される」場合にも
    /// 通ってしまう。
    func testAFileNotListedInFingerprintExcludeIsHashed() async throws {
        try write("stable\n", to: "static/keep-stable.custom")

        let generator = try SiteGenerator(projectPath: projectPath)
        try await generator.build()

        let value = try XCTUnwrap(manifest()["keep-stable.custom"])
        XCTAssertNotEqual(value, "keep-stable.custom", "設定に無いファイルがハッシュされていない")
        XCTAssertTrue(AssetPruner.isFingerprintedName(URL(fileURLWithPath: value).lastPathComponent))
    }
```

- [ ] **Step 2: 配線を消すと落ちることを確かめる（RED 相当）**

`Sources/HirundoCore/SiteGenerator.swift:447-449` の
```swift
        assetPipeline.fingerprintExclusions = AssetFingerprintExclusions(
            additional: config.assets.fingerprintExclude
        )
```
を**一時的に**コメントアウトする。

Run: `swift test --filter AssetFingerprintIntegrationTests/testConfigSuppliedFingerprintExcludePatternExemptsAFileEndToEnd 2>&1 | tail -10`
Expected: FAIL（「keep-stable.custom が元の名前で出力されていない」）

- [ ] **Step 3: 一時変更を戻す**

コメントアウトを解除する。`git diff Sources/` が空であることを確認する。

- [ ] **Step 4: 両テストが通ることを確かめる**

Run: `swift test --filter AssetFingerprintIntegrationTests 2>&1 | tail -5`
Expected: 全件 PASS（11 tests）

- [ ] **Step 5: コミット**

```bash
git add Tests/HirundoTests/AssetFingerprintIntegrationTests.swift
git commit -m "test: exercise the fingerprintExclude wiring with a name the built-in list lacks

ads.txt is a built-in exclusion, so the end-to-end test passed even with
the config wiring removed. Use keep-stable.custom and add the contrast
case that the same file is hashed when it is not listed."
```

---

### Task 3: M-1 — `**` の照合をメモ化 DP にする

**Files:**
- Modify: `Sources/HirundoCore/Assets/AssetFingerprintExclusions.swift:83-125`（`collapsingConsecutiveDoubleStars` のコメントと `matchSegments`）
- Test: `Tests/HirundoTests/AssetFingerprintExclusionsTests.swift`
- Modify: `CHANGELOG.md`（`### Fixed` に追記）

**Interfaces:**
- Consumes: `AssetFingerprintExclusions.matches(pattern:path:) -> Bool`（`static`、`internal`）、`matchSegment(pattern:text:)`（変更しない）
- Produces: `matchSegments(pattern: [String], path: [String]) -> Bool` の意味は不変。計算量が O(パターン長 × パス長) になる

- [ ] **Step 1: 計算量のテストを書く**

`AssetFingerprintExclusionsTests.swift` の `// MARK: - Equatable` の直前に追加する：

```swift
    // MARK: - 計算量

    /// 非連続の `**` を複数含むパターンは、素朴な再帰だとパス長に対して指数的に遅くなる
    /// （`**` ごとに「残りのどこから再開するか」を全部試し、同じ状態を何度も探索するため）。
    /// `assets.fingerprintExclude` はユーザーが自由に書けるので、これは設定ミス1つでビルドが
    /// 止まる経路だった。一致しない入力（＝全候補を試し切る最悪ケース）で時間を測る。
    ///
    /// メモ化前はこのサイズで数十秒かかる（デバッグビルド）。メモ化後は状態数が
    /// 13 × 41 に収まり、ミリ秒未満で終わる。
    func testManyNonAdjacentDoubleStarsAgainstADeepPathFinishesQuickly() {
        let pattern = String(repeating: "**/x/", count: 6) + "z"
        let path = String(repeating: "x/", count: 40) + "y"

        let start = Date()
        let matched = AssetFingerprintExclusions.matches(pattern: pattern, path: path)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(matched)
        XCTAssertLessThan(elapsed, 1.0, "\(elapsed)s かかった。`**` の照合が指数的になっている")
    }
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `swift test --filter AssetFingerprintExclusionsTests/testManyNonAdjacentDoubleStarsAgainstADeepPathFinishesQuickly 2>&1 | tail -5`
Expected: FAIL（`XCTAssertLessThan` で落ちる。数十秒〜1分程度かかる。2分を超えても終わらない場合は Ctrl-C で止めてよい ── それ自体が指数的である証拠）

- [ ] **Step 3: `matchSegments` を DP に置き換える**

`AssetFingerprintExclusions.swift` の `matchSegments`（doc コメント含む、`/// パターンのセグメント列とパスのセグメント列を先頭から再帰的に比較する。` から関数の閉じ括弧まで）を次に置き換える：

```swift
    /// パターンのセグメント列とパスのセグメント列を比較する。
    ///
    /// `**` はセグメントそのもの（例えば `a/**/b` の真ん中）としてのみ意味を持ち、その場合は
    /// ゼロ個以上のセグメントを読み飛ばせる ── ゼロ個も許すことで `a/**/b.txt` が `a/b.txt` に
    /// 一致する。それ以外のセグメントは `matchSegment` で `*` を1セグメント内のワイルドカード
    /// として比較する。
    ///
    /// 状態は `(パターンの添字, パスの添字)` の組で、各状態の結果をメモ化する。`**` が複数ある
    /// パターンでは同じ状態に何度も到達するため、メモ化しないと「`**` ごとに再開位置を全部
    /// 試す」探索がパス長に対して指数的になる（`assets.fingerprintExclude` はユーザー入力なので、
    /// 設定ミス1つでビルドが止まる経路だった）。メモ化すれば状態数はパターン長 × パス長で
    /// 抑えられる。配列を切り出さず添字だけを進めるのも同じ理由（切り出しごとの確保を無くす）。
    private static func matchSegments(pattern: [String], path: [String]) -> Bool {
        // memo[patternIndex][pathIndex]。nil は未計算。
        var memo = [[Bool?]](
            repeating: [Bool?](repeating: nil, count: path.count + 1),
            count: pattern.count + 1
        )

        func match(_ patternIndex: Int, _ pathIndex: Int) -> Bool {
            if let cached = memo[patternIndex][pathIndex] { return cached }

            let result: Bool
            if patternIndex == pattern.count {
                result = pathIndex == path.count
            } else if pattern[patternIndex] == "**" {
                // ゼロ個読み飛ばして次のパターンへ進むか、パスを1つ読み飛ばして `**` に留まるか。
                result = match(patternIndex + 1, pathIndex)
                    || (pathIndex < path.count && match(patternIndex, pathIndex + 1))
            } else if pathIndex < path.count,
                      matchSegment(pattern: pattern[patternIndex], text: path[pathIndex]) {
                result = match(patternIndex + 1, pathIndex + 1)
            } else {
                result = false
            }

            memo[patternIndex][pathIndex] = result
            return result
        }

        return match(0, 0)
    }
```

- [ ] **Step 4: `collapsingConsecutiveDoubleStars` のコメントを現状に合わせる**

同ファイルの `collapsingConsecutiveDoubleStars` の doc コメント（`/// 連続する \`**\` セグメントを1つに畳む。` から `/// 「隣接する \`**\` の数だけ組み合わせを試す」形で指数的に遅くなるのを、原因ごと取り除く。` まで）を次に置き換える。関数本体は変えない：

```swift
    /// 連続する `**` セグメントを1つに畳む。`a/**/**/b` は `a/**/b` と意味的に同じなので、
    /// これは近似ではなく厳密な書き換え。計算量は `matchSegments` のメモ化が抑えるので、
    /// これは正規化にすぎない（メモの行数を減らす程度の効果）。
```

- [ ] **Step 5: 全テストが通ることを確かめる**

Run: `swift test --filter AssetFingerprintExclusionsTests 2>&1 | tail -5`
Expected: 全件 PASS（28 tests）。特に既存の `testMultipleNonAdjacentDoubleStarSegments`、`testDoubleStarMatchesZeroSegments`、`testBareDoubleStarMatchesEveryPath`、`testLeadingDoubleStarSegmentMatchesAnyDepth` が意味の不変を担保する。

Run: `swift test --filter "AssetPipelineTests|AssetFingerprintIntegrationTests" 2>&1 | tail -5`
Expected: 全件 PASS

- [ ] **Step 6: CHANGELOG に追記する**

`CHANGELOG.md` の `## [Unreleased]` 配下 `### Fixed` の**先頭**に追加する：

```markdown
- `assets.fingerprintExclude` pattern matching was exponential in the path depth for a pattern with several non-adjacent `**` segments (`**/a/**/b/**/c`), because each `**` retried every restart position without remembering which `(pattern, path)` states had already failed. One such pattern in `config.yaml` could stall a build. Matching is now memoised over (pattern index, path index) and bounded by pattern length × path depth
```

- [ ] **Step 7: コミット**

```bash
git add Sources/HirundoCore/Assets/AssetFingerprintExclusions.swift Tests/HirundoTests/AssetFingerprintExclusionsTests.swift CHANGELOG.md
git commit -m "perf: memoise ** matching in fingerprint exclusions

A pattern with several non-adjacent ** segments retried every restart
position from every state, which is exponential in the path depth and
reachable from a user's config.yaml. Memoise over (pattern index, path
index) and walk by index instead of slicing arrays."
```

---

### Task 4: M-2 — `AssetItem` を deprecated シムとして復活させる

**Files:**
- Modify: `Sources/HirundoCore/ContentModels.swift:80-85`（`AssetType` の直後に追加）
- Create: `Tests/HirundoTests/AssetItemCompatibilityTests.swift`
- Modify: `CHANGELOG.md:49`（`### Removed` の `AssetItem` 行を `### Deprecated` へ）

**Interfaces:**
- Consumes: `AssetType`（トップレベル `public enum`、変更しない）、`AnyCodable`（既存）
- Produces: `public struct AssetItem`（deprecated）、`AssetItem.AssetType`（`typealias`）、`AssetItem.init(sourcePath:outputPath:type:)`

**背景:** 1.1.4 までは `AssetItem` が `public` で `AssetItem.AssetType` が唯一の型だった。マージ差分は互換層なしで削除した。ユーザーの決定により deprecated シムを残す。なお `### Removed` には他の BREAKING 項目（`AssetConcatenator` 等）が残っており、それらはこの計画の対象外。

- [ ] **Step 1: 互換テストを書く**

`Tests/HirundoTests/AssetItemCompatibilityTests.swift` を新規作成：

```swift
import XCTest
@testable import HirundoCore

/// 1.1.x の利用者が書いていた形がそのままコンパイルできること。
///
/// `AssetItem` は deprecated なので、このテスト自身にも `@available(*, deprecated)` を付けて
/// 警告を抑える（警告付きで通ることが、このシムの意図そのもの）。
final class AssetItemCompatibilityTests: XCTestCase {

    @available(*, deprecated)
    func testNestedAssetTypeIsTheTopLevelAssetType() {
        let nested: AssetItem.AssetType = .image("png")
        let topLevel: AssetType = nested
        XCTAssertEqual(topLevel, .image("png"))
        XCTAssertEqual(nested, AssetPipeline().detectAssetType(for: "logo.png"))
    }

    @available(*, deprecated)
    func testAssetItemStillConstructs() {
        let item = AssetItem(sourcePath: "static/a.css", outputPath: "_site/a.css", type: .css)
        XCTAssertEqual(item.sourcePath, "static/a.css")
        XCTAssertEqual(item.outputPath, "_site/a.css")
        XCTAssertEqual(item.type, .css)
        XCTAssertFalse(item.processed)
        XCTAssertTrue(item.metadata.isEmpty)
    }
}
```

- [ ] **Step 2: コンパイルが落ちることを確かめる**

Run: `swift build --build-tests 2>&1 | grep -E "error" | head -5`
Expected: `error: cannot find 'AssetItem' in scope`（複数）

- [ ] **Step 3: シムを追加する**

`Sources/HirundoCore/ContentModels.swift` の `public enum AssetType { ... }` の閉じ括弧（行 85）の直後に追加する：

```swift

/// 1.1.x までの公開 API との互換のためだけに残している。次のメジャーバージョンで削除する。
///
/// 1.1.4 以前は `AssetType` がこの構造体のネスト型で、`AssetPipeline.detectAssetType` の
/// 戻り値も `AssetItem.AssetType` だった。この構造体自体はリポジトリ内のどこからも生成されて
/// おらず（`sourcePath` / `outputPath` / `processed` / `metadata` は誰も読まない）、ネスト型
/// だけが使われていたので、`AssetType` をトップレベルへ出した。外部の利用者が
/// `AssetItem.AssetType` と書いていてもコンパイルが通るよう、`typealias` で橋渡しする。
@available(*, deprecated, message: "Use the top-level AssetType. AssetItem will be removed in the next major version.")
public struct AssetItem: Sendable {
    public typealias AssetType = HirundoCore.AssetType

    public let sourcePath: String
    public let outputPath: String
    public let type: AssetType
    public var processed: Bool = false
    public var metadata: [String: AnyCodable] = [:]

    public init(sourcePath: String, outputPath: String, type: AssetType) {
        self.sourcePath = sourcePath
        self.outputPath = outputPath
        self.type = type
    }
}
```

- [ ] **Step 4: テストが通り、警告が増えていないことを確かめる**

Run: `swift test --filter AssetItemCompatibilityTests 2>&1 | tail -5`
Expected: 2 tests PASS

Run: `swift build --build-tests 2>&1 | grep -E "warning" | grep -i "AssetItem"`
Expected: 出力なし（テストは `@available(*, deprecated)` で抑えている。ソース側で `AssetItem` を参照する箇所は無い）

- [ ] **Step 5: CHANGELOG を書き換える**

`CHANGELOG.md:49` の行（`- **BREAKING**: removed \`AssetItem\`. ...` で始まる1行）を削除し、`### Removed`（行 45）の**直前**に次のセクションを挿入する：

```markdown
### Deprecated
- `AssetItem` is deprecated and will be removed in the next major version. Nothing in the codebase constructed it — its stored properties (`sourcePath`, `outputPath`, `processed`, `metadata`) were unreachable dead weight — so only its nested `AssetType` enum was ever actually used, and only as a return type. `AssetType` is now a top-level `public enum` in `ContentModels.swift`; `AssetItem.AssetType` remains as a `typealias` so existing code keeps compiling with a deprecation warning

```

- [ ] **Step 6: コミット**

```bash
git add Sources/HirundoCore/ContentModels.swift Tests/HirundoTests/AssetItemCompatibilityTests.swift CHANGELOG.md
git commit -m "refactor: keep AssetItem as a deprecated shim over the top-level AssetType

Removing a public struct from a library product in a minor release breaks
semver. Restore it deprecated, with AssetItem.AssetType bridged by a
typealias, and schedule the removal for the next major version."
```

---

### Task 5: H-1 (a) — `FileIdentity` を追加する

**Files:**
- Create: `Sources/HirundoCore/Assets/FileIdentity.swift`
- Create: `Tests/HirundoTests/FileIdentityTests.swift`

**Interfaces:**
- Consumes: `FileManager.attributesOfItem(atPath:)`
- Produces: `struct FileIdentity: Equatable`（`internal`）、`init(ofItemAtPath: String) throws`

- [ ] **Step 1: 単体テストを書く**

`Tests/HirundoTests/FileIdentityTests.swift` を新規作成：

```swift
import XCTest
@testable import HirundoCore

final class FileIdentityTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-identity-test-\(UUID())")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSameUnchangedFileHasEqualIdentity() throws {
        let file = tempDir.appendingPathComponent("a.bin")
        try Data("bytes".utf8).write(to: file)

        let first = try FileIdentity(ofItemAtPath: file.path)
        let second = try FileIdentity(ofItemAtPath: file.path)
        XCTAssertEqual(first, second)
    }

    func testAppendingBytesChangesIdentity() throws {
        let file = tempDir.appendingPathComponent("a.bin")
        try Data("bytes".utf8).write(to: file)
        let before = try FileIdentity(ofItemAtPath: file.path)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("more".utf8))
        try handle.close()

        XCTAssertNotEqual(before, try FileIdentity(ofItemAtPath: file.path), "サイズが変わったのに同一と判定された")
    }

    /// 同じ名前・同じサイズでも、別のファイルに置き換えられたら別物。inode が変わる。
    func testReplacingTheFileWithSameSizedContentChangesIdentity() throws {
        let file = tempDir.appendingPathComponent("a.bin")
        try Data("bytes".utf8).write(to: file)
        let before = try FileIdentity(ofItemAtPath: file.path)

        try FileManager.default.removeItem(at: file)
        try Data("BYTES".utf8).write(to: file)

        XCTAssertNotEqual(before, try FileIdentity(ofItemAtPath: file.path), "別ファイルに差し替えられたのに同一と判定された")
    }

    /// サイズも inode も変わらない上書きは、更新時刻で検出する。
    func testInPlaceOverwriteOfSameSizeChangesIdentity() throws {
        let file = tempDir.appendingPathComponent("a.bin")
        try Data("bytes".utf8).write(to: file)
        let before = try FileIdentity(ofItemAtPath: file.path)

        // 更新時刻の分解能（APFS はナノ秒）より確実に離す。
        Thread.sleep(forTimeInterval: 0.02)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data("BYTES".utf8))
        try handle.close()

        XCTAssertNotEqual(before, try FileIdentity(ofItemAtPath: file.path), "同サイズの上書きが検出されていない")
    }

    func testMissingFileThrows() {
        XCTAssertThrowsError(try FileIdentity(ofItemAtPath: tempDir.appendingPathComponent("missing").path))
    }
}
```

- [ ] **Step 2: コンパイルが落ちることを確かめる**

Run: `swift build --build-tests 2>&1 | grep -E "error" | head -3`
Expected: `error: cannot find 'FileIdentity' in scope`

- [ ] **Step 3: `FileIdentity` を実装する**

`Sources/HirundoCore/Assets/FileIdentity.swift` を新規作成：

```swift
import Foundation

/// ファイルの識別情報。「判定したときと同じファイルをコピーしたか」を後から確かめるために持つ。
///
/// `AssetPipeline` はソースの閉じ込め判定とコピーを別々の `FileManager` 呼び出しで行うため、
/// その間にファイルが差し替えられたり書き換えられたりしても、それだけでは気づけない。
/// 判定の直後にこれを取り、コピーの直後にもう一度取って比べる。デバイス番号と inode が同じで、
/// サイズと更新時刻も同じなら、同じファイルの同じ内容を見ていたと判断する。
///
/// これは競合の窓を「判定から stat まで」の数マイクロ秒に狭めるものであって、ゼロにはしない。
/// ゼロにするにはファイル記述子で対象を固定して `fstat` する必要があるが、`copyItem` は
/// パスしか受け取らず、それを捨てるとパーミッション・拡張属性・APFS クローンも失う。
struct FileIdentity: Equatable {
    let device: Int
    let inode: Int
    let size: Int
    let modificationDate: Date

    /// `attributesOfItem` は `lstat` 相当でリンクを辿らない。渡すパスは解決済みであること。
    init(ofItemAtPath path: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        device = (attributes[.systemNumber] as? NSNumber)?.intValue ?? -1
        inode = (attributes[.systemFileNumber] as? NSNumber)?.intValue ?? -1
        size = (attributes[.size] as? NSNumber)?.intValue ?? -1
        modificationDate = (attributes[.modificationDate] as? Date) ?? .distantPast
    }
}
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `swift test --filter FileIdentityTests 2>&1 | tail -5`
Expected: 5 tests PASS

- [ ] **Step 5: コミット**

```bash
git add Sources/HirundoCore/Assets/FileIdentity.swift Tests/HirundoTests/FileIdentityTests.swift
git commit -m "feat: add FileIdentity for before/after copy comparison

Device, inode, size and mtime of a resolved path, compared by the asset
pipeline to detect a source that changed between its containment check
and its copy."
```

---

### Task 6: H-1 (b) — 読む直前に閉じ込めを判定し直す `resolveConfinedSource`

**Files:**
- Modify: `Sources/HirundoCore/AssetPipeline.swift`（`processAssets`、`AssetContent`、`processNonStylesheet`、`processStylesheets`、`write` の `.file` 分岐）
- Test: `Tests/HirundoTests/AssetPipelineTests.swift`

**Interfaces:**
- Consumes: `FileIdentity(ofItemAtPath:)`（タスク 5）
- Produces:
  - `struct ConfinedSource { let url: URL; let identity: FileIdentity }`（`internal`）
  - `func resolveConfinedSource(_ fileURL: URL, sourceRoot: String) throws -> ConfinedSource`（`internal`、`AssetPipeline` のインスタンスメソッド、**override 可能**にするため `final` を付けない）
  - `AssetContent.file(ConfinedSource)`（`private`。タスク 7 が `identity` を使う）

**背景:** `AssetFileManager` は列挙の時点で閉じ込めを判定するが、その後リンクが差し替えられると `static/` の外を読む。CSS は列挙（パス1）と読み込み（パス2）が離れているので窓が特に広い。読む側で判定し直す。

- [ ] **Step 1: 競合を再現するテストを書く**

`AssetPipelineTests.swift` のクラス定義の**前**（`final class AssetPipelineTests` の上、import の下）にテスト用サブクラスを追加する：

```swift
/// `AssetFileManager` の閉じ込め判定（列挙時）とソースの読み込みの間に起きる変化を、
/// 決定的に再現するためのフック。`resolveConfinedSource` は読み込みの直前に呼ばれるので、
/// `beforeResolving` は「列挙は通ったが読む前に差し替えられた」、`afterResolving` は
/// 「判定は通ったがコピーの前に書き換えられた」を表す。
final class HookedAssetPipeline: AssetPipeline {
    var beforeResolving: ((URL) throws -> Void)?
    var afterResolving: ((URL) throws -> Void)?

    override func resolveConfinedSource(_ fileURL: URL, sourceRoot: String) throws -> ConfinedSource {
        try beforeResolving?(fileURL)
        let resolved = try super.resolveConfinedSource(fileURL, sourceRoot: sourceRoot)
        try afterResolving?(fileURL)
        return resolved
    }
}
```

同ファイルの `testSkipsAFileSymlinkPointingOutsideTheSourceDirectory` の**直前**に2つのテストを追加する：

```swift
    /// 列挙時の閉じ込め判定を通ったリンクが、読まれる前に `static/` の外へ向け直される
    /// check-to-use 競合。パススルーアセットの経路。
    func testALinkRetargetedOutsideAfterEnumerationIsRefusedAtReadTime() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let insideTarget = sourceDir.appendingPathComponent("inside.png")
        try Data("inside".utf8).write(to: insideTarget)
        let outsideTarget = tempDir.appendingPathComponent("secret.png")
        try Data("secret".utf8).write(to: outsideTarget)

        let link = sourceDir.appendingPathComponent("logo.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: insideTarget)

        let hooked = HookedAssetPipeline()
        hooked.beforeResolving = { fileURL in
            guard fileURL.lastPathComponent == "logo.png" else { return }
            try FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideTarget)
        }

        XCTAssertThrowsError(
            try hooked.processAssets(from: sourceDir.path, to: destDir.path),
            "列挙後に外へ向け直されたリンクが読まれている"
        ) { error in
            guard case AssetPipelineError.pathTraversalAttempt = error else {
                return XCTFail("pathTraversalAttempt 以外のエラー: \(error)")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destDir.appendingPathComponent("logo.png").path),
            "static/ の外の中身が出力に書き出された"
        )
    }

    /// 同じ競合の CSS 経路。CSS は列挙（パス1）と読み込み（パス2）が離れているので、
    /// この窓は実際に広い。
    func testAStylesheetLinkRetargetedOutsideBetweenPassesIsRefused() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let insideTarget = sourceDir.appendingPathComponent("inside.css")
        try "body{}".write(to: insideTarget, atomically: true, encoding: .utf8)
        let outsideTarget = tempDir.appendingPathComponent("secret.css")
        try "/* secret */".write(to: outsideTarget, atomically: true, encoding: .utf8)

        let link = sourceDir.appendingPathComponent("style.css")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: insideTarget)

        let hooked = HookedAssetPipeline()
        hooked.beforeResolving = { fileURL in
            guard fileURL.lastPathComponent == "style.css" else { return }
            try FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideTarget)
        }

        XCTAssertThrowsError(try hooked.processAssets(from: sourceDir.path, to: destDir.path))
        let output = destDir.appendingPathComponent("style.css")
        if FileManager.default.fileExists(atPath: output.path) {
            XCTAssertNotEqual(
                try String(contentsOf: output, encoding: .utf8), "/* secret */",
                "static/ の外の中身が出力に書き出された"
            )
        }
    }
```

- [ ] **Step 2: コンパイルが落ちることを確かめる**

Run: `swift build --build-tests 2>&1 | grep -E "error" | head -3`
Expected: `error: cannot find type 'ConfinedSource' in scope` / `method does not override any method from its superclass`

- [ ] **Step 3: `ConfinedSource` と `resolveConfinedSource` を追加する**

`AssetPipeline.swift` の `// MARK: - Private` の**直前**に追加する：

```swift
    // MARK: - ソースの閉じ込め

    /// 読む直前に閉じ込めを判定し直したソース。`url` は解決済み、`identity` は判定直後の
    /// 識別情報（`write` がコピー後に照合する）。
    struct ConfinedSource {
        let url: URL
        let identity: FileIdentity
    }

    /// ソースを読む**直前**に解決し、解決先が `sourceRoot` の中に収まることを改めて確かめる。
    ///
    /// `AssetFileManager` は列挙の時点で同じ判定をしているが、判定から読み込みまでの間に
    /// リンクが差し替えられると、`static/` の外の中身を読んでしまう（check-to-use 競合）。
    /// CSS は列挙（パス1）と読み込み（パス2）が離れているので、この窓は特に広い。読む側で
    /// 判定し直せば、どの経路でも「判定した直後のパス」を読む。
    ///
    /// 解決できない（壊れた）リンクもここで止める。`resolvingSymlinksInPath` は最後の要素が
    /// 解決できないと何もしないので、そのまま `copyItem` するとリンクのままコピーされてしまう。
    /// 修正前の `Data(contentsOf:)` はここで失敗していたので、同じく失敗させる。
    ///
    /// テストが競合の窓を再現できるよう `internal` で、`final` を付けない。
    func resolveConfinedSource(_ fileURL: URL, sourceRoot: String) throws -> ConfinedSource {
        let resolved = fileURL.resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: resolved.path) else {
            throw AssetPipelineError.processingFailed(
                "Asset source is not readable (broken symlink?): \(fileURL.path)"
            )
        }
        let prefix = sourceRoot.hasSuffix("/") ? sourceRoot : sourceRoot + "/"
        guard resolved.path == sourceRoot || resolved.path.hasPrefix(prefix) else {
            throw AssetPipelineError.pathTraversalAttempt(fileURL.path)
        }
        return ConfinedSource(url: resolved, identity: try FileIdentity(ofItemAtPath: resolved.path))
    }

```

- [ ] **Step 4: `processAssets` でソースルートを求め、各読み込み経路へ配線する**

`processAssets` の `let sourceURL = URL(fileURLWithPath: sourcePath)` の直後に1行追加する：

```swift
        let sourceURL = URL(fileURLWithPath: sourcePath)
        // `AssetFileManager` が列挙時の判定に使うのと同じ値。読む直前の再判定でも同じ基準を使う。
        let sourceRoot = sourceURL.resolvingSymlinksInPath().path
```

同じ関数の `processNonStylesheet(` 呼び出しに `sourceRoot: sourceRoot,` を、`processStylesheets(` 呼び出しにも `sourceRoot: sourceRoot,` を追加する：

```swift
            try self.processNonStylesheet(
                fileURL,
                relativePath: relativePath,
                sourceRoot: sourceRoot,
                destinationPath: destinationPath,
                manifest: &manifest
            )
```
```swift
        try processStylesheets(stylesheets, sourceRoot: sourceRoot, destinationPath: destinationPath, manifest: &manifest)
```

`AssetContent` を次に変える（doc コメントの `URL` を `ConfinedSource` に直す）：

```swift
    /// `write` に渡す元データ。インメモリの `Data` か、コピー元（解決・判定済み）のどちらか。
    ///
    /// 2つに分けているのは、画像などのパススルーアセットで `FileManager.copyItem` を使うため。
    /// `copyItem` はパーミッションや拡張属性を保ったまま、APFS では実体コピーすらせずクローンする。
    /// バイト列を経由すると両方失うので、この場合は `Data` を作らない。
    private enum AssetContent {
        case data(Data)
        case file(ConfinedSource)
    }
```

`processNonStylesheet` を次に置き換える（シグネチャに `sourceRoot` が増え、冒頭で判定する）：

```swift
    /// 画像・その他。コピーのみなのでソースバイト＝出力バイト。
    ///
    /// `FileManager.copyItem` でコピーする（パーミッション・拡張属性を保ち、APFS ではクローンに
    /// なる）。JS だけは中身を書き換える必要があるためテキストとして読む。どちらも読む直前に
    /// `resolveConfinedSource` で閉じ込めを判定し直す。
    private func processNonStylesheet(
        _ fileURL: URL,
        relativePath: String,
        sourceRoot: String,
        destinationPath: String,
        manifest: inout AssetManifest
    ) throws {
        let source = try resolveConfinedSource(fileURL, sourceRoot: sourceRoot)
        switch processor.detectAssetType(for: fileURL.lastPathComponent) {
        case .javascript:
            let content = try String(contentsOf: source.url, encoding: .utf8)
            let data = Data(processor.processJS(content, options: jsOptions).utf8)
            try write(.data(data), relativePath: relativePath, destinationPath: destinationPath, manifest: &manifest)
        default:
            try write(.file(source), relativePath: relativePath, destinationPath: destinationPath, manifest: &manifest)
        }
    }
```

`processStylesheets` のシグネチャと読み込み行を変える：

```swift
    private func processStylesheets(
        _ stylesheets: [(url: URL, relativePath: String)],
        sourceRoot: String,
        destinationPath: String,
        manifest: inout AssetManifest
    ) throws {
        // 最小化まで済ませた内容を持ち回る。依存関係の抽出と書き換えが同じバイト列を見るため。
        // パス1の列挙からここまでの間にリンクが差し替えられていないか、読む直前に判定し直す。
        var contents: [String: String] = [:]
        var keys: [String] = []
        for stylesheet in stylesheets {
            let source = try resolveConfinedSource(stylesheet.url, sourceRoot: sourceRoot)
            let raw = try String(contentsOf: source.url, encoding: .utf8)
            contents[stylesheet.relativePath] = processor.processCSS(raw, options: cssOptions)
            keys.append(stylesheet.relativePath)
        }
```
（以降の本体は変更しない）

- [ ] **Step 5: `write` の `.file` 分岐から解決と壊れたリンクの guard を取り除く**

`write` 内の `case .file(let fileURL):` 分岐を次に置き換える。コメントのうち「コピー元は必ず解決してから読む」までの理由説明は残し、解決処理そのものは `resolveConfinedSource` に移ったことを書く。**ハッシュの位置はこのタスクでは変えない**（タスク 7 で変える）：

```swift
        case .file(let source):
            // `copyItem` はパーミッションと拡張属性を保ち、APFS では実体コピーせずクローンする。
            // ただし `copyItem` はシンボリックリンクをリンクのままコピーする。`static/` の中で
            // 完結するリンク（`AssetFileManager` が通すのはこれだけ）でも、出力側がリンクに
            // なると以下の問題を引き起こす。
            //
            // - `_site` を単体で持ち出す（アーカイブ・アップロードなど）と、リンクの解決先が
            //   出力ツリーの中にあるとは限らず、ファイルが失われる。
            // - フィンガープリント有効時、ハッシュはリンク先の実体を読んで計算する一方、
            //   書き込まれるのはリンクそのものになり、「ハッシュは書き込んだバイト列を覆う」
            //   という不変条件が壊れる。
            //
            // そのため `source.url` は `resolveConfinedSource` が解決し、壊れたリンクと
            // `static/` の外へ抜けるリンクはそこで弾いてある。
            //
            // 加えて、`removeItem` の後に `copyItem` する2段階だと、コピーが失敗した時点で
            // 直前の良い出力を失い、`serve` から見ればファイルが存在しない瞬間ができる
            // （パイプライン内の他の書き込みはすべて `.atomic` なのに、ここだけそうでない）。
            // 一時名へコピーしてから `replaceItemAt` で原子的に差し替えることで、パーミッション・
            // 拡張属性を保つという `copyItem` を選んだ理由を残したまま、両方を直す。
            let staging = outputURL.deletingLastPathComponent()
                .appendingPathComponent(".hirundo-\(UUID().uuidString)")
            defer {
                // 成功時は `replaceItemAt` が消費して既に存在しない。throw で抜けた場合だけ
                // 残っているので、原子的な差し替えの体裁を保つために掃除する。
                if fileManager.fileExists(atPath: staging.path) {
                    try? fileManager.removeItem(at: staging)
                }
            }
            try fileManager.copyItem(at: source.url, to: staging)
            // 既定では差し替え先（＝前回の出力）のメタデータが引き継がれるため、`static/` 側で
            // パーミッションを変えても非クリーン再ビルドに反映されない。`copyItem` が運んできた
            // ソース由来のメタデータを使う。
            _ = try fileManager.replaceItemAt(
                outputURL,
                withItemAt: staging,
                options: .usingNewMetadataOnly
            )
```

同じ `write` 内、フィンガープリント計算の `case .file(let fileURL):` も `source` に合わせる：

```swift
            case .file(let source):
                // ソースをストリーミングで読んでハッシュする。まるごとメモリに載せない。
                fingerprint = try processor.generateFingerprint(for: source.url)
```

- [ ] **Step 6: ビルドとテスト**

Run: `swift build 2>&1 | grep -E "warning|error"`
Expected: 出力なし

Run: `swift test --filter AssetPipelineTests 2>&1 | tail -5`
Expected: 全件 PASS（35 tests）。特に `testBrokenSymlinkedAssetThrowsInsteadOfCopyingTheLink`（guard の移動先で同じエラーになる）、`testSkipsAFileSymlinkPointingOutsideTheSourceDirectory`（列挙時の警告＋スキップはそのまま）、`testFollowsASymlinkThatStaysInsideTheSourceDirectory` が通ること。

Run: `swift test 2>&1 | tail -5`
Expected: 全件 PASS

- [ ] **Step 7: コミット**

```bash
git add Sources/HirundoCore/AssetPipeline.swift Tests/HirundoTests/AssetPipelineTests.swift
git commit -m "fix: re-check source containment immediately before every read

The enumerator's containment check and the actual read were separate
steps, and for CSS a whole pass apart, so a symlink retargeted in between
pulled content from outside static/ into the output. Every read path now
resolves and re-checks the source right before reading it, and records the
file's identity for the copy path to compare against."
```

---

### Task 7: H-1 (c) — ステージングファイルをハッシュし、コピー前後の識別情報を照合する

**Files:**
- Modify: `Sources/HirundoCore/AssetPipeline.swift`（`write` の再構成、`removeStaleSymlink` の抽出）
- Test: `Tests/HirundoTests/AssetPipelineTests.swift`
- Modify: `CHANGELOG.md`（`### Security` に追記）

**Interfaces:**
- Consumes: `ConfinedSource.identity`（タスク 6）、`FileIdentity`（タスク 5）、`AssetProcessor.generateFingerprint(for: URL) throws -> String`（既存）
- Produces: `private func removeStaleSymlink(at: URL) throws`

**背景:** 現状の `.file` 経路は、(1) `generateFingerprint(for:)` でソースを読んでハッシュ → (2) `copyItem` でもう一度読む、の2回読みで、間にファイルが変わると出力名のハッシュと実データが食い違う。ステージングへコピーしてから**そのステージングファイル**をハッシュすれば、ハッシュは差し替えるバイト列そのものを覆う。さらにコピー後に `FileIdentity` を照合し、判定からコピーまでの間に変わっていたら失敗させる。

- [ ] **Step 1: 「判定後に書き換えられたソースは失敗する」テストを書く**

`AssetPipelineTests.swift` の `testAStylesheetLinkRetargetedOutsideBetweenPassesIsRefused` の直後に追加する：

```swift
    /// 閉じ込め判定は通ったが、コピーの前にソースが書き換えられた。ハッシュ計算とコピーが
    /// 別々にソースを読む構造だと、出力名のハッシュと実データが食い違う。判定直後の識別情報と
    /// コピー直後の識別情報を比べて、変わっていたら失敗させる。
    func testASourceModifiedAfterItsContainmentCheckFailsTheCopy() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let sourceFile = sourceDir.appendingPathComponent("logo.png")
        try Data("original".utf8).write(to: sourceFile)

        let hooked = HookedAssetPipeline()
        hooked.enableFingerprinting = true
        hooked.afterResolving = { fileURL in
            guard fileURL.lastPathComponent == "logo.png" else { return }
            let handle = try FileHandle(forWritingTo: sourceFile)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(" + appended".utf8))
            try handle.close()
        }

        XCTAssertThrowsError(
            try hooked.processAssets(from: sourceDir.path, to: destDir.path),
            "判定後に書き換えられたソースがそのままコピーされている"
        ) { error in
            XCTAssertTrue(
                "\(error)".contains("changed while it was being copied"),
                "想定外のエラー: \(error)"
            )
        }

        // 失敗したときにステージングファイルが残っていないこと。
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
            .filter { $0.hasPrefix(".hirundo-") }
        XCTAssertTrue(leftovers.isEmpty, "ステージングファイルが残っている: \(leftovers)")
    }

    /// ハッシュはステージングファイル（差し替えるバイト列そのもの）から取る。ソースを2回読む
    /// 構造ではないことを、出力名のハッシュ＝出力バイト列のハッシュで固定する。
    func testPassThroughFingerprintCoversTheBytesActuallyWritten() throws {
        let sourceDir = tempDir.appendingPathComponent("source")
        let destDir = tempDir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let content = Data("pass-through bytes".utf8)
        try content.write(to: sourceDir.appendingPathComponent("logo.png"))

        pipeline.enableFingerprinting = true
        let manifest = try pipeline.processAssets(from: sourceDir.path, to: destDir.path)

        let outputRelativePath = try XCTUnwrap(manifest["logo.png"])
        let written = try Data(contentsOf: destDir.appendingPathComponent(outputRelativePath))
        XCTAssertEqual(
            outputRelativePath,
            "logo-\(AssetProcessor().generateFingerprint(for: written)).png",
            "出力名のハッシュが出力バイト列のハッシュと一致しない"
        )
    }
```

- [ ] **Step 2: 落ちることを確かめる**

Run: `swift test --filter AssetPipelineTests/testASourceModifiedAfterItsContainmentCheckFailsTheCopy 2>&1 | tail -10`
Expected: FAIL（「判定後に書き換えられたソースがそのままコピーされている」── 現状は識別情報を照合しないので throw しない）

Run: `swift test --filter AssetPipelineTests/testPassThroughFingerprintCoversTheBytesActuallyWritten 2>&1 | tail -5`
Expected: PASS（現状でも結果として一致する。これは再構成後の回帰を止めるためのテスト）

- [ ] **Step 3: `write` を再構成する**

`AssetPipeline.swift` の `write` 関数全体（doc コメント `/// 出力先の閉じ込め、ハッシュ、書き込み、マニフェストへの登録。` から関数の閉じ括弧まで）を次に置き換える：

```swift
    /// 出力先の閉じ込め、ハッシュ、書き込み、マニフェストへの登録。
    ///
    /// ハッシュ・書き込み・マニフェスト登録が1箇所に集まっているのが不変条件。「書き込んだバイト
    /// 以外の何か」をハッシュすることが構造的にできないのはこれのおかげなので、`AssetContent`
    /// で入力の形（メモリ上のデータか、コピー元ファイルか）を分けても、ハッシュ計算・書き込み・
    /// 登録という処理そのものは分岐させず、ここに置いたままにする。
    ///
    /// パススルー（`.file`）では、ハッシュを**ステージングファイル**から取る。ソースからハッシュを
    /// 取ってから別途コピーすると、その間にソースが変わったとき出力名のハッシュと実データが
    /// 食い違う（`serve` 中の編集で起きる）。ステージングは差し替えるバイト列そのものなので、
    /// そこから取れば不変条件が構造的に守られる。
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

        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let shouldFingerprint = enableFingerprinting && allowFingerprint
            && !fingerprintExclusions.excludes(relativePath)

        let outputURL: URL
        switch content {
        case .data(let data):
            outputURL = shouldFingerprint
                ? URL(fileURLWithPath: processor.addFingerprint(
                    to: candidateURL.path,
                    fingerprint: processor.generateFingerprint(for: data)
                ))
                : candidateURL
            try removeStaleSymlink(at: outputURL)
            try data.write(to: outputURL, options: .atomic)

        case .file(let source):
            // `copyItem` はパーミッションと拡張属性を保ち、APFS では実体コピーせずクローンする。
            // ただし `copyItem` はシンボリックリンクをリンクのままコピーする。`static/` の中で
            // 完結するリンク（`AssetFileManager` が通すのはこれだけ）でも、出力側がリンクに
            // なると以下の問題を引き起こす。
            //
            // - `_site` を単体で持ち出す（アーカイブ・アップロードなど）と、リンクの解決先が
            //   出力ツリーの中にあるとは限らず、ファイルが失われる。
            // - フィンガープリント有効時、ハッシュはリンク先の実体を読んで計算する一方、
            //   書き込まれるのはリンクそのものになり、「ハッシュは書き込んだバイト列を覆う」
            //   という不変条件が壊れる。
            //
            // そのため `source.url` は `resolveConfinedSource` が解決し、壊れたリンクと
            // `static/` の外へ抜けるリンクはそこで弾いてある。
            //
            // `removeItem` の後に `copyItem` する2段階だと、コピーが失敗した時点で直前の良い
            // 出力を失い、`serve` から見ればファイルが存在しない瞬間ができる（パイプライン内の
            // 他の書き込みはすべて `.atomic` なのに、ここだけそうでない）。一時名へコピーして
            // から `replaceItemAt` で原子的に差し替える。
            let staging = parentURL.appendingPathComponent(".hirundo-\(UUID().uuidString)")
            defer {
                // 成功時は `replaceItemAt` が消費して既に存在しない。throw で抜けた場合だけ
                // 残っているので、原子的な差し替えの体裁を保つために掃除する。
                if fileManager.fileExists(atPath: staging.path) {
                    try? fileManager.removeItem(at: staging)
                }
            }
            try fileManager.copyItem(at: source.url, to: staging)

            // 閉じ込め判定の直後に取った識別情報と、コピー直後の識別情報を比べる。違っていれば
            // 判定からコピーまでの間にソースが差し替えられたか書き換えられたということで、
            // コピーしたバイト列は判定したファイルのものではない。黙って出さずに失敗させる
            // （`serve` なら次の変更検知で再ビルドされる）。
            let identityAfterCopy = try FileIdentity(ofItemAtPath: source.url.path)
            guard identityAfterCopy == source.identity else {
                throw AssetPipelineError.processingFailed(
                    "Asset source changed while it was being copied: \(source.url.path)"
                )
            }

            // ハッシュはステージングファイルから取る。これから差し替えるバイト列そのもの。
            outputURL = shouldFingerprint
                ? URL(fileURLWithPath: processor.addFingerprint(
                    to: candidateURL.path,
                    fingerprint: try processor.generateFingerprint(for: staging)
                ))
                : candidateURL
            try removeStaleSymlink(at: outputURL)
            // 既定では差し替え先（＝前回の出力）のメタデータが引き継がれるため、`static/` 側で
            // パーミッションを変えても非クリーン再ビルドに反映されない。`copyItem` が運んできた
            // ソース由来のメタデータを使う。
            _ = try fileManager.replaceItemAt(
                outputURL,
                withItemAt: staging,
                options: .usingNewMetadataOnly
            )
        }

        // マニフェストの値は「実際に書いた場所」でなければならない。途中のディレクトリが
        // 出力ツリー内のシンボリックリンクなら、値は解決先（実体）の側になる ── 掃除
        // （`AssetPruner`）も同じく実体側の相対パスで「残すもの」を判定するため、ここで
        // 食い違うと書いたばかりのファイルが掃除で消える。
        manifest[relativePath] = outputDirectory.isEmpty
            ? outputURL.lastPathComponent
            : outputDirectory + "/" + outputURL.lastPathComponent
    }

    /// 出力先にシンボリックリンクが残っていると（以前のバージョンが書き出した `_site` が
    /// まさにそれ）、`replaceItemAt` は "file doesn't exist" で失敗する。最後の要素は
    /// 置き換える対象であって辿る対象ではないので、どちらの書き込み経路でも先に取り除いて
    /// おき、非クリーン再ビルドで自己修復させる。`attributesOfItem` は `lstat` 相当で
    /// リンクを辿らないため、壊れたリンクも判定できる。
    private func removeStaleSymlink(at outputURL: URL) throws {
        if let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path),
           attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            try fileManager.removeItem(at: outputURL)
        }
    }
```

- [ ] **Step 4: ビルドとテスト**

Run: `swift build 2>&1 | grep -E "warning|error"`
Expected: 出力なし

Run: `swift test --filter AssetPipelineTests 2>&1 | tail -5`
Expected: 全件 PASS（37 tests）。特に以下が通ること：
- `testSymlinkedAssetIsCopiedAsARegularFile...`（タスク 1 の隣、名前ハッシュ＝リンク先バイト列のハッシュ）
- `testSecondBuildAfterASymlinkedAssetDoesNotThrow`（タスク 1 で本物にしたもの）
- `testBuildOverAnOutputLeftAsASymlinkRecovers`（`removeStaleSymlink` の抽出後も自己修復する）
- `testPassThroughPermissionChangeReachesANonCleanRebuild`（`.usingNewMetadataOnly` を維持）
- `testWriteThroughASymlinkedOutputDirectoryIsRefused`（閉じ込め判定を動かしていない）

Run: `swift test 2>&1 | tail -5`
Expected: 全件 PASS

- [ ] **Step 5: CHANGELOG に追記する**

`CHANGELOG.md` の `## [Unreleased]` 配下 `### Security` の**先頭**に追加する：

```markdown
- **SECURITY**: a pass-through asset was read three times by three separate calls — hashed from the source, then the source was resolved again, then copied — so a file that changed in between shipped under a hash that did not describe its bytes, and a symlink retargeted after the enumerator's containment check could pull content from outside `static/` into the output (for CSS the read happens a whole pass after enumeration, so that window was wide). Every read path now resolves and re-checks containment immediately before reading; a pass-through asset is copied to its staging file first and the hash is taken over the staging file's bytes, the exact bytes that get swapped in; and the source's identity (device, inode, size, mtime) recorded at the containment check is compared again after the copy, failing the build with `Asset source changed while it was being copied` if it differs. The remaining window is the few microseconds between the check and the `stat`; closing it entirely would need a descriptor-based copy, which `copyItem` (kept for its permission, xattr and APFS-clone behaviour) does not offer
```

- [ ] **Step 6: コミット**

```bash
git add Sources/HirundoCore/AssetPipeline.swift Tests/HirundoTests/AssetPipelineTests.swift CHANGELOG.md
git commit -m "fix: hash the staged copy and verify the source did not change under it

Hashing the source and then copying it read the file twice, so a change in
between shipped bytes under a hash that did not describe them. Copy to the
staging file first and hash that; compare the source's identity recorded
at the containment check against the one after the copy and fail if they
differ."
```

---

### Task 8: 仕上げ — 全体の検証とレビュー文書の更新

**Files:**
- Modify: `docs/reviews/2026-09-06-fingerprint-exclusions-codex-review.md`（検証状況の表）

- [ ] **Step 1: クリーンな状態で全テストを回す**

Run: `swift build 2>&1 | grep -E "warning|error"; swift test 2>&1 | tail -5`
Expected: 警告なし、全件 PASS

- [ ] **Step 2: 実サイトでスモークテスト**

```bash
cd test-site && swift run --package-path .. hirundo build --clean 2>&1 | tail -5 && cd ..
```
Expected: エラーなし。`test-site/_site/` に出力がある（`config.yaml` の `features.fingerprint` が有効ならハッシュ付き名）。

- [ ] **Step 3: レビュー文書の「検証状況」表を更新する**

`docs/reviews/2026-09-06-fingerprint-exclusions-codex-review.md` の「検証状況」表の H-1 行を次に置き換える：

```markdown
| H-1: TOCTOU | `HookedAssetPipeline` で列挙後のリンク差し替え・判定後の書き換えを決定的に再現するテストを追加（`AssetPipelineTests`）。ステージングファイルをハッシュする構造に変更 | 対応済み（本計画タスク 5〜7） |
```

「不足しているテスト」節の3項目それぞれの末尾に ` → 追加済み` を付ける。

- [ ] **Step 4: コミット**

```bash
git add docs/reviews/2026-09-06-fingerprint-exclusions-codex-review.md
git commit -m "docs: record the Codex review findings as addressed"
```

---

## Self-Review（作成時に実施済み）

**Spec coverage:**
- H-1（ハッシュとコピーの別スナップショット / symlink 境界の競合）→ タスク 5, 6, 7
- M-1（`**` の組合せ爆発）→ タスク 3
- M-2（`AssetItem` の互換層）→ タスク 4（ユーザー決定: deprecated シム）
- L-1（`ads.txt` 重複でテストが空振り）→ タスク 2
- L-2（symlink テストがソース外を指す）→ タスク 1
- 不足テスト 3 件（ハッシュ後の変更 / 判定後のリンク差し替え / `**` の時間上限）→ タスク 7, 6, 3

**意図的に対象外:**
- Codex の M-1 修正方針にある「パターン数・長さ・セグメント数の上限」は入れない。DP 化で計算量が多項式になり、上限は防御の重複になる。`config.yaml` の構造上、パターン数が問題になる規模には現実的にならない
- fd ベースの完全な TOCTOU 封鎖は入れない（理由は `FileIdentity` の doc コメントと CHANGELOG に記載）

**Type consistency:**
- `ConfinedSource { url: URL; identity: FileIdentity }` はタスク 6 で定義し、タスク 7 の `write` が `source.url` / `source.identity` で参照
- `resolveConfinedSource(_:sourceRoot:) throws -> ConfinedSource` はタスク 6 で定義、`HookedAssetPipeline` が同じシグネチャで override
- `FileIdentity(ofItemAtPath:)` はタスク 5 で定義、タスク 6・7 で使用
- `removeStaleSymlink(at:)` はタスク 7 で定義・使用（`private`）
- テスト数の期待値: `AssetPipelineTests` は現在 33 → タスク 6 で +2 = 35 → タスク 7 で +2 = 37。`AssetFingerprintExclusionsTests` は 27 → 28。`AssetFingerprintIntegrationTests` は 10 → 11

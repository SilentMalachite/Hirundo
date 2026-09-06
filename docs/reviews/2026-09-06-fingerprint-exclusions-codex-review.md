# Codex コードレビュー: フィンガープリント除外 / アセットパイプライン

- **実施日**: 2026-09-06
- **レビュー実行**: Codex (openai-codex plugin, read-only モード)
- **対象差分**: `git diff 7e22c07^1...7e22c07`（`Merge branch 'feat/fingerprint-exclusions'` で取り込まれたブランチ側の変更）
- **規模**: 30ファイル / +1,578行
- **重点観点**: フィンガープリント除外ロジック、HTML/CSS 参照書き換え、パストラバーサル / シンボリックリンク境界、テストカバレッジ

## サマリ

| 深刻度 | 件数 |
|--------|------|
| CRITICAL | 0 |
| HIGH | 1 |
| MEDIUM | 2 |
| LOW | 2 |

HTML/CSS の依存順・参照書き換えについては、この差分で新たに導入された確定的な不具合は見つかっていません。

---

## HIGH

### H-1. ハッシュ計算とコピーが別スナップショットを参照している（TOCTOU）

**該当箇所**

- `Sources/HirundoCore/AssetPipeline.swift:331`
- `Sources/HirundoCore/AssetPipeline.swift:383`
- `Sources/HirundoCore/AssetPipeline.swift:401`
- `Sources/HirundoCore/Assets/AssetFileManager.swift:71`

**なぜ問題か**

パススルーアセットの処理は、同じファイルを3回別々にディスクから触っています。

1. `generateFingerprint(for:)` でファイルを読んでハッシュを計算する
2. その後 `fileURL.resolvingSymlinksInPath()` を再実行する
3. `copyItem` でもう一度読んでコピーする

このため次の2つの問題が起きます。

- **ハッシュと実データの不一致**: 1 と 3 の間にファイルが更新されると、出力ファイル名に埋め込まれたハッシュと、実際に公開されるバイト列が食い違います。`hirundo serve` 中の編集や外部の同期処理で発生し得て、「内容が変わればURLが変わる」というフィンガープリントの契約（キャッシュ破棄）が壊れます。
- **symlink 境界の迂回**: `static/` 内への包含判定は列挙時に `AssetFileManager` 側で先に行われますが、実際のコピー時にリンクを再解決して包含性を再検証していません。判定後に symlink が外部ファイルへ差し替えられると、`static/` 外の内容をステージングファイルへコピーできてしまいます。典型的な check-to-use 競合です。

**修正方針**

検証・ハッシュ・コピーを同一スナップショットに統合する。

- 検証済みソースからまず**ステージング用の通常ファイル**を作り、**そのステージングファイルのバイト列をハッシュ**して最終出力名を決める（読み込みを1回に集約する）
- symlink 境界を厳密に守るには、パスを別々に再解決するのではなくディスクリプタベースで対象を固定する。少なくともコピー前後のファイル識別情報（inode / device / mtime / size）を検証し、変化していれば失敗させる

---

## MEDIUM

### M-1. 複数の非連続 `**` によりパターン照合が組合せ爆発する

**該当箇所**

- `Sources/HirundoCore/Assets/AssetFingerprintExclusions.swift:110`
- `Sources/HirundoCore/Assets/AssetFingerprintExclusions.swift:114`

**なぜ問題か**

`**` ごとに `0...path.count` の全候補を再帰探索し、各再帰で `Array(dropFirst(...))` による配列コピーも発生します。連続する `**` は畳み込まれますが、`**/x/**/x/**/z` のような**非連続**パターンでは同じ状態を何度も再探索するため、パターン数とパス深度に対して指数的に遅くなります。

`assets.fingerprintExclude` は `config.yaml` から自由に指定できるため、悪意のある、あるいは単に誤った設定を含むリポジトリを CI でビルドすると、CPU・メモリ消費によってビルドが停止します。

**修正方針**

- `(patternIndex, pathIndex)` を状態とするメモ化探索に変更する
- 配列を切り出さず添字で走査する（`Array(dropFirst())` を廃止）
- 併せて、パターン数・パターン長・セグメント数に上限を設ける

### M-2. 公開されていた `AssetItem` と `AssetItem.AssetType` を互換層なしで削除している

**該当箇所**

- `Sources/HirundoCore/ContentModels.swift:80`
- `Sources/HirundoCore/AssetPipeline.swift:110`

**なぜ問題か**

変更前の `AssetItem` は `public struct AssetItem: Sendable` であり、ネストされた `AssetItem.AssetType` も公開 API でした。この差分はそれらを削除し、トップレベルの `AssetType` に置き換えています。外部クライアントが `AssetItem` を生成している場合や、`AssetItem.AssetType` を型注釈に使っている場合はコンパイルできなくなります。フィンガープリント除外という機能追加には不要な破壊的変更です。

**修正方針**

- 少なくとも互換期間は `AssetItem` を残し、ネスト型を `typealias AssetType = HirundoCore.AssetType` 相当で橋渡ししたうえで deprecated にする
- 完全削除は次のメジャー（破壊的）バージョンで行う

---

## LOW

### L-1. 設定配線の統合テストが、組み込み除外との重複により常に成功する

**該当箇所**

- `Tests/HirundoTests/AssetFingerprintIntegrationTests.swift:194`
- `Tests/HirundoTests/AssetFingerprintIntegrationTests.swift:211`
- `Sources/HirundoCore/Assets/AssetFingerprintExclusions.swift:29`

**なぜ問題か**

テストは「`ads.txt` は組み込みパターンではないため、設定配線を削除すれば失敗する」という前提で書かれていますが、このマージ結果では `ads.txt` が組み込み除外リストに含まれています（`AssetFingerprintExclusions.swift:29`）。そのため、`SiteGenerator` から `config.assets.fingerprintExclude` の配線を完全に削除してもテストが成功してしまい、配線の回帰を検出できません。

**修正方針**

- 組み込みリストに存在しない固有名（例: `keep-stable.custom`）を設定値とフィクスチャに使う
- 同名ファイルを設定なしでビルドした場合は**ハッシュされる**という対照ケースも追加する

### L-2. 「symlink アセットの2回目のビルド」テストが対象ファイルを一度も処理していない

**該当箇所**

- `Tests/HirundoTests/AssetPipelineTests.swift:278`
- `Tests/HirundoTests/AssetPipelineTests.swift:286`
- `Sources/HirundoCore/Assets/AssetFileManager.swift:71`

**なぜ問題か**

テストはリンク先を `tempDir/shared`（`source` の兄弟ディレクトリ）に作っています。これは `static/` 相当のソースルート外なので、`AssetFileManager` の包含判定によって**両方のビルドとも列挙段階でスキップ**されます。したがって `XCTAssertNoThrow` は、出力の自己修復や2回目の置換処理を一切通らないまま成功しており、意図した回帰（`Output path escapes destination directory`）を固定できていません。

**修正方針**

- リンク先を `source/shared` 内に置く
- 1回目に通常ファイルとして出力されたこと、2回目にもマニフェストと出力内容が正しいことを検証する

---

## 検証状況

| 指摘 | 確認方法 | 結果 |
|------|----------|------|
| L-1: `ads.txt` が組み込み除外に含まれる | `AssetFingerprintExclusions.swift:29` を確認 | 確認済み |
| M-2: `AssetItem` が変更前は `public` だった | `git show 7e22c07^1:Sources/HirundoCore/ContentModels.swift` で `public struct AssetItem: Sendable` を確認 | 確認済み |
| M-2: 現在 Sources から消えている | `grep -rn "AssetItem" Sources/` がヒット0 | 確認済み |
| L-2: リンク先が `source` の外 | `AssetPipelineTests.swift:286` 付近を確認 | 確認済み |
| H-1: TOCTOU | 静的レビューのみ。再現テストは未実施 | **未検証** |

Codex は read-only 制約を維持するため `swift test` を実行していません（テンポラリファイルと `.build` を書き換えるため）。作業ツリーへの変更・コミットも行っていません。

## 不足しているテスト

- ハッシュ計算後にソースファイルを変更し、出力名のハッシュと実データが一致しなくなることを再現するテスト（H-1）
- 包含判定後に symlink を外部ファイルへ差し替える TOCTOU テスト（H-1）
- 非連続 `**` パターンに対する照合時間の上限テスト（M-1）

## 参考

- Codex session ID: `01a075bd-04ad-7ec2-b077-776b8ba5036a`
- 再開: `codex resume 01a075bd-04ad-7ec2-b077-776b8ba5036a`

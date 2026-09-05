# AssetPipeline: フィンガープリントと参照書き換え — 設計

- 日付: 2026-09-06
- 対象: `Sources/HirundoCore/AssetPipeline.swift` および `Sources/HirundoCore/Assets/`
- 状態: 設計合意済み。実装計画はこの spec から起こす

## 背景

`AssetPipeline` には、`config.yaml` から到達できない機能が半分だけ実装された状態で残っている。
`AssetPipeline.swift` の冒頭コメントが4つの欠陥を列挙しており、本 spec はそれに調査で見つけた
3つを加えた計7つを対象にする。

| # | 欠陥 | 現在の場所 |
|---|------|-----------|
| 1 | 参照を書き換える処理がどこにも無い。フィンガープリントしたアセットはどのページも読み込まない | `SiteGenerator.processStaticAssets` はマニフェストを書くだけで終わる |
| 2 | ハッシュ対象が**ソース**バイト、書き出すのは**処理後**バイト。ハッシュが名前の対象を識別していない | `AssetPipeline.swift` の `generateFingerprint(for: fileURL)` と `AssetProcessor.processAssetContent` |
| 3 | 結合ルールの照合が二箇所で食い違う。`js/*.js` は束ねた上で元ファイルも出力し、`*.js` は元ファイルを全部落とす | `AssetFileManager.findFiles` はパターン末尾をファイル名にだけ照合、`isConcatenatedFile` はパターンを相対パス全体に照合 |
| 4 | ソースマップはどの経路でも生成されない | `CSSProcessingOptions.sourceMap` / `JSProcessingOptions.sourceMap` を読む箇所がゼロ |
| 5 | 結合の出力は最小化を通らない | `AssetConcatenator.processConcatenationRules` が `processCSS` / `processJS` を呼ばない |
| 6 | フィンガープリント無効時、結合の出力はマニフェストに載らない | 同上、`manifest[...]` の代入が `enableFingerprinting` の中にしかない |
| 7 | 古いハッシュ名の出力が消えない。`serve` は非 clean 再ビルドなので出力が膨れ続ける | 掃除する処理が存在しない |

加えて `JSProcessingOptions.transpile` / `target` は、警告を出して入力をそのまま返す
`AssetProcessor.transpileJS` にしか繋がっておらず、`config.yaml` からも到達しない。

## スコープ

**実装する** — 欠陥 1・2・7、およびマニフェスト形式の修正。

**削除する** — 欠陥 3・4・5・6 は「機能ごと消す」ことで解消する。結合は HTTP/2 以降に価値が薄く、
ソースマップは正規表現ベースの自作 minifier が位置情報を持たない以上、minifier をトークナイザ化
するところからの作業になり、割に合わない。あわせて、同じ「config から到達しない未到達コード」
である `transpile` / `target` も削除する。

**対象外** — 最小化アルゴリズムそのものの改善、画像最適化、`autoprefixer`（これは実際に動作するので
残す）、`excludePatterns`（ライブラリ API としては仕様どおり動くので残す。ただしファイル名にしか
照合しない点をコメントで明記する）。

## 設定面

`features` に真偽値を1つ足すだけで、`build:` には削除された4キーを戻さない。

```yaml
features:
  fingerprint: true    # 追加。デフォルト false
```

- `Features` に `fingerprint: Bool` を追加し、`CodingKeys` にも足す
- `Features.init(from:)` は既に各キーを独立して `decodeIfPresent` しているので、既存の
  `features:` ブロックは無変更のまま動く
- `ConfigDiagnostics` は鍵集合を `Features.CodingKeys.allCases` から導出しているため、
  `hirundo validate` は自動的に新しいキーを認識する。差分は不要
- `hirundo init` が生成する config（`ScaffoldTemplates`）に `fingerprint: false` を1行追加

## アーキテクチャ

### ビルド順序

`finalizationSteps` に1ステップ追加する。個別ページ・archive・categories・tags はいずれも
`static assets` より前に書き終わっているので、`static assets` の直後に置けば出力ツリーの全 HTML が
対象になる。

```
processContent            (個別ページの HTML を出力)
finalizationSteps:
  archive
  categories
  tags
  static assets           (パス1: CSS 以外 → パス2: CSS。マニフェストを確定し、prune も行う)
  asset references        ← 新設（パス3: HTML）。features.fingerprint が true のときだけ追加される
  sitemap.xml             (.html しか拾わないので影響なし)
  rss.xml
  search-index.json
```

`build` と `buildWithRecovery` は同じ `finalizationSteps` を回すので、`hirundo build` と
`hirundo serve` の再ビルドの双方に自動的に効く。

`features.fingerprint` が false のときは `asset references` ステップを**追加しない**。
マニフェストの値がキーと同一になり書き換えが全て no-op になるため、`serve` の再ビルドごとに
出力ツリーを読み直す I/O を払う理由が無い。

### 新規ファイル

| ファイル | 責務 | 依存 |
|---|---|---|
| `Assets/AssetManifest.swift` | キー/値の型、参照文字列の解決とキー照合（純粋、I/O 無し） | Foundation のみ |
| `Assets/AssetReferenceRewriter.swift` | 文字列 + マニフェスト + 基準ディレクトリ → 文字列（純粋、I/O 無し） | `AssetManifest` |
| `Assets/AssetPruner.swift` | 出力ツリーから古いフィンガープリント出力を削除 | FileManager |

書き換えの中核を純粋関数に切ることで、テストがファイルシステムを必要としなくなる。
ファイルの読み書きは `SiteGenerator` 側の新しいステップが担う。

### 削除するファイルとシンボル

| 対象 | 種別 |
|---|---|
| `Assets/AssetConcatenator.swift` | ファイルごと削除 |
| `Assets/AssetConcatenationRule.swift` | ファイルごと削除 |
| `AssetPipeline.concatenationRules` | public プロパティ削除 |
| `AssetPipeline.enableSourceMaps` | public プロパティ削除 |
| `CSSProcessingOptions.sourceMap` | public プロパティ削除（`init` の引数も） |
| `JSProcessingOptions.sourceMap` / `transpile` / `target` | public プロパティ削除（`init` の引数も） |
| `AssetProcessor.transpileJS` と `processJS` の `if options.transpile` 分岐 | private メソッド削除 |
| `AssetFileManager.findFiles` / `isConcatenatedFile` | public / private メソッド削除 |
| `AssetFileManager.processDirectory` の `concatenationRules` 引数 | シグネチャ変更 |
| `AssetPipelineTests.testAssetConcatenation` | テスト削除 |

## 詳細仕様

### マニフェスト

キー = static ディレクトリからの相対パス、値 = 出力ディレクトリからの相対パス。

```
"css/style.css"      → "css/style-9f2a1c04b7e3d5a1.css"
"images/logo.png"    → "images/logo-1b4d0f77c2ae8e93.png"
```

- 現行は値が `outputURL.lastPathComponent`（`style-9f2a1c04b7e3d5a1.css`）で、ディレクトリが
  落ちているため書き換えに使えない。**出力ディレクトリからの相対パスに直す**
- フィンガープリント無効時も全アセットをマニフェストに載せる（値 == キー）。掃除と書き換えの
  両方が「マニフェストが出力の完全な目録である」ことに依存するため
- ディスク上の `_site/asset-manifest.json` を書くのは `features.fingerprint` が true のときだけ。
  現行の `!manifest.isEmpty` という条件は、常に真になるので明示的な条件に置き換える

### フィンガープリント（欠陥2）と処理の3パス構成

**ハッシュは必ず「そのファイルの最終的な出力バイト列」に対して取る。** 現行はソースバイトを
ハッシュして処理後バイトを書いており、これが欠陥2そのものである。

ここで順序の依存が生まれる。CSS の最終バイト列は、その中の `url(...)` を書き換えた**後**にしか
確定しない。そして `url(...)` の書き換えには、参照先（画像・フォント）のハッシュ名が既に確定して
いる必要がある。したがってアセット処理を3つのパスに分ける。

**パス1 — CSS 以外**（画像・JS・その他）
`AssetProcessor` の処理を適用し、その結果をハッシュして書き出し、マニフェストに登録する。
コピーのみで済むもの（画像その他）はソースバイト = 出力バイトなので、ソースをストリーミングで
読んでハッシュしながらコピーし、巨大な画像を丸ごとメモリに載せない。

**パス2 — CSS**
最小化などを適用 → パス1で確定したマニフェストで `url(...)` を書き換え → **その結果**をハッシュ
→ 書き出し、マニフェストに登録する。

**パス3 — HTML**
完成したマニフェストで出力ツリーの HTML を書き換える。これが `asset references` ステップに当たる。
HTML は自身がフィンガープリントの対象ではないので、書き換え後に再ハッシュする必要はない。

ハッシュ形式は現行のまま（SHA-256 の先頭 16 桁 hex）。出力名は `<name>-<hash>.<ext>`。
`AssetProcessor.processAssetContent` は「処理して書き込む」API なので削除し、
「処理結果を返すが書き込まない」API に置き換える。書き込みは `AssetPipeline` 側が行う。

この修正により、`features.minify` の ON/OFF がハッシュに反映される（現在は反映されない）。

**既知の制限 — CSS が CSS を参照する場合**: パス2は全 CSS を同時に扱うため、
`@import url("other.css")` のような CSS → CSS 参照は解決できない（参照先のハッシュ名がまだ
確定していない）。この参照は**無変更で残し、stderr に警告を1行出す**。トポロジカル順に
処理すれば解けるが、静的サイトの CSS でこの形が現れることは稀であり、実装量に見合わない。
README と CLAUDE.md に制限として記載する。

### 参照の解決規則

`AssetManifest` が担う。入力は「参照文字列」と「その参照を含むファイルの出力ディレクトリからの
相対ディレクトリ」。

**スキップする参照**（無変更で返す）:

- スキームを持つもの — `http:` `https:` `data:` `mailto:` `tel:` など、`:` が最初の `/` `?` `#`
  より前に現れるもの
- プロトコル相対 — `//example.com/x.css`
- フラグメントのみ — `#main`
- 空文字列

**分解**: `path?query#fragment` に分け、`path` だけを照合に使う。`?query` と `#fragment` は
書き換え後にそのまま再結合する。

**キー候補の算出**:

- `/` 始まり（サイトルート相対）: 先頭の `/` を落としたものがキー候補
- それ以外（相対）: 参照元ファイルの出力相対ディレクトリと連結し、`.` と `..` を解決した結果が
  キー候補。出力ルートの外に出る場合はスキップ

**置換**: キー候補がマニフェストに無ければ無変更。あれば値（出力相対パス）を、元の参照の形に
合わせて書き戻す。

- 元が `/` 始まり → `/` + 値
- 元が相対 → 参照元ファイルの出力相対ディレクトリから値への相対パスを再計算

### 書き換え対象

**HTML**（`.html` / `.htm`）: タグ内の属性値のうち `href` / `src` / `srcset`（属性名は大文字小文字
を区別しない）。`srcset` はカンマ区切りの各候補について、先頭の URL 部分だけを解決し、
`1.5x` / `800w` などの記述子はそのまま残す。

**CSS**（`.css`）: `url(...)` の中身。引用符（`"` `'`）の有無と前後の空白の両方に対応する。
裸の `@import "..."` は対象外（`@import url(...)` の形は自動的に含まれるが、参照先が CSS の場合は
上記「既知の制限」のとおり警告して無変更で残す）。

**HTML 内の CSS**: CSS 書き換え器を `<style>` の本文と `style` 属性の値にも適用する。
HTML はフィンガープリントの対象ではないので、ここでの書き換えはハッシュに影響しない。

**JavaScript は対象外**: JS 内の文字列リテラル（`fetch("/images/x.png")` など）は書き換えない。
静的解析で参照かどうかを判定できないため。JS からアセットを参照する場合は、フィンガープリント
を有効にした構成では `asset-manifest.json` を読む必要がある。README に記載する。

**安全性の担保**: 書き換え器は入力を**逐語的にコピー**し、マニフェストのキーに解決できた属性値
だけを差し替える。HTML を再シリアライズしない。したがって走査が誤っても、起こり得るのは
「書き換えそこねる」か「本来対象でない文字列を書き換える」だけで、無関係なバイトが壊れることは
構造上あり得ない。加えて `<script>` と `<style>` の本文、および `<!-- -->` コメントは走査を
スキップし、`a<b` のような本文中の `<` をタグ開始と誤認する余地を減らす。

### 掃除 / prune（欠陥7）

`features.fingerprint` が true のときだけ、`static assets` ステップの中でマニフェスト確定直後に
実行する。

**削除対象は次の3条件を全て満たすファイルのみ**:

1. 出力ツリー内で、`static/` のトップレベル要素に対応するパスの配下にあること
   （`static/css/` があるなら `_site/css/**`、`static/robots.txt` があるなら `_site/robots.txt`）
2. ベース名がフィンガープリント形（`<name>-<16桁の16進数>.<ext>`）であること
3. 現在のマニフェストの値集合に含まれないこと

条件2があるため、`content/css/foo.md` が `_site/css/foo/index.html` を生む、といったパスの衝突が
あってもページ出力を削除することは**構造上あり得ない**。`_site/index.html`、`sitemap.xml`、
`asset-manifest.json` も同様に対象外。空になったディレクトリは削除しない（無害なため）。

## エラー処理

- `asset references` は `finalizationSteps` の一員なので、`build` では最初の失敗でビルドが止まり、
  `buildWithRecovery` では `.writing` ステージのエラーとして記録され、後続のステップは続行する。
  ステップ名は `"asset references"`
- UTF-8 として読めないファイルはスキップする（バイナリを壊さない）
- マニフェストに解決できない参照は無変更で通す。警告も出さない。外部 URL やまだ置いていない
  アセットへの参照はよくあることで、ビルドのたびに騒ぐ価値が無い
- prune の削除が失敗した場合はステップのエラーとして扱う

## 破壊的変更

`AssetPipeline` とその周辺は public API なので、以下は SemVer 上の破壊的変更として
`CHANGELOG.md` の `[Unreleased]` に記載する。

- `AssetConcatenator` と `AssetConcatenationRule` の削除
- `AssetPipeline.concatenationRules` / `enableSourceMaps` の削除
- `CSSProcessingOptions.sourceMap`、`JSProcessingOptions.sourceMap` / `transpile` / `target` の削除
- `AssetFileManager.findFiles` の削除、`processDirectory` のシグネチャ変更
- `AssetPipeline.processAssets` が返すマニフェストの値が、ファイル名から出力相対パスに変わる

`config.yaml` に対する破壊的変更は無い。`features.fingerprint` はデフォルト false で、既存の
設定ファイルの意味は変わらない。

## テスト計画

TDD で進める。各項目は RED を先に書く。

**`AssetReferenceRewriterTests`**（純粋関数、ファイルシステム不要）

- ルート絶対参照 `/css/style.css` の置換
- 相対参照 `../css/style.css` の置換と、置換後も相対形が保たれること
- `?v=1` と `#icon` の保持
- `http://` / `https://` / `//cdn` / `data:` / `mailto:` / `#main` のスキップ
- `srcset` の複数候補と記述子（`1.5x`, `800w`）の保持
- CSS `url(...)` の引用符あり・なし・空白あり
- マニフェストに無い参照が無変更で通ること
- `<script>` 本文と HTML コメントの属性を走査しないこと
- `<style>` 本文と `style` 属性の `url(...)` が書き換わること
- JS ファイルが一切書き換わらないこと
- 出力ルートの外に出る相対参照をスキップすること

**`AssetManifestTests`**

- 値が bare filename ではなくディレクトリ付きの出力相対パスであること
- `features.minify` の ON / OFF でハッシュが変わること（欠陥2の回帰テスト）
- 画像はソースのハッシュ = 出力のハッシュであること
- フィンガープリント無効時も全アセットが載り、値がキーと等しいこと
- **CSS のハッシュが `url(...)` 書き換え後のバイト列に対して取られていること** — 参照先の画像
  だけを差し替えると CSS のハッシュも変わる、という形で検証する（3パス構成の回帰テスト）
- CSS → CSS の `@import url(...)` が無変更で残り、警告が出ること

**`AssetPrunerTests`**

- 古いハッシュ名の出力が消えること
- HTML・`sitemap.xml`・`asset-manifest.json`・非フィンガープリント名のファイルが消えないこと
- `content/` 由来で `static/` のトップレベル名と衝突する出力（`_site/css/foo/index.html`）が
  消えないこと

**統合テスト**

- `features.fingerprint: true` でビルドし、`_site/index.html` の `href` が**実在するファイル**を
  指すこと。これが現在まさに壊れている挙動であり、この spec の存在理由
- `BuildWithRecoveryCompletenessTests` に fingerprint 経路を追加し、`serve` の再ビルドでも
  書き換えが走ることを確認する
- 非 clean 再ビルドを2回行い、出力に残るアセットが1世代分だけであること

**既存テストの更新**

- `AssetPipelineTests.testAssetConcatenation` を削除
- `AssetPipelineTests.testAssetFingerprinting` / `testAssetManifest` をマニフェストの新しい値の形
  に合わせて更新

## ドキュメント更新

- `README.ja.md` / `README.md` の「未実装の項目」— フィンガープリントの行を実装済みとして書き直し、
  結合とソースマップは「削除した」と明記する
- `CLAUDE.md` の `features` の表と YAML 例に `fingerprint` を追加
- `README.ja.md` / `README.md` に `fingerprint` の制限を明記 — JS 内の参照は書き換えない、
  CSS → CSS の `@import url(...)` は書き換えない
- `AssetPipeline.swift` 冒頭の欠陥リストのコメントを削除し、`excludePatterns` がファイル名にのみ
  照合する点を残す
- `CHANGELOG.md` の `[Unreleased]` に Added（`features.fingerprint` と参照書き換え）、
  Removed（結合・ソースマップ・transpile）、Fixed（ハッシュ対象、マニフェスト形式、古い出力）を追記

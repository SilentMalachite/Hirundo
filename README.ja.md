# Hirundo 🦅

Swiftで構築された、モダンで高速、かつセキュアな静的サイトジェネレーター。

[![Swift Version](https://img.shields.io/badge/Swift-6.0%2B-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2012%2B-blue.svg)](https://github.com/SilentMalachite/Hirundo)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Build](https://img.shields.io/badge/Build-See_CI-blue.svg)](https://github.com/SilentMalachite/Hirundo/actions)
[![Security](https://img.shields.io/badge/Security-Policy_Available-lightgrey.svg)](SECURITY.md)
[![Release](https://img.shields.io/github/v/release/SilentMalachite/Hirundo)](https://github.com/SilentMalachite/Hirundo/releases)
[![Tests](https://img.shields.io/badge/Tests-Passing-green.svg)](#テスト)

## 主な機能

- **🚀 高速**: Swiftによる実装。パース済みコンテンツ、レンダリング済みページ、テンプレートをキャッシュします
- **📝 Markdown**: Apple製swift-markdownによる、YAMLフロントマター付きCommonMarkサポート
- **🎨 テンプレート**: 20種類のカスタムフィルターを備えたStencilベースのテンプレートエンジン
- **🔄 ライブリロード**: 変更を検知して再ビルドし、WebSocket経由でリロードを通知する開発サーバー
- **🧩 組み込み機能**: サイトマップ、RSS、検索インデックス、アセット最小化を単純なオン/オフフラグで提供
- **📦 型安全**: 強く型付けされ、検証される設定とモデル
- **⚡ シンプル**: 設定項目はトップレベル6キーのみ。管理すべきプラグインランタイムはありません

## 目次

- [主な機能](#主な機能)
- [クイックスタート](#クイックスタート)
- [コマンド](#コマンド)
- [プロジェクト構造](#プロジェクト構造)
- [設定](#設定)
- [フロントマター](#フロントマター)
- [テンプレート](#テンプレート)
- [組み込み機能](#組み込み機能)
- [未実装の項目](#未実装の項目)
- [セキュリティ](#セキュリティ)
- [開発](#開発)
- [テスト](#テスト)
- [ライセンス](#ライセンス)

## クイックスタート

### インストール

```bash
git clone https://github.com/SilentMalachite/Hirundo.git
cd Hirundo
swift build -c release
cp .build/release/hirundo /usr/local/bin/
```

### 最初のサイトを作成

```bash
# 新しいサイトを作成
hirundo init my-site --blog

# サイトディレクトリに移動
cd my-site

# ビルド
hirundo build

# 開発サーバーを起動
hirundo serve
```

サイトは `http://localhost:8080` でライブリロード機能と共に利用できます。

> `hirundo serve` は出力ディレクトリにあるファイルをそのまま配信します。最初に `serve`
> する前に必ず一度 `hirundo build` を実行してください。配信対象が存在しないと、すべての
> リクエストが404になります。

## コマンド

すべてのコマンドは `--verbose` を受け付けます。指定すると、要約されたメッセージではなく
元のエラー内容が表示されます。

### `hirundo init`
新しいHirundoサイトを作成します。

```bash
hirundo init [パス] [オプション]

引数:
  パス                 サイトを作成する場所（デフォルト: "."）

オプション:
  --title <タイトル>   サイトタイトル（デフォルト: "My Hirundo Site"）
  --blog               ブログ機能を含める
  --force              空でないディレクトリへの作成を許可する
  --verbose            詳細なエラー情報を表示
```

押さえておきたい挙動:

- **空文字列のパスはエラーになります**。ディレクトリパス、またはカレントディレクトリを
  表す `.` を指定してください。
- 既存の `.gitignore` は**上書きされず、マージされます**（`--force` 指定時も同様）。
  マージされたファイルは `📝 Updated <パス>`、新規作成されたファイルは
  `✅ Created <パス>` として報告されます。
- `.git`、`.gitignore`、`.DS_Store`、`.svn`、`.hg` しか存在しないディレクトリは空とみなされる
  ため、クローンしたばかりのリポジトリには `--force` なしで初期化できます。
- 途中で失敗した場合、その実行で作成したディレクトリは**ロールバック**され、中途半端な
  状態が残りません。
- `--blog` を指定した場合、サンプル記事の日付は生成時刻になります。

`hirundo init --blog` が書き出すファイル:

```
.gitignore
config.yaml
content/index.md
content/about.md
content/posts/hello-world.md   # --blog 指定時のみ
static/css/style.css
templates/base.html
templates/default.html
templates/post.html            # --blog 指定時のみ
```

`--blog` を付けない場合、`features.rss` と `blog.generateArchive` / `generateCategories` /
`generateTags` はいずれも `false` として書き出されます。

### `hirundo build`
静的サイトをビルドします。

```bash
hirundo build [オプション]

オプション:
  --config <ファイル>       設定ファイルのパス（デフォルト: config.yaml）
  --environment <環境>      ビルド環境 development/production（デフォルト: production）
  --drafts                  下書き記事を含める
  --clean                   ビルド前に出力をクリーン
  --continue-on-error       一部のファイルで失敗してもビルドを継続（エラーリカバリモード）
  --verbose                 詳細なエラー情報を表示
```

設定ファイルが存在しない場合はエラーにならず、プロジェクトのデフォルト設定にフォール
バックします。`--environment` は現在のところ記録・表示されるだけで出力内容を変えません。
将来の条件分岐のために予約されています。

### `hirundo serve`
ライブリロード付きの開発サーバーを起動します。

```bash
hirundo serve [オプション]

オプション:
  --port <ポート>       サーバーポート（デフォルト: 8080）
  --host <ホスト>       サーバーホスト（デフォルト: localhost）
  --no-reload           ライブリロードを無効化
  --no-browser          ブラウザを自動で開かない
  --verbose             詳細なエラー情報を表示
```

サーバーはカレントディレクトリの `config.yaml` を読んで出力ディレクトリを特定し、
その中のファイルを配信します。

- ディレクトリへのリクエストは、そのディレクトリの `index.html` に解決されます。
  `/`、`/about`、`/about/` はいずれも動作します。
- 出力ディレクトリの外へ出るリクエスト（`/../../etc/passwd` など）は拒否されます。
- ライブリロードが有効な場合、`/livereload` にWebSocketエンドポイントが公開されます。

`--port` と `--host` はコマンドラインからのみ指定できます。`config.yaml` の `server.port`
は `serve` からは参照されません。

### `hirundo new`
新しいコンテンツを作成します。

```bash
hirundo new post <タイトル> [--slug <スラグ>] [--categories <一覧>] [--tags <一覧>]
                            [--template <テンプレート>] [--draft] [--open] [--verbose]
hirundo new page <タイトル> [--path <パス>] [--template <テンプレート>] [--open] [--verbose]
```

**`hirundo new post`**

| オプション | 意味 |
|---|---|
| `--slug` | `.md` を除いたファイル名。指定した文字列をそのまま使います。省略時はタイトルから生成します。 |
| `--categories` | カンマ区切り。空要素と重複は除去されます。 |
| `--tags` | カンマ区切り。空要素と重複は除去されます。 |
| `--template` | `template:` キーの値。既定は `post.html`。 |
| `--draft` | `draft: true` を書き出します。`--drafts` 付きでビルドしない限り除外されます。 |
| `--open` | 作成したファイルを `$VISUAL`、無ければ `$EDITOR` で開きます。 |

`<contentDirectory>/posts/<スラグ>.md` を作成します:

```markdown
---
title: "My First Post"
date: 2026-09-05T12:00:00Z
categories: ["swift"]
tags: ["static-site"]
template: "post.html"
---

# My First Post

```

`categories` / `tags` / `draft` は指定したときだけ出力されます。

**`hirundo new page`**

| オプション | 意味 |
|---|---|
| `--path` | content ディレクトリからの相対パス。`--path about/team` は `content/about/team.md` を作成し、中間ディレクトリも作ります。省略時はタイトルから生成します。 |
| `--template` | `template:` キーの値。既定は `default.html`。 |
| `--open` | 作成したファイルを `$VISUAL`、無ければ `$EDITOR` で開きます。 |

`<contentDirectory>/<パス>.md` を作成します。`date:` キーは出力しません
（`hirundo init` が生成する初期ページと同じ形です）。

**補足**

- content ディレクトリは `config.yaml` の `build.contentDirectory` から決まります。
  設定ファイルが無い場合も、`config.yaml` があるのに読み込めない場合も `content` を使い、
  どちらが起きたのかを標準エラー出力に警告として表示します。ファイルは作成され、終了
  コードは 0 のままです。設定ファイルが無いのは、たいていサイトのルート以外で実行した
  ということです。ファイルは書き出されますが、`config.yaml` ができるまでビルドされません。
- **どちらのコマンドも既存ファイルを上書きしません。** 衝突した場合はエラーになります。
  別の `--slug` / `--path` を指定するか、既にあるファイルを編集してください。
- `--slug` が決めるのは**ファイル名だけ**です。フロントマターに `slug:` キーは
  書き出しません。出力 URL はファイル名由来、RSS のリンクは記事のスラグ由来なので、
  ファイル名と異なる `slug:` を書くと両者が別の URL を指してしまいます。
  指定した `--slug` はスラグ化されず**そのまま**ファイル名になり、したがって URL の
  セグメントにも、空白や非 ASCII も含めて入力どおりに使われます。拒否されるのは
  `/`、`\`、`.`、`..`、制御文字、長すぎる値だけです。
- `--open` は許可リスト（`vim`、`nvim`、`nano`、`emacs`、`code`、`subl`、`vi`、`open` など）
  にあるエディタのみを、シェルを経由せずに起動します。コマンド名は単体で実行するため、
  引数付きの値（`code --wait`、`vim +startinsert` など）は不許可です。決められた一覧に
  無い絶対パスも不許可になります。`$EDITOR` が
  未設定・不許可・起動失敗のいずれでも、警告を表示するだけで終了コードは 0 のままです
  （ファイルは既に作成済みのため）。警告は「未設定」と「設定されているが不許可」を
  区別し、不許可の場合はその値を表示します。

### `hirundo clean`
出力ディレクトリとキャッシュをクリーンします。

```bash
hirundo clean [オプション]

オプション:
  --cache    .hirundo-cache ディレクトリもクリーンする
  --force    実際に削除する（指定しない場合は削除対象を表示するだけ）
  --verbose  詳細なエラー情報を表示
```

> `clean` は**デフォルトではドライラン**です。対話的な確認プロンプトはありません。
> `--force` を付けない限り、削除対象のパスを一覧表示するだけです。出力ディレクトリは
> `config.yaml` の `build.outputDirectory` から読み取られ、無ければ `_site` になります。

## プロジェクト構造

```
my-site/
├── config.yaml           # サイト設定
├── content/              # Markdownコンテンツ
│   ├── index.md          # ホームページ
│   ├── about.md          # Aboutページ
│   └── posts/            # ブログ記事
├── templates/            # Stencilテンプレート
│   ├── base.html         # ベースレイアウト
│   ├── default.html      # デフォルトページテンプレート
│   └── post.html         # ブログ記事テンプレート
├── static/               # 静的アセット（出力のルート直下にコピーされます）
│   └── css/
└── _site/                # 生成された出力（gitignore対象）
```

`static/` 配下のファイルは出力ディレクトリの**ルート**にコピーされます。
`static/css/style.css` は `/static/css/style.css` ではなく `/css/style.css` として配信されます。
`hirundo init` が作成するのは `static/css/` のみです。`js/` や `images/` などは必要に応じて
追加してください。

## 設定

`config.yaml` のトップレベルキーは `site`、`build`、`server`、`blog`、`features`、`limits`
のちょうど6つです。必須は `site` のみで、他のブロックは省略するとデフォルト値になります。

> ⚠️ **未知のトップレベルキーは黙って無視されます。** ブロック名のタイプミス（`serverr:`）や、
> 存在しないブロック（`timeouts:`、`plugins:`）はエラーにならず、単に無視されます。設定が
> 効いていないように見えるときは、上記の一覧と綴りを照合してください。

```yaml
site:
  title: "マイサイト"                 # 必須
  url: "https://example.com"         # 必須
  description: "Hirundoで構築されたサイト"   # オプション（最大500文字）
  language: "ja-JP"                  # オプション（デフォルト: "en-US"）
  author:                            # オプション
    name: "あなたの名前"
    email: "your.email@example.com"

build:
  contentDirectory: "content"
  outputDirectory: "_site"
  staticDirectory: "static"
  templatesDirectory: "templates"

server:
  port: 8080
  liveReload: true

blog:
  postsPerPage: 10                   # 1〜100
  generateArchive: true
  generateCategories: true
  generateTags: true

# 組み込み機能のフラグ。リストではなくマッピング形式です。
# ブロックごと省略した場合は4つとも false になります。
features:
  sitemap: true
  rss: true
  searchIndex: true
  minify: true

# セキュリティとパフォーマンスの制限。このブロックを書く場合は10キーすべてが必要です。
# 以下の値はいずれも省略時のデフォルトです。
limits:
  maxMarkdownFileSize: 10485760      # 10MB
  maxConfigFileSize: 1048576         # 1MB
  maxFrontMatterSize: 100000         # 100KB
  maxFilenameLength: 255
  maxTitleLength: 200
  maxDescriptionLength: 500
  maxUrlLength: 2000
  maxAuthorNameLength: 100
  maxEmailLength: 254
  maxLanguageCodeLength: 10
```

最小限の設定は、必須の2項目だけです。

```yaml
site:
  title: "マイサイト"
  url: "https://example.com"
```

### 注意点

- **`limits` はオール・オア・ナッシングです。** 他のブロックと異なり、キー単位のデフォルト値が
  ありません。`limits:` ブロックを書く場合は**10キーすべて**を列挙する必要があります。1つでも
  欠けると `Failed to parse configuration: The data couldn't be read because it is missing.`
  でビルドが失敗します。デフォルト値のままでよい場合は、ブロックごと省略してください。
- **`features` はリストではなくマッピングです。** 旧来のプラグイン形式はもはや受け付けられず、
  パースエラーになります。
  ```yaml
  # ✗ 現在はパースできません
  features:
    - name: "sitemap"
      enabled: true
  ```
- **`blog.rssEnabled` は存在しません。** RSSは `features.rss` で制御します。
- **`server` が受け付けるのは `port` と `liveReload` のみです。** [未実装の項目](#未実装の項目)を参照してください。

### ブロックを省略した場合のデフォルト

| ブロック | 省略時の挙動 |
|---------|-------------|
| `build` | `content` / `_site` / `static` / `templates` |
| `server` | `port: 8080`、`liveReload: true` |
| `blog` | `postsPerPage: 10`、`generate*` はすべて `true` |
| `features` | 4つともfalse |
| `limits` | 上記の例に記載した値 |

`hirundo init` は `features` までを書き出し、`limits` は出力しません。したがって `limits` は
デフォルト値で動作します。

## フロントマター

HirundoはMarkdownファイルのYAMLフロントマターを読み取ります。

```markdown
---
title: "記事タイトル"
date: 2024-01-15T10:00:00Z
description: "短い概要"
categories: ["開発", "swift"]
tags: ["静的サイト", "ウェブ"]
draft: false
slug: "my-post-title"
template: "post.html"
---

# 記事タイトル

ここにコンテンツを書きます...
```

認識されるキー: `title`、`date`、`description`、`categories`、`tags`、`draft`、`slug`、
`template`、`type`、`author`。

- `draft: true` のファイルは、`--drafts` を付けてビルドしない限り除外されます。
- `template:` はStencilテンプレートを指定します。存在しないテンプレート名を指定すると
  ビルドが失敗します。
- **`layout:` は読み取られません。** テンプレートを変更したい場合は `template:` を使うか、
  デフォルト（記事は `post.html`、ページは `default.html`）に任せてください。
  `hirundo init` が生成する初期コンテンツは `template:` を明示的に書き出します。

## テンプレート

Hirundoは[Stencil](https://github.com/stencilproject/Stencil)テンプレートエンジンを使用します。
テンプレートは以下の変数にアクセスできます。

- `site`: サイト設定とメタデータ
- `page`: 現在のページデータ
- `pages`: 全ページ
- `posts`: 全ブログ記事
- `categories`: カテゴリーマッピング
- `tags`: タグマッピング
- `content`: レンダリングされたページコンテンツ

### カスタムフィルター

| フィルター | 用途 |
|-----------|------|
| `date` | 日付フォーマット |
| `slugify` | URLスラグ作成 |
| `excerpt` | 抜粋抽出 |
| `markdown` | Markdownレンダリング |
| `absolute_url` | 絶対URL作成 |
| `relative_url` | ルート相対URL作成 |
| `site_url` | 設定値のサイトURL |
| `site_title` | 設定値のサイトタイトル |
| `site_description` | 設定値のサイト説明 |
| `join` | リストを連結して文字列にする |
| `length` | リストまたは文字列の長さ |
| `first` | 先頭の要素 |
| `last` | 末尾の要素 |
| `slice` | リストの部分範囲 |
| `truncate` | 文字列の切り詰め |
| `strip` | 前後の空白を除去 |
| `replace` | 部分文字列の置換 |
| `split` | 文字列をリストに分割 |
| `number` | 数値の書式化 |
| `default` | 空値のときの代替値 |

### テンプレート例

```html
{% extends "base.html" %}

{% block content %}
<article>
    <h1>{{ page.title }}</h1>
    {% if page.date %}
    <time>{{ page.date | date: "%Y年%m月%d日" }}</time>
    {% endif %}
    {{ content }}
</article>
{% endblock %}
```

## 組み込み機能

Hirundoには4つの組み込み機能があり、`features` ブロックで切り替えます。セキュリティと
単純さのため、外部コードの動的読み込みはサポートしていません。

| フラグ | 効果 |
|-------|------|
| `sitemap` | 出力のルートに `sitemap.xml` を書き出します |
| `rss` | 記事から `rss.xml` を書き出します |
| `searchIndex` | クライアントサイド検索用に `search-index.json` を書き出します |
| `minify` | アセットパイプラインでCSSとJSの最小化を有効にします |

`minify` が対象とするのは**CSSとJSのアセットのみ**です。生成されるHTMLは最小化されません。

アーカイブ、カテゴリー、タグの各ページは、これとは別に `blog` ブロックで制御します。

## 未実装の項目

以前のバージョンの本ドキュメントで「動作する」と記載されていたため、ここに明記します。
以下はいずれも実装されていません。

- **CORS設定**。`server.cors` ブロックは存在しません。`server` が受け付けるのは `port` と
  `liveReload` のみで、その下に `cors:` を書いても黙って無視されます。
- **タイムアウト設定**。`timeouts` ブロックは存在せず、ファイル操作、ディレクトリ操作、
  HTTPリクエスト、ファイル監視、サーバー起動のいずれについても設定可能なタイムアウトは
  ありません。
- **プラグインアーキテクチャ**。プラグインシステムは削除され、`features` の4つのフラグが
  その役割を担っています。カスタムプラグイン開発のサポートはなく、`imageOptimization` や
  `syntaxHighlight` という機能も存在しません。
- **ライブリロードのWebSocket認証**。`/auth-token` エンドポイントもトークンによるハンド
  シェイクも存在せず、`/livereload` は接続をそのまま受け付けます。開発サーバーを信頼できない
  ネットワークに公開しないでください。
- **アセットのフィンガープリント、ソースマップ、JS/CSSの結合**。
  `build.enableAssetFingerprinting`、`enableSourceMaps`、`concatenateJS`、`concatenateCSS` は
  設定パーサーに受け付けられますが、どこでも使用されていません。
- **フロントマターの `layout:`**。`template:` を使用してください。

## セキュリティ

Hirundoは静的サイトジェネレーターとして適切なセキュリティ対策を実装しています。

- **入力検証**: Markdownファイル、設定ファイル、フロントマターの設定可能なサイズ制限。
  タイトル、説明、URL、著者名、メールアドレス、言語コードの長さ制限。
- **パス検証**: `build` の各ディレクトリは絶対パスや `..` を含むことができません。開発サーバーは
  出力ディレクトリの外へ出るリクエストパスを拒否します。
- **アセット処理**: 最小化を任意で有効にできるCSS/JS処理。
- **開発サーバー**: 終了時にWebSocketセッションとファイル監視を後始末します。

セキュリティポリシーについては[SECURITY.md](SECURITY.md)をご覧ください。

### 付属フィクスチャでのローカル確認

付属のフィクスチャでエンドツーエンドの確認ができます。

```bash
cd test-hirundo
swift run --package-path .. hirundo build --clean
swift run --package-path .. hirundo serve
# ブラウザで http://localhost:8080 を開き、test-hirundo/content/ 配下を編集
```

## 開発

### 要件

- Swift 6.0+
- macOS 12+
- Xcode 16+（macOS開発の場合）

### ソースからビルド

```bash
git clone https://github.com/SilentMalachite/Hirundo.git
cd Hirundo
swift build
```

### デバッグモード

詳細な出力のためのログレベル設定:

```bash
HIRUNDO_LOG_LEVEL=debug hirundo build
```

## テスト

```bash
# 全テストを実行
swift test

# 特定のテストスイートを実行
swift test --filter SiteGeneratorTests
swift test --filter ConfigTests
swift test --filter IntegrationTests

# テストカバレッジの生成
swift test --enable-code-coverage
```

### テストスイート

- `AssetPipelineTests` — アセット処理と最小化
- `ConfigTests`、`ConfigParseTests` — 設定の検証とパース
- `MarkdownParserTests`、`SimpleMarkdownTest` — Markdownとフロントマターの処理
- `TemplateEngineTests` — テンプレートのレンダリングとフィルター
- `SiteGeneratorTests` — サイト生成のエンドツーエンド
- `SiteScaffolderTests`、`InitDestinationResolverTests`、`ScaffoldErrorMappingTests` — `hirundo init`
- `DevelopmentServerTests` — リクエストのルーティングとパスの封じ込め
- `HotReloadManagerTests`、`HotReloadIntegrationTest`、`FSEventsMemoryTests` — ファイル監視
- `ErrorRecoveryTests` — `--continue-on-error` の挙動
- `SecurityTests` — 検証とパストラバーサルのチェック
- `IntegrationTests` — エンドツーエンドのワークフロー
- `DependencyCompatibilityTests`、`EditorCommandValidationTests`

## ドキュメント

- 開発ガイド: [`DEVELOPMENT.md`](DEVELOPMENT.md)
- テストガイド: [`TESTING.md`](TESTING.md)
- アーキテクチャ: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- セキュリティポリシー: [`SECURITY.md`](SECURITY.md)
- コントリビューション: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- English documentation: [`README.md`](README.md)

## 技術アーキテクチャ

### 依存関係

- **[swift-markdown](https://github.com/apple/swift-markdown)**: AppleのCommonMarkパーサー
- **[Stencil](https://github.com/stencilproject/Stencil)**: テンプレートエンジン
- **[Yams](https://github.com/jpsim/Yams)**: YAMLパーサー
- **[Swifter](https://github.com/httpswift/swifter)**: 軽量HTTPサーバー
- **[PathKit](https://github.com/kylef/PathKit)**: パスユーティリティ
- **[swift-argument-parser](https://github.com/apple/swift-argument-parser)**: コマンドラインインターフェース

### パフォーマンス

- **キャッシング**: パース済みコンテンツ、レンダリング済みページ、テンプレート
- **Async/Await**: ビルド時間短縮のための並列処理
- **ホットリロード**: FSEventsによるファイルシステム監視と、終了時のクリーンアップ

## コントリビューション

コントリビューションを歓迎します！ガイドラインについては[CONTRIBUTING.md](CONTRIBUTING.md)をご覧ください。

### 開発セットアップ

1. リポジトリをフォーク
2. フィーチャーブランチを作成
3. 変更を行う
4. 新機能のテストを追加
5. テストスイートを実行
6. プルリクエストを提出

## ライセンス

HirundoはMITライセンスの下でリリースされています。詳細は[LICENSE](LICENSE)をご覧ください。

## 謝辞

- [Swift](https://swift.org)で構築
- モダンな静的サイトジェネレーターからインスパイア
- 信頼性の高いMarkdownパースのためにAppleの[swift-markdown](https://github.com/apple/swift-markdown)を使用

---

❤️ とSwiftで作られました

# Hirundo プロジェクト

Swiftで構築された、モダンで高速、かつセキュアな静的サイトジェネレーターです。

## 主な機能

- **🚀 高速**: マルチレベルキャッシング付きSwiftによる最適なパフォーマンス
- **🔒 セキュア**: 包括的な入力検証、パストラバーサル保護、安全なアセット処理
- **📝 Markdown**: Apple swift-markdownを使用したフロントマター付きCommonMarkサポート
- **🎨 テンプレート**: カスタムフィルター付きの強力なStencilベースのテンプレートエンジン
- **🔄 ライブリロード**: リアルタイムエラー報告機能付き自動再構築開発サーバー
- **🧩 機能フラグ**: sitemap / rss / searchIndex / minify を `features` で切り替え
- **💾 スマートキャッシング**: 超高速再構築のためのインテリジェント無効化キャッシング
- **📦 型安全**: 包括的検証付きの強く型付けされた設定とモデル
- **⚡ 設定可能**: カスタマイズ可能なセキュリティ制限（`limits`）
- **🛡️ メモリ安全**: WebSocket接続とファイル監視の高度なメモリ管理

## 技術スタック

- **言語**: Swift 5.9+
- **HTTPサーバー**: Swifter（軽量HTTPサーバー）
- **Markdownパーサー**: swift-markdown（Apple製）
- **テンプレートエンジン**: Stencil
- **YAML**: Yams
- **対応OS**: macOS 12+

## プロジェクト構造

```
my-site/
├── config.yaml          # サイト設定
├── content/            # Markdownコンテンツ
│   ├── index.md       # ホームページ
│   ├── about.md       # Aboutページ
│   └── posts/         # ブログ記事
├── templates/          # HTMLテンプレート
│   ├── base.html      # ベースレイアウト
│   ├── default.html   # デフォルトページテンプレート
│   └── post.html      # ブログ記事テンプレート
├── static/            # 静的アセット
│   ├── css/          # スタイルシート
│   ├── js/           # JavaScript
│   └── images/       # 画像
└── _site/            # 生成された出力（gitignore対象）
```

## 主要コマンド

### 開発サーバーの起動
```bash
hirundo serve
```
- ポート: 8080（デフォルト）
- ライブリロード: 有効
- URL: `http://localhost:8080`

### 本番用ビルド
```bash
hirundo build
```
- 出力先: `_site`ディレクトリ
- 環境: production/development
- オプション: --drafts（下書きを含める）、--clean（クリーンビルド）

### 新規コンテンツの作成
```bash
# ブログ記事の作成
hirundo new post "記事タイトル"

# ページの作成
hirundo new page "ページタイトル"
```

### テストの実行
```bash
swift test
```

### リントとタイプチェック
```bash
# Swiftの場合、ビルド時に型チェックが実行される
swift build

# デバッグモードでのビルド
HIRUNDO_LOG_LEVEL=debug hirundo build
```

## アーキテクチャの特徴

### 1. パッケージ管理
- 単一のクリーンなPackage.swift
- 適切な依存関係管理

### 2. 型安全性
- 全体を通じた強い型付けモデル
- AnyCodableによる柔軟性を持つCodable実装
- 包括的なエラー型とヘルプメッセージ

### 3. パフォーマンス
- マルチレベルキャッシング（パース済みコンテンツ、レンダリング済みページ、テンプレート）
- async/awaitによる並列処理
- ストリーミングによる効率的なメモリ使用

### 4. セキュリティ
- パストラバーサル保護
- 入力検証とサニタイゼーション
- セキュアなファイルパーミッション

### 5. 機能フラグ（features）
`config.yaml` の `features` ブロックで有効・無効を切り替えます（すべてデフォルト `false`）：
- **sitemap**: sitemap.xml生成
- **rss**: ブログのRSSフィード生成
- **searchIndex**: 検索インデックス（JSON）の生成
- **minify**: HTML出力の最小化

## 設定ファイル（config.yaml）

`hirundo init` が生成する `config.yaml` が正となる形式です。トップレベルで解釈されるキーは
`site` / `build` / `server` / `blog` / `features` / `limits` の6つのみで、`site` 以外はすべて
オプションです（省略時は下記のデフォルト値が使われます）。未知のキーは無視されるため、
綴り間違いはエラーにならず黙って無視される点に注意してください。

```yaml
site:
  title: "サイトタイトル"
  description: "サイトの説明"        # オプション（最大500文字）
  url: "https://example.com"
  language: "ja-JP"                 # オプション（デフォルト: "en-US"）
  author:                           # オプション
    name: "著者名"
    email: "email@example.com"

build:
  contentDirectory: "content"
  outputDirectory: "_site"
  staticDirectory: "static"
  templatesDirectory: "templates"

server:
  port: 8080
  liveReload: true

blog:
  postsPerPage: 10                  # 1〜100
  generateArchive: true
  generateCategories: true
  generateTags: true

# 機能フラグ（オプション。マッピング形式で、ブロックごと省略した場合はすべて false）
features:
  sitemap: true
  rss: true
  searchIndex: false
  minify: false

# セキュリティとパフォーマンス制限（オプション。以下の値はいずれも省略時のデフォルト）
limits:
  maxMarkdownFileSize: 10485760     # 10MB
  maxConfigFileSize: 1048576        # 1MB
  maxFrontMatterSize: 100000        # 100KB
  maxFilenameLength: 255
  maxTitleLength: 200
  maxDescriptionLength: 500
  maxUrlLength: 2000
  maxAuthorNameLength: 100
  maxEmailLength: 254
  maxLanguageCodeLength: 10
```

`hirundo init` は `features` までを書き出し、`limits` は出力しません（デフォルト値で動作します）。
`--blog` を付けずに初期化した場合は、`features.rss` と `blog.generateArchive` /
`generateCategories` / `generateTags` がまとめて `false` になります。

各ブロックのデフォルト値：

| ブロック | 省略時の挙動 |
|---------|-------------|
| `build` | `content` / `_site` / `static` / `templates`（4つのディレクトリはすべて別名である必要あり） |
| `server` | `port: 8080`、`liveReload: true` |
| `blog` | `postsPerPage: 10`、`generate*` はすべて `true` |
| `features` | すべて `false` |
| `limits` | 上記YAML例に記載した値 |

## テンプレート変数

利用可能な変数：
- `site`: サイト設定とメタデータ
- `page`: 現在のページデータ
- `pages`: 全ページ
- `posts`: 全ブログ記事
- `categories`: カテゴリーマップ
- `tags`: タグマップ
- `content`: レンダリングされたページコンテンツ

カスタムフィルター：
- `date`: 日付フォーマット
- `slugify`: URLスラグ作成
- `excerpt`: 抜粋抽出
- `absolute_url`: 絶対URL作成
- `markdown`: Markdownレンダリング

## 今後の拡張予定

- 国際化（i18n）サポート
- CSS/JS処理のためのアセットパイプライン
- 高度なキャッシング戦略
- カスタムプラグイン開発サポート
- I/O操作のタイムアウト設定（`timeouts` ブロック）
  - 現在 `config.yaml` の `timeouts` は解釈されません（`ConfigValidation.validateTimeout`
    のみが存在する未配線の状態です）。記述しても無視されます。
- 開発サーバーのCORS設定（`server.cors` ブロック）
  - 現在 `server` が解釈するのは `port` と `liveReload` のみです。
- 複数テーマサポート

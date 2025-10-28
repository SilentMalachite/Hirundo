# Hirundo プロジェクト

Swiftで構築された、モダンで高速、かつセキュアな静的サイトジェネレーターです。

## 主な機能

- **🚀 高速**: マルチレベルキャッシング付きSwiftによる最適なパフォーマンス
- **🔒 セキュア**: 包括的な入力検証、パストラバーサル保護、安全なアセット処理
- **📝 Markdown**: Apple swift-markdownを使用したフロントマター付きCommonMarkサポート
- **🎨 テンプレート**: カスタムフィルター付きの強力なStencilベースのテンプレートエンジン
- **🔄 ライブリロード**: リアルタイムエラー報告機能付き自動再構築開発サーバー
- **🌐 CORS対応**: 開発サーバーでの設定可能なCORS（Cross-Origin Resource Sharing）サポート
- **🧩 拡張可能**: セキュア検証付きカスタム機能プラグインアーキテクチャ
- **💾 スマートキャッシング**: 超高速再構築のためのインテリジェント無効化キャッシング
- **📦 型安全**: 包括的検証付きの強く型付けされた設定とモデル
- **⚡ 設定可能**: カスタマイズ可能なセキュリティ制限とパフォーマンス設定
- **🛡️ メモリ安全**: WebSocket接続とファイル監視の高度なメモリ管理
- **⏱️ タイムアウト保護**: すべてのI/O操作に対する設定可能なタイムアウトによるDoS攻撃防護

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

### 5. プラグインシステム
組み込みプラグイン：
- **sitemap**: sitemap.xml生成
- **rss**: ブログのRSSフィード生成
- **minify**: HTML出力の最小化
- **imageOptimization**: 画像最適化とレスポンシブ画像作成
- **syntaxHighlight**: 拡張コードシンタックスハイライト

## 設定ファイル（config.yaml）

```yaml
site:
  title: "サイトタイトル"
  description: "サイトの説明"
  url: "https://example.com"
  language: "ja-JP"
  author:
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
  cors:
    enabled: true
    allowedOrigins: ["http://localhost:*", "https://localhost:*"]
    allowedMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allowedHeaders: ["Content-Type", "Authorization"]
    exposedHeaders: ["X-Response-Time"]  # オプション
    maxAge: 3600
    allowCredentials: false

blog:
  postsPerPage: 10
  generateArchive: true
  generateCategories: true
  generateTags: true

# セキュリティとパフォーマンス制限（オプション）
limits:
  maxMarkdownFileSize: 10485760     # 10MB
  maxConfigFileSize: 1048576        # 1MB
  maxFrontMatterSize: 100000        # 100KB
  maxFilenameLength: 255
  maxTitleLength: 200
  maxDescriptionLength: 500

# プラグイン設定（オプション）
features:
  - name: "sitemap"
    enabled: true
  - name: "rss"
    enabled: true
  - name: "minify"
    enabled: true
    settings:
      minifyHTML: true
      minifyCSS: true
      minifyJS: false  # 安全のため無効

# タイムアウト設定（オプション）
timeouts:
  fileReadTimeout: 30.0              # ファイル読み込みタイムアウト（秒）
  fileWriteTimeout: 30.0             # ファイル書き込みタイムアウト（秒）
  directoryOperationTimeout: 15.0    # ディレクトリ操作タイムアウト（秒）
  httpRequestTimeout: 10.0           # HTTPリクエストタイムアウト（秒）
  fsEventsTimeout: 5.0              # ファイル監視開始タイムアウト（秒）
  serverStartTimeout: 30.0          # サーバー起動タイムアウト（秒）
```

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

## タイムアウト設定

Hirundoは、DoS攻撃や意図しないリソース消費を防ぐため、すべてのI/O操作に対してタイムアウト設定を提供します。

### 設定可能なタイムアウト

- **fileReadTimeout**: ファイル読み込み操作（Markdownファイル、設定ファイルなど）
- **fileWriteTimeout**: ファイル書き込み操作（HTML出力、キャッシュファイルなど）
- **directoryOperationTimeout**: ディレクトリ操作（ディレクトリ作成、一覧取得など）
- **httpRequestTimeout**: HTTPリクエスト（開発サーバーでの外部API呼び出しなど）
- **fsEventsTimeout**: ファイル監視システムの初期化
- **serverStartTimeout**: 開発サーバーの起動

### デフォルト値

- ファイル操作: 30秒
- ディレクトリ操作: 15秒
- HTTPリクエスト: 10秒
- ファイル監視: 5秒
- サーバー起動: 30秒

### 制限

- 最小値: 0.1秒
- 最大値: 600秒（10分）

これらの制限により、システムが適切に応答し続けることが保証され、悪意あるファイルや環境の問題による無限ハング状態を防ぎます。

## 今後の拡張予定

- 国際化（i18n）サポート
- CSS/JS処理のためのアセットパイプライン
- 高度なキャッシング戦略
- カスタムプラグイン開発サポート
- 複数テーマサポート

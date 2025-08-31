# Hirundo 🦅

Swiftで構築された、モダンで高速、かつセキュアな静的サイトジェネレーター。

[![Swift Version](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2012%2B-blue.svg)](https://github.com/SilentMalachite/Hirundo)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Build](https://img.shields.io/badge/Build-See_CI-blue.svg)](https://github.com/SilentMalachite/Hirundo/actions)
[![Security](https://img.shields.io/badge/Security-Policy_Available-lightgrey.svg)](SECURITY.md)
[![Release](https://img.shields.io/github/v/release/SilentMalachite/Hirundo)](https://github.com/SilentMalachite/Hirundo/releases)
[![Tests](https://img.shields.io/badge/Tests-Passing-green.svg)](#テスト)

## 主な機能

- **🚀 高速**: マルチレベルキャッシング付きSwiftによる最適なパフォーマンス
- **📝 Markdown**: Apple swift-markdownを使用したフロントマター付きCommonMarkサポート
- **🎨 テンプレート**: カスタムフィルター付きの強力なStencilベースのテンプレートエンジン
- **🔄 ライブリロード**: 自動再構築とリアルタイムエラー報告機能付き開発サーバー
- **🧩 拡張可能**: 組み込みプラグイン付きカスタム機能プラグインアーキテクチャ
- **💾 スマートキャッシング**: 超高速再構築のためのマルチレベルインテリジェントキャッシング
- **📦 型安全**: 包括的検証付きの強く型付けされた設定とモデル
- **⚡ シンプル**: 不要な複雑さのない、クリーンで使いやすい設定
- **🛡️ メモリ安全**: WebSocket接続とファイル監視の高度なメモリ管理

## 目次

- [主な機能](#主な機能)
- [クイックスタート](#クイックスタート)
- [設定](#設定)
- [フロントマター](#フロントマター)
- [テンプレート](#テンプレート)
- [開発](#開発)
- [テスト](#テスト)
- [ライセンス](#ライセンス)

## クイックスタート

### インストール

#### Swift Package Managerを使用

```bash
git clone https://github.com/SilentMalachite/Hirundo.git
cd hirundo
swift build -c release
cp .build/release/hirundo /usr/local/bin/
```

#### ソースからビルド

```bash
swift build -c release
```

### 最初のサイトを作成

```bash
# 新しいサイトを作成
hirundo init my-site --blog

# サイトディレクトリに移動
cd my-site

# 開発サーバーを起動
hirundo serve
```

サイトは `http://localhost:8080` でライブリロード機能と共に利用できます。

## コマンド

### `hirundo init`
新しいHirundoサイトを作成します。

```bash
hirundo init [パス] [オプション]

オプション:
  --title <タイトル>   サイトタイトル（デフォルト: "My Hirundo Site"）
  --blog              ブログ機能を含める
  --force             空でないディレクトリでも強制作成
```

### `hirundo build`
静的サイトをビルドします。

```bash
hirundo build [オプション]

オプション:
  --config <ファイル>    設定ファイルのパス（デフォルト: config.yaml）
  --environment <環境>   ビルド環境（デフォルト: production）
  --drafts              下書き記事を含める
  --clean               ビルド前に出力をクリーン
```

### `hirundo serve`
ライブリロード付きの開発サーバーを起動します。

```bash
hirundo serve [オプション]

オプション:
  --port <ポート>       サーバーポート（デフォルト: 8080）
  --host <ホスト>       サーバーホスト（デフォルト: localhost）
  --no-reload          ライブリロードを無効化
  --no-browser         ブラウザを自動で開かない
```

### `hirundo new`
新しいコンテンツを作成します。

```bash
# 新しいブログ記事を作成
hirundo new post "記事タイトル" --tags "swift,web" --categories "開発"

# 新しいページを作成
hirundo new page "私たちについて" --layout "default"
```

### `hirundo clean`
出力ディレクトリとキャッシュをクリーンします。

```bash
hirundo clean [オプション]

オプション:
  --cache    アセットキャッシュもクリーン
  --force    確認をスキップ
```

## プロジェクト構造

```
my-site/
├── config.yaml          # サイト設定
├── content/              # Markdownコンテンツ
│   ├── index.md         # ホームページ
│   ├── about.md         # Aboutページ
│   └── posts/           # ブログ記事
├── templates/            # HTMLテンプレート
│   ├── base.html        # ベースレイアウト
│   ├── default.html     # デフォルトページテンプレート
│   └── post.html        # ブログ記事テンプレート
├── static/              # 静的アセット
│   ├── css/            # スタイルシート
│   ├── js/             # JavaScript
│   └── images/         # 画像
└── _site/              # 生成された出力（gitignore対象）
```

## 設定

### サイト設定 (`config.yaml`)

```yaml
site:
  title: "マイサイト"
  description: "Hirundoで構築されたサイト"
  url: "https://example.com"
  language: "ja-JP"
  author:
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
  postsPerPage: 10
  generateArchive: true
  generateCategories: true
  generateTags: true
  rssEnabled: true

# パフォーマンス制限（オプション）
limits:
  maxMarkdownFileSize: 10485760     # 10MB
  maxConfigFileSize: 1048576        # 1MB
  maxFrontMatterSize: 100000        # 100KB
  maxFilenameLength: 255
  maxTitleLength: 200
  maxDescriptionLength: 500

# プラグイン設定（オプション）
features:
  sitemap: true
  rss: true
  - name: "minify"
    enabled: true
    settings:
      minifyHTML: true
      minifyCSS: true
      minifyJS: false  # 安全のため無効
```

## フロントマター

HirundoはMarkdownファイルでYAMLフロントマターをサポートします：

```markdown
---
title: "記事タイトル"
date: 2024-01-15T10:00:00Z
layout: "post"
categories: ["開発", "swift"]
tags: ["静的サイト", "ウェブ"]
draft: false
---

# 記事タイトル

ここにコンテンツを書きます...
```

## テンプレート

Hirundoは[Stencil](https://github.com/stencilproject/Stencil)テンプレートエンジンを使用します。テンプレートは以下の変数にアクセスできます：

- `site`: サイト設定とメタデータ
- `page`: 現在のページデータ
- `pages`: 全ページ
- `posts`: 全ブログ記事
- `categories`: カテゴリーマッピング
- `tags`: タグマッピング
- `content`: レンダリングされたページコンテンツ

### カスタムフィルター

- `date`: 日付フォーマット
- `slugify`: URLスラグ作成
- `excerpt`: 抜粋抽出
- `absolute_url`: 絶対URL作成
- `markdown`: Markdownレンダリング

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

## プラグイン

Hirundoには複数の組み込みプラグインが含まれています：

### Sitemapプラグイン
検索エンジン用の`sitemap.xml`を生成します。

### RSSプラグイン
ブログ記事のRSSフィードを作成します。

### Minifyプラグイン
より良いパフォーマンスのためにHTML出力を最小化します。

### Search Indexプラグイン
クライアントサイド検索機能のための検索インデックスを生成します。

## セキュリティ機能

Hirundoは包括的な保護対策でセキュリティを優先しています：

### 入力検証
- **ファイルサイズ制限**: Markdownファイル、設定ファイル、フロントマターの設定可能な制限
- **パス検証**: シンボリックリンク解決を含む高度なパストラバーサル保護
- **コンテンツサニタイゼーション**: ユーザー生成コンテンツの安全な処理

### アセット処理セキュリティ
- **安全なCSS/JS処理**: コードインジェクションを防ぐための最小化前検証
- **JS変換の無効化**: 潜在的に危険な正規表現ベースの変換はデフォルトで無効
- **パスサニタイゼーション**: セキュリティチェック付きの包括的なパスクリーニング

### 開発サーバーセキュリティ
- **WebSocket保護**: メモリ安全なWebSocketセッション管理
- **エラー分離**: 情報漏洩のない安全なエラー報告
- **ファイル監視**: クリーンアップ付きの安全なファイルシステム監視

## 開発

### 要件

- Swift 5.9+
- macOS 12+ または Linux
- Xcode 16+（macOS開発の場合）

### ソースからビルド

```bash
git clone https://github.com/SilentMalachite/Hirundo.git
cd hirundo
swift build
```

### テストの実行

Hirundoは包括的なテストスイートを提供します：

```bash
# 全テストを実行
swift test

# 特定のテストを実行
swift test --filter SiteGeneratorTests
swift test --filter EdgeCaseTests
swift test --filter IntegrationTests

# テストカバレッジの生成
swift test --enable-code-coverage
```

#### テストカテゴリ

- **単体テスト**: 個別コンポーネントのテスト（85+ テスト）
- **統合テスト**: エンドツーエンドのワークフローテスト
- **セキュリティテスト**: 脆弱性とセキュリティ検証
- **エッジケーステスト**: 境界条件と異常ケース
- **パフォーマンステスト**: メモリとパフォーマンスの検証

### デバッグモード

詳細な出力のためのログレベル設定：

```bash
HIRUNDO_LOG_LEVEL=debug hirundo build
```

## ドキュメント

- 開発ガイド: `DEVELOPMENT.md`
- テストガイド: `TESTING.md`
- アーキテクチャ: `ARCHITECTURE.md`
- セキュリティ: `SECURITY.md` と `WEBSOCKET_AUTHENTICATION.md`
- コントリビューション: `CONTRIBUTING.md`

### ライブリロード認証の概要

開発サーバーのWebSocket接続はトークンで認証されます：

- トークン取得: `GET /auth-token` → `{ token, expiresIn, endpoint: "/livereload" }`
- 接続直後にサーバーから `auth_required` が送られます
- クライアントは `{"type":"auth", "token":"..."}` を送信
- 成功時 `auth_success`、以降リロードイベントを受信／失敗時は未登録のためイベントは受信しません

`hirundo serve` ではHTMLにクライアントスクリプトが自動挿入され、上記フローが自動で処理されます。

### 付属フィクスチャでのローカル確認

```bash
cd test-hirundo
swift run --package-path .. hirundo build --clean
swift run --package-path .. hirundo serve
# ブラウザで http://localhost:8080 を開き、test-hirundo/content/ 配下を編集
```

## 技術アーキテクチャ

### 依存関係

- **[swift-markdown](https://github.com/apple/swift-markdown)**: AppleのCommonMarkパーサー
- **[Stencil](https://github.com/stencilproject/Stencil)**: テンプレートエンジン
- **[Yams](https://github.com/jpsim/Yams)**: YAMLパーサー
- **[Swifter](https://github.com/httpswift/swifter)**: 軽量HTTPサーバー
- **[swift-argument-parser](https://github.com/apple/swift-argument-parser)**: コマンドラインインターフェース

### パフォーマンス機能

- **マルチレベルキャッシング**: インテリジェント無効化付きのパース済みコンテンツ、レンダリング済みページ、テンプレートキャッシング
- **Async/Await**: ビルド時間向上のための並列処理
- **ストリーミング**: 制御されたリソース使用による大きなサイトの効率的なメモリ使用
- **メモリ管理**: 高度なWebSocketセッションクリーンアップとファイルハンドル管理
- **設定可能な制限**: 調整可能なパフォーマンスとセキュリティ制限
- **ホットリロード**: macOSでのFSEventsとLinuxでのフォールバックによる高速ファイルシステム監視

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

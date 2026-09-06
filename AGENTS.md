# Repository Guidelines

## プロジェクト構成とモジュール
- `Package.swift`: SwiftPM マニフェスト（Swift 6、macOS 12+）。
- `Sources/Hirundo/`: CLI 実行ファイル（`hirundo`）。
- `Sources/HirundoCore/`: コアライブラリ（パーサ、テンプレート、アセット、開発サーバ、スキャフォルド）。
  - `Scaffold/`: `hirundo init` 用（`SiteScaffolder.swift`、`ScaffoldTemplates.swift`、`InitDestinationResolver.swift`）。
  - プラグイン機構は Stage 2 で削除済み。代わりに `Models/Features.swift` の組み込みフィーチャーを使う。
- `Tests/HirundoTests/`: XCTest 一式。ファイルは `*Tests.swift`、クラスは `XCTestCase` を継承。
- `test-site/`, `test-hirundo/`: 手動/統合検証用のサンプルサイトとフィクスチャ。

## ビルド・テスト・実行
- ビルド: `swift build`（最適化は `-c release`）。
- テスト: `swift test`（全テストを実行）。
- CLI ヘルプ: `swift run hirundo --help`。
- 開発サーバ: `swift run hirundo serve`（ライブリロード付きで起動）。
- サイト生成: `swift run hirundo build --clean`（出力をクリアしてビルド）。

## コーディング規約と命名
- Swift API Design Guidelines 準拠。インデントは4スペース、行長は目安120桁。
- 公開 API は `///` ドキュメントコメントを付与（引数/戻り値を記述）。
- 型は `UpperCamelCase`、関数/変数は `lowerCamelCase`。定数は可読かつ明示的に。
- エラーは型付き `Error` 列挙を優先。`throws` で伝播し成功/失敗の両方をテスト。
- ファイル配置は機能単位（例: `Models/`, `Parsers/`, `Renderers/`, `Scaffold/`, `Templates/`, `Utilities/`）。

## テスト指針
- フレームワークは XCTest を使用。新規テストは `Tests/HirundoTests/` に配置。
- 命名例: `testGeneratesSite_whenDraftsEnabled_outputsDrafts()` のように状況と期待を明示。
- カバレッジ: 変更で触れる公開 API と辺縁/エラー経路を必ず追加テスト。
- 必要に応じて `test-site/` を使い CLI を統合的に検証（ローカルでも可）。

## コミットとプルリク
- コミットは可能なら Conventional 形式: `feat: merge existing .gitignore on init`、`fix: prevent path traversal` 等。
- 変更は小さく、メッセージは命令形で Issue を参照（例: `Fixes #123`）。
- PR には説明、関連 Issue、テスト結果（`swift test`）、破壊的変更の明記を含める。
- 事前チェック: テスト成功、ドキュメント更新（README/ARCHITECTURE/CHANGELOG）、規約準拠。
- `swift test` には既知の失敗（`HotReloadManagerTests` の 6 件）がある。詳細は `TESTING.md` を参照し、それ以外の新規失敗を出さないこと。

## セキュリティと設定
- 秘密情報はコミットしない。サイト設定は `config.yaml` を利用し入力値を検証。
- `config.yaml` のトップレベルキーは `site` / `build` / `server` / `blog` / `features` / `limits` / `assets` の7つのみ。未知のキーは黙って無視される。`assets.fingerprintExclude` はフィンガープリント除外パターンの追加用（組み込みの `robots.txt` 等は常に除外される）。
- 設定の各種制限は `limits`（ファイルサイズ・文字数の10項目）で指定する。タイムアウト設定・CORS 設定・WebSocket 認証設定は存在しない。詳細は `SECURITY.md` を参照。
- `/livereload` のハンドシェイクは `WebSocketOriginGuard` が `Origin` と `Host` で検証する（一致しなければ 403）。設定項目もトークンも無く、認証ではない。

## アーキテクチャ注意点
- `hirundo` 実行ファイルは `HirundoCore` に委譲。機能追加はコアに実装し、CLI で公開する方針。

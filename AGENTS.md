# Repository Guidelines

## プロジェクト構成とモジュール
- `Package.swift`: SwiftPM マニフェスト（Swift 6、macOS 12+）。
- `Sources/Hirundo/`: CLI 実行ファイル（`hirundo`）。
- `Sources/HirundoCore/`: コアライブラリ（パーサ、テンプレート、サーバ、プラグイン）。
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
- ファイル配置は機能単位（例: `Models/`, `Plugins/`, `Utilities/`）。

## テスト指針
- フレームワークは XCTest を使用。新規テストは `Tests/HirundoTests/` に配置。
- 命名例: `testGeneratesSite_whenDraftsEnabled_outputsDrafts()` のように状況と期待を明示。
- カバレッジ: 変更で触れる公開 API と辺縁/エラー経路を必ず追加テスト。
- 必要に応じて `test-site/` を使い CLI を統合的に検証（ローカルでも可）。

## コミットとプルリク
- コミットは可能なら Conventional 形式: `feat: add RSS plugin option`、`fix: prevent path traversal` 等。
- 変更は小さく、メッセージは命令形で Issue を参照（例: `Fixes #123`）。
- PR には説明、関連 Issue、テスト結果（`swift test`）、破壊的変更の明記を含める。
- 事前チェック: テスト成功、ドキュメント更新（README/ARCHITECTURE/CHANGELOG）、規約準拠。

## セキュリティと設定
- 秘密情報はコミットしない。サイト設定は `config.yaml` を利用し入力値を検証。
- 設定の各種制限（ファイルサイズ、タイムアウト等）を遵守。詳細は `SECURITY.md` と `WEBSOCKET_AUTHENTICATION.md` を参照。

## アーキテクチャ注意点
- `hirundo` 実行ファイルは `HirundoCore` に委譲。機能追加はコアに実装し、CLI で公開する方針。

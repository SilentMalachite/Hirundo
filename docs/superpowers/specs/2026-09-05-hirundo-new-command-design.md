# `hirundo new` 実装設計

- 日付: 2026-09-05
- 対象: `hirundo new post` / `hirundo new page`
- 状態: 設計承認済み

## 1. 背景

`Sources/Hirundo/Commands/NewCommand.swift` の `NewPostCommand.run()` と
`NewPageCommand.run()` はスタブである。引数を印字し、`content/posts`（または
`content/`）を `mkdir -p` して「Full implementation would create the post file」と
出力するだけで、Markdown ファイルを一切書かない。

`--slug` `--categories` `--tags` `--draft` `--path` `--layout` `--open` は
`ArgumentParser` に定義されているが、いずれも `print` されるだけで動作に影響しない。

README.md と README.ja.md は現状を「Not fully implemented」として正しく記載している。
本設計はこの機能を完成させ、ドキュメントの該当記述を削除する。

## 2. 現状調査で判明した制約

### 2.1 CLI ターゲットはテストできない

`Package.swift` のテストターゲット `HirundoTests` は `HirundoCore` にのみ依存する。
既存のテスト 19 ファイルはすべて `@testable import HirundoCore` であり、
`Sources/Hirundo`（実行可能ターゲット）を import しているテストは存在しない。

したがって **CLI ターゲットに書いたロジックはテスト不能**である。
`hirundo init` が `InitCommand` を薄く保ち、実体を `HirundoCore` の
`SiteScaffolder` / `InitDestinationResolver` / `ScaffoldTemplates` に置いているのは
この制約への対応であり、`new` も同じ構造を取る。

### 2.2 `layout:` はビルド時に読まれない

README の Frontmatter 節に明記のとおり、認識されるキーは
`title` `date` `description` `categories` `tags` `draft` `slug` `template` `type` `author`
であり、`layout:` は読まれない。テンプレートの選択は `template:` のみが行う
(`PageRenderer.swift:24`)。

現行の `new page --layout <値>` は、この読まれないキーを連想させる名前を持つ。

### 2.3 `slug:` フロントマターと出力 URL は別系統

- 出力パスはファイル名から導出される (`SiteGenerator.swift:291, 301` の
  `content.url.deletingPathExtension().lastPathComponent`)。
- `Post.slug` は `metadata.slug`（= フロントマターの `slug:`）を優先し、
  無い場合のみファイル名にフォールバックする。
- RSS のアイテム URL は `Post.slug` から組み立てられる
  (`SiteGenerator.swift:400` の `"/posts/\(p.slug)/"`)。

つまり `slug:` をファイル名と異なる値で書くと、**実際の出力 URL と RSS のリンクが
食い違う**。生成物にこの不整合を作り込んではならない。

### 2.4 `SecurityUtilities` は未配線の死んだコード

`SecurityUtilities.validateAndSanitizeEditorCommand`
(`Sources/HirundoCore/SecurityUtilities.swift:11`) はエディタの許可リスト、
パストラバーサル拒否、シェルメタ文字拒否、実行ファイル存在確認を実装し、
`Tests/HirundoTests/EditorCommandValidationTests.swift` に完全なテストを持つ。

しかし **プロダクションコードのどこからも呼ばれていない**。`--open` のために
書かれ、配線されないまま残っている。

### 2.5 参考にする既存パターン

| 要素 | 既存実装 |
|---|---|
| 薄い CLI | `Sources/Hirundo/Commands/InitCommand.swift` |
| 生成ロジック | `Sources/HirundoCore/Scaffold/SiteScaffolder.swift` |
| 埋め込みテンプレート | `Sources/HirundoCore/Scaffold/ScaffoldTemplates.swift` |
| エラー型 | `ScaffoldError`（`Errors.swift:101`）と `toHirundoError()` |
| CLI のエラー表示 | `Sources/Hirundo/ErrorHandling.swift` の `handleError` |
| テスト | `SiteScaffolderTests.swift` / `ScaffoldErrorMappingTests.swift` |
| 設定の読み込み | `CleanCommand.swift:29-38`（config.yaml があれば読み、無ければ既定値） |

## 3. 決定事項

| 論点 | 決定 |
|---|---|
| post のファイル名 | `<slug>.md`（日付プレフィックスなし） |
| `--layout` | `--template` にリネームし、`--layout` は削除 |
| `--open` | 実装して `SecurityUtilities` に配線する |
| 既存ファイル | エラーで中断。上書き手段は用意しない |
| config.yaml が無い場合 | エラーにせず既定値にフォールバックし警告を出す |
| `--draft` | post のみ。page には追加しない |

### 3.1 ファイル名を `<slug>.md` とする理由

出力 URL は `/posts/<ファイル名>/` になる。`hirundo init --blog` が生成する
`content/posts/hello-world.md` も日付プレフィックスを持たない。日付を付けると
`/posts/2026-09-05-my-post/` となり、init 生成物・アーカイブ・RSS のスラグ表記と
規約が二種類混在する。日付はフロントマターの `date:` が保持する。

### 3.2 `slug:` を書き出さない

2.3 の理由により、`--slug` は **ファイル名だけ** を決める。生成する
フロントマターに `slug:` キーは含めない。これによりファイル名が唯一の
スラグの出所となり、出力 URL と RSS リンクが構造的に一致する。

## 4. アーキテクチャ

```
Sources/HirundoCore/Scaffold/
├── ContentScaffolder.swift    (新規) 解決・検証・書き込み
├── ContentTemplates.swift     (新規) フロントマター生成
├── SiteScaffolder.swift       (変更なし)
├── ScaffoldTemplates.swift    (変更なし。yamlQuoted を ContentTemplates と共有)
└── InitDestinationResolver.swift (変更なし)

Sources/HirundoCore/
├── EditorLauncher.swift       (新規) --open の実体
└── Errors.swift               (変更) ContentScaffoldError を追加

Sources/Hirundo/Commands/
└── NewCommand.swift           (変更) 薄いラッパに縮小
```

### 4.1 公開 API

```swift
/// 生成するコンテンツの種別。
public enum ContentKind: Sendable {
    case post
    case page
}

/// 1 本のコンテンツを生成するための入力。
public struct ContentScaffoldOptions: Sendable {
    public var title: String
    /// post のファイル名を決める。nil ならタイトルから生成する。
    public var slug: String?
    /// page の content ディレクトリ相対パス。nil ならタイトルから生成する。
    public var path: String?
    public var categories: [String]
    public var tags: [String]
    public var draft: Bool
    /// フロントマターの template: に書く値。nil なら種別の既定値。
    public var template: String?

    public init(
        title: String,
        slug: String? = nil,
        path: String? = nil,
        categories: [String] = [],
        tags: [String] = [],
        draft: Bool = false,
        template: String? = nil
    )
}

/// 生成に成功した 1 ファイルの情報。
public struct ContentScaffoldResult: Sendable {
    /// 生成したファイルの絶対 URL。
    public let url: URL
    /// プロジェクトルートからの相対パス（例: "content/posts/hello-world.md"）。
    public let relativePath: String
}

/// Markdown コンテンツを 1 本生成する。
///
/// `FileManager` を保持するため `Sendable` にはしない（`SiteScaffolder` と同じ理由）。
public struct ContentScaffolder {
    public init(fileManager: FileManager = .default)

    public func scaffold(
        in projectRoot: URL,
        build: Build,
        limits: Limits,
        kind: ContentKind,
        options: ContentScaffoldOptions,
        date: Date = Date()
    ) throws -> ContentScaffoldResult
}
```

`date` を引数に出すのはテストのためである（`ScaffoldTemplates.helloWorldPost(date:)`
と同じ手法）。

`HirundoConfig` 全体ではなく `Build` と `Limits` を受け取る。この生成処理が使うのは
`build.contentDirectory` と `limits.maxTitleLength` / `maxFilenameLength` だけであり、
`HirundoConfig` を要求すると `config.yaml` が無い場合に呼び出し側が架空の `Site`
（`title` と `url` が必須）をでっち上げる必要が生じる。フォールバックは
`Build.defaultBuild()` と `Limits()` で足りる。

### 4.2 エラー型

`Errors.swift` に `ScaffoldError` と同じ形で追加する。

```swift
public enum ContentScaffoldError: Error, LocalizedError, Equatable, Sendable {
    case invalidTitle(String)
    case invalidSlug(String)
    case invalidPath(String)
    case fileExists(String)
    case cannotCreateDirectory(String)
    case cannotWriteFile(String)
}
```

`toHirundoError()` を実装し、`ErrorCategory` を振り分ける。

| ケース | code | category | suggestion |
|---|---|---|---|
| `invalidTitle` | `INVALID_TITLE` | `.configuration` | 使用可能なタイトルを渡すよう案内 |
| `invalidSlug` | `INVALID_SLUG` | `.configuration` | `--slug` に英数字とハイフンを使うよう案内 |
| `invalidPath` | `INVALID_PATH` | `.configuration` | content ディレクトリ内の相対パスを渡すよう案内 |
| `fileExists` | `FILE_EXISTS` | `.filesystem` | 別の `--slug` / `--path` を使うか既存ファイルを編集するよう案内 |
| `cannotCreateDirectory` | `CREATE_DIR_FAILED` | `.filesystem` | なし |
| `cannotWriteFile` | `WRITE_FAILED` | `.filesystem` | なし |

`Sources/Hirundo/ErrorHandling.swift` の `handleError` に
`ContentScaffoldError` の分岐を追加する（既存の `ScaffoldError` 分岐と同じ形）。

## 5. 生成物の仕様

### 5.1 post

パス: `<contentDirectory>/posts/<slug>.md`

```markdown
---
title: "My Post Title"
date: 2026-09-05T12:00:00Z
categories: ["swift", "development"]
tags: ["static-site"]
draft: true
template: "post.html"
---

# My Post Title

```

- `categories` は `--categories` が実質的な値を持つときのみ出力する。
- `tags` も同様。
- `draft: true` は `--draft` 指定時のみ出力する。指定が無ければ行ごと省略する
  （`draft: false` は書かない。既定と同義であり、ノイズになる）。
- `date` は `ISO8601DateFormatter`、`formatOptions = [.withInternetDateTime]`、
  `timeZone = TimeZone(secondsFromGMT: 0)`。`ScaffoldTemplates.helloWorldPost` と同一。
- `template` の既定値は `"post.html"`。
- `slug:` キーは出力しない（3.2 参照）。
- 本文は `# <title>` と末尾の空行のみ。

### 5.2 page

パス: `<contentDirectory>/<slug>.md`、`--path` 指定時はその相対パス。

```markdown
---
title: "About"
template: "default.html"
---

# About

```

- `template` の既定値は `"default.html"`。
- `date` は出力しない。既存の `content/index.md` / `content/about.md`
  （`ScaffoldTemplates`）に合わせる。

### 5.3 YAML エスケープ

タイトル・カテゴリ・タグの各文字列は `ScaffoldTemplates.yamlQuoted` を通す。
バックスラッシュと二重引用符をエスケープし、二重引用符で囲む。

`SiteScaffolder.forbiddenTitleScalars` と同じ理由で、タイトルに制御文字と
改行系スカラー（U+2028 / U+2029 を含む）が含まれる場合は `invalidTitle` で拒否する。
これらは二重引用符スカラーに素通しで書かれると YAML パーサが空白に畳んでしまい、
値がラウンドトリップしない。

## 6. パスの解決と検証

### 6.1 プロジェクトルートと content ディレクトリ

1. プロジェクトルートはカレントディレクトリ。
2. `config.yaml` が存在すれば `HirundoConfig.load(from:)` で読む。
3. 存在しない、または読み込みに失敗した場合は `Build.defaultBuild()` と `Limits()`
   を使い、その旨を警告として印字する（終了はしない）。`CleanCommand.swift:29-38`
   と同じ方針。
4. content ディレクトリ = `build.contentDirectory`（既定 `"content"`）。

### 6.2 slug の導出

- `--slug` 指定時: その値を使う。
- 未指定時: `title.slugify(maxLength:)`（`StringExtensions.swift:9`）。

`maxLength` には `config.limits.maxFilenameLength - 3`（`.md` の 3 文字分）を渡す。
`slugify` は空になると `"untitled"` を返すので、日本語のみのタイトルでも
パーセントエンコードされた有効なスラグが得られる。

導出後の slug に `/`、`\`、`..`、NUL、制御文字が含まれる場合は `invalidSlug` を投げる。
`--slug` はファイル名 1 個であり、パスではない。

### 6.3 `--path`（page のみ）

- content ディレクトリからの相対パスとして解釈する。例: `--path about/team` →
  `content/about/team.md`。
- `path` と `slug` の両方が指定された場合は `path` が優先される。CLI からは
  `NewPageCommand` が `--path` のみ、`NewPostCommand` が `--slug` のみを渡すため
  この状況は起きないが、API としての挙動を定義しておく。
- 末尾が `.md` の場合はそのまま使い、`.md` を二重に付けない。
- `PathSanitizer.sanitize` に通す。同関数は `..`、`./`、先頭 `/`、NUL、`://` を
  含む入力に対して空文字列を返すので、**空文字列が返ったら `invalidPath` を投げる**。
- サニタイズ後、`content` ディレクトリを基準に解決した URL を
  `standardizedFileURL` にし、そのパスが content ディレクトリのパスを
  プレフィックスに持つことを確認する。持たなければ `invalidPath`。
- 中間ディレクトリは `withIntermediateDirectories: true` で作成する。

### 6.4 title の検証

`ConfigValidation.validateNonEmptyAndLength(title, maxLength: config.limits.maxTitleLength,
fieldName: "Title")` を使う。`ConfigError` が飛んだら `invalidTitle` に変換する
（`SiteScaffolder.validateTitle` と同じ変換）。

### 6.5 categories / tags のパース

CLI 側でカンマ区切り文字列を配列に変換する。

1. `,` で分割
2. 各要素を `trimmingCharacters(in: .whitespacesAndNewlines)`
3. 空要素を除去
4. 順序を保ったまま重複を除去

`"swift, , swift ,web"` → `["swift", "web"]`。

## 7. 書き込みとロールバック

1. 出力先ファイルが既に存在すれば `fileExists` を投げる。**上書きしない。**
2. 親ディレクトリが存在しなければ作成する。作成に失敗したら
   `cannotCreateDirectory`。
3. `Data(contents.utf8).write(to: url, options: .atomic)` で書き込む。失敗したら
   `cannotWriteFile`。
4. 書き込みに失敗し、かつ手順 2 でディレクトリを新規作成していた場合は、
   `SiteScaffolder.topmostMissingAncestor` と同じ考え方で、この実行が作った
   最上位のディレクトリを削除して巻き戻す。既存ディレクトリには触れない。

`SiteFileManager` は使わない。`SiteScaffolder` が使わないのと同じ理由で、
同型はシンボリックリンクを解決してから書き込むため、ユーザーが明示した
パスにそのまま書くべきこの用途には合わない。

## 8. `--open`

新規 `Sources/HirundoCore/EditorLauncher.swift`。

```swift
public enum EditorLauncher {
    /// 環境変数からエディタコマンドを解決する。
    /// $VISUAL を優先し、無ければ $EDITOR を見る。
    public static func resolveEditorCommand(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String?

    /// 指定ファイルをエディタで開く。
    /// - Returns: 起動できたかどうか。
    @discardableResult
    public static func open(_ fileURL: URL) -> Bool
}
```

- `resolveEditorCommand` は `$VISUAL` → `$EDITOR` の順に読み、値を
  `SecurityUtilities.validateAndSanitizeEditorCommand` に通す。検証に落ちたら `nil`。
- `open` は `Process` でエディタを起動する。シェルを経由しない
  （`/bin/sh -c` を使わない）。引数はファイルパス 1 個のみ。
- 起動して終了を待つ。ターミナル型エディタ（vim, nano）が前面に来る必要があるため、
  標準入出力は継承する。

**失敗時の扱い**: `$EDITOR` が未設定、検証に落ちた、起動に失敗した、のいずれでも
警告を標準エラーに出すだけで、**終了コードは 0 のまま**とする。ファイルはすでに
生成されており、それを失敗として報告するのは事実に反する。

これが `SecurityUtilities` の最初の呼び出し元となり、
`EditorCommandValidationTests` が守る対象が実在するようになる。

## 9. CLI の変更

`Sources/Hirundo/Commands/NewCommand.swift`。

### 9.1 オプションの変更

`NewPageCommand` のみ:

```diff
- @Option(name: .long, help: "Template layout")
- var layout: String = "default"
+ @Option(name: .long, help: "Template file name (default: default.html)")
+ var template: String?
```

`NewPostCommand` にも同じ `--template` を追加する（既定 `post.html`）。
既存の `--slug` `--categories` `--tags` `--draft` `--path` `--open` `--verbose`
はシグネチャを変えず、初めて実際に機能するようになる。

### 9.2 run() の構造

両サブコマンドとも同じ形になる。

1. config を読む（6.1）
2. カンマ区切りをパースする（6.5）
3. `ContentScaffolder().scaffold(...)` を呼ぶ
4. 成功: `✅ Created <relativePath>` を印字
5. `--open` 指定時: `EditorLauncher.open(result.url)`
6. 失敗: `handleError(error, context: "New post", verbose: verbose)` の後
   `throw ExitCode.failure`

現行の絵文字付き引数エコー（`📝 Creating new blog post...` 以下 7 行）は削除する。
`init` は同種の情報を 3 行に留めており、そちらに合わせる。

## 10. テスト計画

TDD で進める。各項目は先に失敗するテストを書いてから実装する。

### 10.1 `Tests/HirundoTests/ContentScaffolderTests.swift`（新規）

**post の生成**
- 既定オプションで `content/posts/<slug>.md` が作られる
- 生成物が `MarkdownParser.parse` でパースでき、`title` / `date` / `template` が読める
- `--slug` 明示時にその名前のファイルになる
- タイトルからのスラグ自動生成（`"Hello World"` → `hello-world.md`）
- 日本語タイトルが `slugify` のパーセントエンコードを経て有効なファイル名になる
- `maxFilenameLength` を超える長いタイトルが切り詰められる
- `slug:` キーがフロントマターに **含まれない** こと
- `categories` / `tags` が YAML 配列として出力され、再パースできる
- `--categories "swift, , swift ,web"` が `["swift", "web"]` になる
- categories / tags 未指定時にキーごと省略される
- `--draft` 時に `draft: true` が出力され、未指定時はキーごと省略される
- `--draft` で生成した post が `includeDrafts: false` のビルドから除外される
- 引用符やバックスラッシュを含むタイトルが正しくエスケープされ、再パースで元に戻る
- 制御文字 / U+2028 / U+2029 を含むタイトルが `invalidTitle` で拒否される

**page の生成**
- 既定で `content/<slug>.md`、`template: "default.html"`
- `date` キーが出力されないこと
- `--path about/team` → `content/about/team.md`（中間ディレクトリ作成）
- `--path about/team.md` が `.md` を二重に付けない
- `--path ../outside` が `invalidPath`
- `--path /etc/passwd` が `invalidPath`
- `--path` が content 外に解決される場合に `invalidPath`

**共通**
- カスタム `build.contentDirectory` が反映される
- 既存ファイルがあると `fileExists` を投げ、**既存ファイルの内容が無傷**であること
- `--template` 明示時にその値が `template:` に出る
- 書き込み失敗時に、この実行が作ったディレクトリが残らない

**統合**
- 生成した post を `SiteGenerator` でビルドし、`_site/posts/<slug>/index.html`
  が出力されることを確認する（既存 `IntegrationTests.swift` のパターンに倣う）

### 10.2 `Tests/HirundoTests/ContentScaffoldErrorMappingTests.swift`（新規）

`ScaffoldErrorMappingTests.swift` に倣い、各 `ContentScaffoldError` ケースの
`toHirundoError()` が期待する `code` / `category` / `suggestion` の有無を返すことを
検証する。

### 10.3 `Tests/HirundoTests/EditorLauncherTests.swift`（新規）

- `$VISUAL` が `$EDITOR` より優先される
- どちらも未設定なら `nil`
- 許可リスト外のエディタ（`$EDITOR=malicious`）で `nil`
- シェルメタ文字入り（`$EDITOR="vim; rm -rf /"`）で `nil`
- 空文字列 / 空白のみで `nil`

`open(_:)` の実プロセス起動はテストしない。検証ロジックのみを対象とする。

## 11. ドキュメントの変更

### 11.1 README.md

- `### hirundo new` の「⚠️ **Not fully implemented.**」ブロック（4 行）を削除する。
- コマンド書式の `--layout <layout>` を `--template <template>` に変更し、
  post 側にも `--template` を追加する。
- 各オプションの説明表を追加する（`hirundo clean` 節と同じ体裁）。
- 生成されるファイルの例（パスとフロントマター）を示す。
- `--slug` がファイル名を決めること、フロントマターに `slug:` を書かないことを明記する。
- `--open` が `$VISUAL` / `$EDITOR` を許可リストで検証してから起動すること、
  失敗しても終了コードが 0 であることを明記する。
- 「Not Yet Implemented」節から
  「**`hirundo new post` / `hirundo new page` file creation.**」の行を削除する。

### 11.2 README.ja.md

11.1 と同じ変更を日本語で行う。

### 11.3 CLAUDE.md

「新規コンテンツの作成」節を実際のオプションを含む形に更新する。

### 11.4 CONTRIBUTING.md

`new`（`new post` / `new page`）に関する記述は現状のままで正しい。変更不要。

## 12. 実装フェーズ

| Phase | 内容 | 完了条件 |
|---|---|---|
| 1 | `ContentScaffoldError` + `ContentScaffolder` + `ContentTemplates` | 10.1 / 10.2 のテストが通る |
| 2 | `NewCommand` の配線、`--layout` → `--template`、`handleError` 分岐追加 | `swift build` が通り、手動で post / page を生成できる |
| 3 | `EditorLauncher` と `--open` | 10.3 のテストが通る |
| 4 | README ×2 / CLAUDE.md の更新 | ドキュメントとコードが一致する |

各フェーズ終了時に `swift build` と `swift test` を実行する。

## 13. スコープ外

- `new` に追加のサブコマンド（`new draft` など）を足すこと
- page への `--draft` 追加
- 既存ファイルの上書き手段（`--force` 等）
- テンプレートのカスタマイズ機構（ユーザー定義のコンテンツ雛形）
- `slug:` フロントマターの取り扱いを `SiteGenerator` 側で変更すること
  （2.3 の URL と RSS の不整合そのものは既存の問題であり、本作業では
  生成物がその不整合を作らないようにするに留める）

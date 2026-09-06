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
- **🧩 組み込み機能**: サイトマップ、RSS、検索インデックス、アセット最小化、アセットのフィンガープリントを単純なオン/オフフラグで提供
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

サイトは `http://127.0.0.1:8080`（`serve` が表示し、ブラウザで開くアドレスです）で
ライブリロード機能と共に利用できます。

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

コンテンツディレクトリの走査はシンボリックリンクをたどります。`content/posts` が別の場所の
ディレクトリへのリンクであっても、その先のMarkdownはビルドされ、各ページのURLは
`content/` 配下のパスどおりになります（実体がどこにあっても `content/posts/hello.md` は
`/posts/hello/` に出力されます）。リンクをたどるのは、その先がプロジェクトディレクトリ
（`config.yaml` があるディレクトリ）の内側にとどまる場合だけです。つまりビルドが読む
Markdownはプロジェクト内のものに限られます。マシン上のそれ以外の場所を指すリンクや、
プロジェクトディレクトリ自身を指すリンク（`content/up -> ..`）は読み飛ばし、出力
ディレクトリ・`static`・`templates` を指すリンクも同様に読み飛ばします。単一のファイルを
指すリンクにも同じ規則が適用され、`content/notes.md -> ../shared/notes.md` はビルドされ、
`content/leak.md -> /Users/someone/private-notes.md` は読み飛ばされます。同じディレクトリに
入るのは1ビルドにつき1回だけなので、互いを指し合うリンクやすでに走査済みの場所を指す
リンクも無限にたどらず終了します。どう判断したかはビルド中にすべて表示されます
（`Following content symlink: content/posts -> ../shared-posts`）。

### `hirundo serve`
ライブリロード付きの開発サーバーを起動します。

```bash
hirundo serve [オプション]

オプション:
  --port <ポート>       サーバーポート（デフォルト: config.yaml の server.port）
  --host <ホスト>       バインドする数値アドレス（デフォルト: localhost）
  --no-reload           ライブリロードを無効化
  --no-browser          ブラウザを自動で開かない
  --drafts              下書き記事を含める
  --verbose             詳細なエラー情報を表示
```

`serve` はカレントディレクトリの `config.yaml` を読み込み、一度ビルドしてから配信を開始し、
以後は変更を監視します。ポートとライブリロードのどちらも優先順位は同じで、CLI引数 >
`config.yaml` の `server` ブロック > 組み込みの既定値（ポート8080、ライブリロード有効）の
順です。`--port` を指定すると `server.port` を上書きし、`--no-reload` を指定すると
`server.liveReload` の値に関わらずライブリロードを無効化します。どちらも指定しなければ
`config.yaml` の設定に従います。ポートはどちらで指定した場合も 1〜65535 の範囲である必要が
あります。

`--host` はサーバーが実際にバインドするアドレスで、受け付けるのは数値アドレスと `localhost`
の2種類のみです。それ以外のホスト名を渡すとエラーになります。デフォルトの `localhost` は
IPv4のループバックアドレスに解決されるため、接続できるのはこのマシンだけです。他のマシンか
らの接続を許可するには `--host 0.0.0.0` を明示してください。ただしその場合、このマシンに到達
できる相手は誰でもサイトを閲覧できるため、信頼できるネットワークでのみ使用してください。
その際はサイトをIPアドレスで開いてください。ホスト名は後述のライブリロードの検証で拒否され
ます。

- ディレクトリへのリクエストは、そのディレクトリの `index.html` に解決されます。
  `/`、`/about`、`/about/` はいずれも動作します。
- 出力ディレクトリの外へ出るリクエスト（`/../../etc/passwd` など）は拒否されます。
- ライブリロードが有効な場合、`serve` は `content` / `templates` / `static` の各ディレクトリ
  （出力ディレクトリは対象外）を監視して変更のたびに再ビルドし、接続中のすべてのブラウザに
  `/livereload` のWebSocket経由でリロードを送ります。
- `/livereload` のハンドシェイクは、接続をアップグレードする前に検証されます。受け付けるのは、
  リクエストの `Origin` ヘッダのホストとポートが宛先の `Host` と一致し、かつその `Host` が
  IPアドレスか `localhost` である場合だけです。2つの規則はどちらも必要です。前者はブラウザで
  たまたま開いている別のページが開発サーバーに接続してくるのを防ぎ、後者はループバックアドレス
  に解決される名前を使って前者をすり抜けるのを防ぎます。拒否したハンドシェイクには `403` を
  返し、理由を端末に表示します。拒否されたブラウザは永久に再接続を繰り返すため、表示するのは
  理由が変わったときだけです。設定項目はありません。またこれは認証ではありません。識別して
  いるのはページであって人ではなく、ポートに到達できる相手はサイトを閲覧できます。
- 再ビルドでは出力ディレクトリをクリーンしません。そのため、ページを削除してもすでに生成済み
  のHTMLはそのまま残り、そのURLは古い内容を返し続けます。削除するには
  `hirundo build --clean` を実行してください。
- `config.yaml` は起動時に一度だけ読み込みます。`serve` の実行中に編集しても反映されません。
  サーバーを停止してから起動し直してください。
- `build.outputDirectory` が監視対象のディレクトリの内側にある場合（またはその逆の場合）、
  `serve` は起動を拒否します。再ビルドのたびに次の再ビルドが始まり、止まらなくなるためです。

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
| `--slug` | `.md` を除いたファイル名。指定した文字列をそのまま使います。省略時はタイトルから生成します。記事では `index` は予約されています。 |
| `--categories` | カンマ区切り。空要素と重複は除去されます。制御文字と改行は拒否されます。 |
| `--tags` | カンマ区切り。空要素と重複は除去されます。制御文字と改行は拒否されます。 |
| `--template` | `template:` キーの値。既定は `post.html`。制御文字と改行は拒否されます。 |
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
| `--path` | content ディレクトリからの相対パス。`--path about/team` は `content/about/team.md` を作成し、中間ディレクトリも作ります。省略時はタイトルから生成します。各構成要素は `limits.maxFilenameLength` 文字（既定 255）までで、超えるものがあると拒否されます。短い名前が続く深い階層は問題ありません。 |
| `--template` | `template:` キーの値。既定は `default.html`。制御文字と改行は拒否されます。 |
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
  `/`、`\`、`.`、`..`、制御文字、空の値、ファイル名の長さ制限を超える値です。
- **記事では `index` は予約語です。** `content/posts/index.md` は `/posts/` として
  公開される一方、RSS のリンクはスラグから作られて `/posts/index/` を指してしまうため、
  `--slug index` も `index` にスラグ化されるタイトルも拒否されます。ページは対象外です。
  `content/index.md` は `hirundo init` が生成するホームページであり、
  `content/about/index.md` が `/about/` として公開されるのも正当で、
  ページはフィードに含まれないため食い違いは起きません。
- `--categories` / `--tags` / `--template` はフロントマターに引用符付きの値として
  書き出されるため、制御文字と改行は作成前に拒否されます。そのまま書き出すと、
  生成されたファイルがビルド時に解析できなくなるためです。
- `--open` は許可リスト（`vim`、`nvim`、`nano`、`emacs`、`code`、`subl`、`vi`、`open` など）
  にあるエディタのみを、シェルを経由せずに起動します。コマンド名は単体で実行するため、
  引数付きの値（`code --wait`、`vim +startinsert` など）は不許可です。決められた一覧に
  無い絶対パスも不許可になります。検証した対象をそのまま実行します。許可された絶対パス
  （`/usr/bin/vim`）はそのファイルを直接実行し、`PATH` から探すのはコマンド名だけを
  指定した場合（`vim` など）に限られます。`$EDITOR` が
  未設定・不許可・起動失敗のいずれでも、警告を表示するだけで終了コードは 0 のままです
  （ファイルは既に作成済みのため）。警告は「未設定」と「設定されているが不許可」を
  区別し、不許可の場合はその値を表示します。
  エディタの実行中は端末をエディタに預けるため、全画面エディタも通常どおり描画され、
  Ctrl-Z は他のコマンドと同じようにジョブを中断します。`hirundo` もエディタと一緒に停止し、
  シェルが端末を取り戻してプロンプトを表示します。`fg` で両方とも再開します。

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

### `hirundo validate`
ビルドせずに設定ファイルだけを検査します。

```bash
hirundo validate [オプション]

オプション:
  --config <ファイル>  設定ファイルのパス（デフォルト: config.yaml）
  --verbose            詳細なエラー情報を表示
```

報告される問題は2種類あります。デコードできない設定は**エラー**で、終了コードは非0になり、
原因となったキーを名指しします（`Missing required field: site.url`、
`Invalid configuration value: blog.postsPerPage: expected Int`）。デコードはできるが Hirundo が
解釈しないキーが含まれている場合 — 綴り間違いや、[`timeouts` / `server.cors`](#未実装の項目)
のように配線されていないブロック — は stderr への**警告**にとどまり、終了コードは0のままです。
それらを黙って無視するのがパーサーの実際の挙動だからです。

検査するのはトップレベルとその1階層下までです（`features.sitemp` は検出されます）。
それより深い階層は見ていません。

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

`config.yaml` のトップレベルキーは `site`、`build`、`server`、`blog`、`features`、`limits`、
`assets` のちょうど7つです。必須は `site` のみで、他のブロックは省略するとデフォルト値になります。

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
# ブロックごと省略した場合は5つとも false になります。
features:
  sitemap: true
  rss: true
  searchIndex: true
  minify: true
  fingerprint: true

# セキュリティとパフォーマンスの制限。各キーは省略可能で、以下の値はいずれも省略時のデフォルトです。
limits:
  maxMarkdownFileSize: 10485760      # 10MB
  maxFrontMatterSize: 100000         # 100KB
  maxFilenameLength: 255
  maxTitleLength: 200
  maxDescriptionLength: 500
  maxUrlLength: 2000
  maxAuthorNameLength: 100
  maxEmailLength: 254
  maxLanguageCodeLength: 35

# フィンガープリント除外の追加パターン（組み込みの一覧に追加されます。詳細は後述の
# 「組み込み機能」を参照）。オプションで、無ければブロックごと省略できます。
assets:
  fingerprintExclude:
    - "apple-touch-icon*.png"
    - "ads.txt"
```

最小限の設定は、必須の2項目だけです。

```yaml
site:
  title: "マイサイト"
  url: "https://example.com"
```

### 注意点

- **オプションの各ブロックは一部のキーだけを書けます。** `features` / `limits` / `assets` /
  `build` / `server` / `blog` はいずれも、書かなかったキーにデフォルト値を使います。制限値を1つ
  変えるために残り9つを書き直す必要はありません。解釈されないキーは `hirundo validate` が
  報告します。
- **値はデコードされるだけでなく検証されます。** `site.url` はスキームとホストを持つURLで
  なければならず、`site.language` は BCP 47 として妥当なタグ（`en`、`en-US`、`zh-Hans` など）、
  `site.author.email` はメールアドレスの形式である必要があります。`limits` の各値は正の整数で
  なければなりません。これらに反する設定は、黙って無視されるのではなくビルドが失敗します。
  なお `site.*` の長さ上限は固定値（タイトル200、説明500、URL 2000、著者名100、メール254）で、
  `limits` ブロックからは**読まれません**。
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
| `features` | 5つともfalse |
| `limits` | 上記の例に記載した値 |
| `assets` | 追加の除外パターンなし（組み込みの一覧はそのまま適用されます） |

`hirundo init` は `features` までを書き出し、`limits` と `assets` は出力しません。したがって
両方ともデフォルト値で動作します。`assets:` ブロックが無くても、組み込みのフィンガープリント
除外は適用されます。

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

Hirundoには5つの組み込み機能があり、`features` ブロックで切り替えます。セキュリティと
単純さのため、外部コードの動的読み込みはサポートしていません。

| フラグ | 効果 |
|-------|------|
| `sitemap` | 出力のルートに `sitemap.xml` を書き出します |
| `rss` | 記事から `rss.xml` を書き出します |
| `searchIndex` | クライアントサイド検索用に `search-index.json` を書き出します |
| `minify` | アセットパイプラインでCSSとJSの最小化を有効にします |
| `fingerprint` | アセット名に内容ハッシュを付け、HTMLとCSSの参照を書き換えます |

`minify` が対象とするのは**CSSとJSのアセットのみ**です。生成されるHTMLは最小化されません。

`fingerprint` を有効にすると、`static/` のアセットの大半は `style-9f2a1c04b7e3d5a1.css` の
ような内容ハッシュ付きの名前で出力され、生成されたHTMLの `href` / `src` / `srcset`、CSSの
`url(...)`、`<style>` の本文と `style` 属性がその名前を指すように書き換えられます。対応表は
`_site/asset-manifest.json` に書き出されます。古い世代のハッシュ名のファイルはビルドのたびに
削除されるため、`hirundo serve` を回し続けても出力が膨れません。ただしこの掃除はフラグが
有効な間しか走らないため、`fingerprint` を後から無効に戻しても、既にハッシュ名で書き出された
出力は削除**されません**。フラグをどちらの向きに変更したときも、変更後は
`hirundo build --clean` を実行してください。

一部のアセットはフィンガープリントの対象から除外されます。詳細は後述の
[フィンガープリントからのアセット除外](#フィンガープリントからのアセット除外)を参照してください。

制限は次のとおりです。

- **URLとして書き換えるHTML属性は `href` / `src` / `srcset` の3つだけです。** これに加えて
  `style` 属性の値と `<style>` の本文は、CSSの `url(...)` を書き換えるのと同じ経路で処理
  されます。`data-src` や `poster`、`background` のような、ブラウザがアセットを読み込みうる
  他の属性は対象外です。
- **参照とマニフェストの照合は逐語的で、パーセントデコードはしません。** `/images/my%20photo.jpg`
  のようなパーセントエンコード済みのパスは、`images/my photo.jpg` として格納されたアセットの
  マニフェスト項目とは一致しないため無変更のまま残り、対象がハッシュ名に変わった後はリンク切れに
  なります。これは一般的な規則の一例です。マニフェストで解決できなかった参照は、設計上、
  警告無しでそのまま通されます（下記のCSSからCSSへの参照だけが警告を出す例外です）。
- **JavaScript内の参照は書き換えません。** `fetch("/images/logo.png")` のような文字列が参照
  かどうかは静的には判定できないためです。JSからアセットを参照する場合は
  `asset-manifest.json` を読んでください。
- **CSSからCSSへの `@import url(...)` は書き換えません。** 参照先のハッシュがまだ確定していない
  ためです。この形の参照を見つけると警告を出します。
- **決まった既知の名前で取得されるファイルは、フィンガープリントの対象から自動的に除外
  されます。** `robots.txt`、`favicon.ico`、`CNAME`、`_headers`、`_redirects`、
  `.htaccess`、そして `.well-known/` 配下のすべてのファイルがこれに当たります。これらは
  どのページからも参照されないため書き換えようがなく、改名してしまうと既知の名前への
  リクエストがすべて404になってしまいます。これらの組み込みパターンには設定は不要です。
  追加のパターンは `assets.fingerprintExclude` で指定できます。詳細は後述の
  [フィンガープリントからのアセット除外](#フィンガープリントからのアセット除外)を参照して
  ください。

### フィンガープリントからのアセット除外

上記の組み込み一覧 ── `robots.txt`、`favicon.ico`、`CNAME`、`_headers`、`_redirects`、
`.htaccess`、`.well-known/**` ── は、`config.yaml` に `assets:` ブロックがあるかどうかに
関わらず常に適用されます。除外するファイルを追加するには、`assets.fingerprintExclude` に
パターンを列挙します。

```yaml
assets:
  fingerprintExclude:
    - "apple-touch-icon*.png"
    - "ads.txt"
```

パターンは組み込みの一覧に**追加**されるだけで、組み込みパターンを取り除くことはできません。
除外されたアセットは元の名前のまま書き出され、マニフェストにも自分自身への対応として載るため、
そのアセットへの参照は変わらず機能し、プルーナーも古い出力として扱いません。

パターンは、static ディレクトリからの相対パスに対して `/` 区切りで照合されます。

- `/` を含まないパターンは、深さに関わらずファイル名に一致します（`ads.txt` は `ads.txt` にも
  `vendor/ads.txt` にも一致します）
- `/` を含むパターンはパス全体に一致します（`css/style.css` は `deep/css/style.css` には
  一致しません）
- `*` は1つのパスセグメント内でのみ一致し、`/` をまたぎません
- `**` を1つのセグメントとして書くと、0個以上の任意の数のセグメントに一致します
- それ以外はすべて文字どおりの一致です。大文字・小文字は区別され、`?` やキャラクタークラス、
  エスケープ、否定はありません。

アーカイブ、カテゴリー、タグの各ページは、これとは別に `blog` ブロックで制御します。

## 未実装の項目

以前のバージョンの本ドキュメントで「動作する」と記載されていたため、ここに明記します。
以下はいずれも実装されていません。

- **CORS設定**。`server.cors` ブロックは存在しません。`server` が受け付けるのは `port` と
  `liveReload` のみで、その下に `cors:` を書いても黙って無視されます。
- **タイムアウト設定**。`timeouts` ブロックは存在せず、ファイル操作、ディレクトリ操作、
  HTTPリクエスト、ファイル監視、サーバー起動のいずれについても設定可能なタイムアウトは
  ありません。
- **プラグインアーキテクチャ**。プラグインシステムは削除され、`features` の5つのフラグが
  その役割を担っています。カスタムプラグイン開発のサポートはなく、`imageOptimization` や
  `syntaxHighlight` という機能も存在しません。
- **ライブリロードのWebSocket認証**。`/auth-token` エンドポイントもトークンによるハンド
  シェイクも無く、設定項目もありません。`/livereload` は `Origin` と `Host` の検証
  （[`hirundo serve`](#hirundo-serve)を参照）で守られていますが、これはブラウザ内の別ページを
  締め出すだけで、接続してきた相手が誰であるかを確かめるものではありません。ポートに到達でき
  る相手はサイトを閲覧でき、IPアドレスでサイトを開けばライブリロードにも接続できます。開発
  サーバーを信頼できないネットワークに公開しないでください。
- **アセットの結合とソースマップ**。JS/CSSの結合とソースマップ生成は削除されました。
  結合は `AssetConcatenator` ごと、ソースマップは `sourceMap` オプションごと消えています。
  JSのトランスパイル（`transpile` / `target`）も同様です。ES6+の変換には Babel や esbuild を
  使ってください。
- **フロントマターの `layout:`**。`template:` を使用してください。

`config.yaml` にこの一覧のキーを書いている場合、`hirundo validate` がすべて報告します。

## セキュリティ

Hirundoは静的サイトジェネレーターとして適切なセキュリティ対策を実装しています。

- **入力検証**: Markdownファイル、設定ファイル、フロントマターの設定可能なサイズ制限。
  タイトル、説明、URL、著者名、メールアドレス、言語コードの長さ制限。
- **パス検証**: `build` の各ディレクトリは絶対パスや `..` を含むことができません。開発サーバーは
  出力ディレクトリの外へ出るリクエストパスを拒否します。
- **アセット処理**: 最小化を任意で有効にできるCSS/JS処理。
- **開発サーバー**: ライブリロードのハンドシェイクは、アドレスでサーバーに到達した同一オリジン
  のページからのものだけを受け付けます。終了時にはWebSocketセッションとファイル監視を後始末
  します。

セキュリティポリシーについては[SECURITY.md](SECURITY.md)をご覧ください。

### 付属フィクスチャでのローカル確認

付属のフィクスチャでエンドツーエンドの確認ができます。

```bash
cd test-hirundo
swift run --package-path .. hirundo build --clean
swift run --package-path .. hirundo serve
# ブラウザで http://127.0.0.1:8080 を開き、test-hirundo/content/ 配下を編集
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

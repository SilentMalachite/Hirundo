# `hirundo serve` ライブリロード 設計書

日付: 2026-09-05

## 背景

`hirundo serve` はすでに存在し、`config.build.outputDirectory` の中身を HTTP で配信する。
だがライブリロードは配線されていない。`DevelopmentServer` は `hotReloadManager` プロパティを
宣言するだけで一度も生成せず、`/livereload` の WebSocket は `ping` に `pong` を返すだけである。

その結果、README と CLAUDE.md が謳う「ライブリロード付き開発サーバー」は次の状態にある。

| 機能 | 現状 |
|---|---|
| 静的配信・ディレクトリ→`index.html` 解決・出力ディレクトリ外の拒否 | 動作する |
| `/livereload` WebSocket エンドポイント | 存在するが ping/pong のみ |
| ファイル監視 | **無い**（`HotReloadManager` は生成されない） |
| 初回ビルド | **無い**（`_site` が無ければ全リクエストが 404） |
| 変更時の再ビルド | **無い**（`SiteGenerator` は `serve` から呼ばれない） |
| ブラウザへのリロード通知 | **無い**（WebSocket セッションを保持していない） |
| クライアントスクリプト | **無い**（誰も `/livereload` に接続しない） |

素材は揃っている。`HotReloadManager` は FSEvents ベースで symlink 境界にも対応済み、
`SiteGenerator.buildWithRecovery` はエラー回復付きのビルドを返す。欠けているのは接続だけである。

同時に、`serve` には配線とは独立した3つの欠陥がある。本設計はこれらも対象に含める。

- `--host` の値が無視され、実際には**全インターフェースで listen している**。
  認証の無い WebSocket が LAN に露出する。
- `withTaskCancellationHandler` による Ctrl+C 処理は SIGINT では発火しない。
  `stop()` は呼ばれず、サーバはプロセスごと即死する。
- `config.server.port` と `config.server.liveReload` は読み込まれるが参照されない。

## スコープ

含む: 初回ビルド、ファイル監視、全体再ビルド、WebSocket によるリロード通知、
HTML へのクライアントスクリプト注入、bind アドレスの修正、シグナル処理の修正、
`config.server` の尊重。

含まない: 差分ビルド（依存グラフ）、ブラウザ上のエラーオーバーレイ、
WebSocket 認証、CORS 設定。再ビルド失敗は端末表示に留める。

`serve` は `config.yaml` を決め打ちで読む。`build` にある `--config` 相当の
オプションは今回追加しない（本設計の目的と独立しており、別途扱う）。

## 決定事項

### 再ビルドは常にサイト全体

`SiteGenerator` にはサイト全体をビルドする API しかなく、差分ビルドには
ページ単位の依存グラフが要る。1つの記事を変更するとアーカイブ、カテゴリー、タグ、
RSS、サイトマップが同時に変わるため、依存グラフは小さくならない。

したがって変更の種類にかかわらず `buildWithRecovery` を丸ごと呼ぶ。
既存 API のみで済み、存在し続けるページについては差分ビルド特有の取りこぼし
（一部のページだけが古いまま残る）が起きない。
static ファイルだけの高速パスも設けない（経路が2つに増える割に得るものが小さい）。

ただし再ビルドは `clean: false` で行うため、**削除されたコンテンツの出力は消えずに残る**。
`content/about.md` を削除しても再ビルドは成功し、ブラウザもリロードされるが、
`_site/about/index.html` は残り続けるので `/about/` は古いページを返す。
これを消すには `hirundo build --clean` を実行する。

`serve` を `clean: true` にはしない。配信中に出力ツリーを丸ごと削除して書き直すと、
その間に届いたリクエストが無作為に 404 になる。滅多に起きない削除のために、
毎回の再ビルドで確実に壊れるほうを選ぶ理由はない。

### `--host` は実際のバインドアドレスになる

Swifter は `HttpServer.listenAddressIPv4` / `listenAddressIPv6` でバインドアドレスを
受け付けるが、値は `inet_pton` を通るので**数値アドレスのみ**である。`localhost` という
文字列は渡せない。

既定の `localhost` はループバックだけに bind する。外部に出したい利用者は
`--host 0.0.0.0` を明示する。既存の振る舞いは変わるが、認証の無いライブリロード
WebSocket を既定で LAN に開くほうが問題である。

### クライアントスクリプトはサーバ側で注入する

テンプレートに `{% if livereload %}` のような分岐を持ち込まない。利用者のテンプレートを
汚さず、`hirundo build` の出力に開発用スクリプトが混入する事故も起きない。

## アーキテクチャ

`DevelopmentServer` に監視・ビルド・通知・注入をすべて足すと神クラスになる。
責務を4つに分ける。

| ユニット | 責務 | 依存 |
|---|---|---|
| `DevelopmentServer`（既存・縮小） | HTTP 配信、パス解決、bind、`/livereload` の受け口 | `LiveReloadHub`、`LiveReloadScriptInjector` |
| `LiveReloadHub`（新規 actor） | 接続中クライアントの登録・解除・ブロードキャスト | なし |
| `LiveReloadScriptInjector`（新規 struct） | HTML 文字列へのスクリプト挿入（純関数） | なし |
| `RebuildCoordinator`（新規 actor） | 変更バッチ→再ビルドの直列化→Hub への通知 | `SiteGenerator`、`LiveReloadHub` |
| `ServeCommand`（既存） | 配線、シグナル処理、ブラウザ起動 | 上記すべて |

### `LiveReloadHub`

```swift
public protocol LiveReloadClient: AnyObject, Sendable {
    var id: ObjectIdentifier { get }
    func send(_ text: String)
}

public actor LiveReloadHub {
    public func add(_ client: LiveReloadClient)
    public func remove(_ client: LiveReloadClient)
    public func broadcast(_ message: String)
    public var clientCount: Int { get }
}
```

`WebSocketSession` を直接抱えず `LiveReloadClient` 越しに扱う。テストで fake を差せる。
actor にすることで、この repo に手書きロックをもう一つ増やさずに済む。

Swifter の `websocket(text:binary:pong:connected:disconnected:)` が `connected` と
`disconnected` のコールバックを提供するので、登録と解除はそこで行う。
`WebSocketSession` を `LiveReloadClient` に適合させる薄いラッパーを置く。

送るメッセージは `"reload"` のみ。プロトコルはこれ以上増やさない。

### `LiveReloadScriptInjector`

```swift
public struct LiveReloadScriptInjector {
    public init(endpointPath: String = "/livereload")
    public func inject(into html: String) -> String
}
```

`</body>` の直前に `<script>` を挿入する。大文字小文字を区別せず、複数出現する場合は
**最後の** `</body>` を使う。`</body>` が無い HTML には末尾に追加する。

注入するスクリプトの要件:

- `new WebSocket((location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/livereload")`
- `onmessage` で本文が `"reload"` なら `location.reload()`
- `onclose` で指数バックオフ（初回 500ms、上限 10 秒）で再接続する。
  `serve` を再起動してもブラウザが自力で復帰するため。
- スクリプト全体を IIFE で包み、ページのグローバル空間を汚さない

### `RebuildCoordinator`

```swift
public actor RebuildCoordinator {
    public init(build: @escaping @Sendable () async throws -> BuildResult,
                onSuccess: @escaping @Sendable () async -> Void,
                onFailure: @escaping @Sendable (Error) async -> Void)
    public func requestRebuild() async
}
```

再ビルドを直列化する。ビルド実行中に届いた要求は捨てず、フラグとして1回分にまとめ、
完了後にもう一度だけ走らせる（in-flight と pending の2状態のみ）。要求が10回来ても
ビルドは最大2回で収束する。

`build` クロージャは `SiteGenerator.buildWithRecovery(clean: false, includeDrafts: drafts,
environment: "development")` を呼ぶ。`drafts` は新設する `serve --drafts` フラグの値で、
既定は偽である。`hirundo build --drafts` と同じ綴り・同じ既定にすることで、
ローカルで見える内容と配信される内容が黙って食い違うことを防ぐ。

成功時は `onSuccess`（= `hub.broadcast("reload")`）。失敗時は `onFailure` で端末に
エラーを出すのみで、リロードは送らない。壊れたページに置き換わるより、直前の正しい
ページが残るほうが良い。`BuildResult.success == false` も失敗として扱う。

### `DevelopmentServer` の変更

```swift
public init(projectPath: String, port: Int, host: String, liveReload: Bool,
            fileManager: FileManager = .default, outputDirectory: String = "_site",
            hub: LiveReloadHub? = nil)
```

- `hotReloadManager` プロパティと、`deinit` から非同期クリーンアップを spawn する
  現行コードを削除する。ライフサイクルは `ServeCommand` が明示的に握る。
- `start()` を `start()` のまま残しつつ、内部で `resolveListenAddress` の結果を
  `listenAddressIPv4` / `listenAddressIPv6` に設定してから `server.start` を呼ぶ。
- `/livereload` のハンドラを `connected` / `disconnected` 付きに差し替え、Hub に登録・解除する。
- 静的配信で `Content-Type` が `text/html` のときだけ、`liveReload` が真なら
  `LiveReloadScriptInjector` を通す。バイト列を文字列として解釈できない場合は
  無加工で返す（注入の失敗が配信の失敗になってはいけない）。

`resolveFilePath` と MIME 判定は変更しない。

### バインドアドレスの解決

```swift
struct ListenAddress: Equatable {
    let address: String
    let forceIPv4: Bool
}
func resolveListenAddress(host: String) throws -> ListenAddress
```

| 入力 | 結果 |
|---|---|
| `localhost`、`127.0.0.1` | `127.0.0.1`、IPv4 |
| `0.0.0.0` | `0.0.0.0`、IPv4（起動時に「外部から到達可能」と警告） |
| `::1` | `::1`、IPv6 |
| `::` | `::`、IPv6（同上の警告） |
| その他の IPv4 / IPv6 リテラル | そのまま、対応する family |
| 上記以外（ホスト名など） | エラー。数値アドレスを渡すよう促す |

Swifter は AF_INET か AF_INET6 のどちらか一方にしか bind しない。`localhost` を IPv4
`127.0.0.1` に倒すのは、ブラウザが `http://localhost:<port>` を `::1` へ解決したときの
接続失敗を避けるためである。起動メッセージとブラウザ起動 URL も
`http://127.0.0.1:<port>` を用い、名前解決の曖昧さを残さない。

### `ServeCommand` の起動シーケンス

1. `config.yaml` をロードする。
2. 有効値を解決する。優先順位は **CLI 明示 > `config.server` > 既定**。
   - `--port` を `Int?` に変更し、`port ?? config.server.port` とする。
   - `--no-reload` は Flag なので「指定されたら必ず無効、未指定なら
     `config.server.liveReload` に従う」とする。
   - この解決は純関数 `resolveServeOptions(cli:config:)` に切り出し、単体テストする。
3. `resolveListenAddress(host:)` を解決する。失敗すればここで終了する。
4. 初回ビルドを実行する。失敗しても起動は続け、端末にエラーを出す。
   ビルドできない状態でもサーバが上がるほうが、原因を調べやすい。
5. `HotReloadManager` を起動する。
6. HTTP サーバを起動し、ブラウザを開く。
7. シグナルを待つ。

### 監視パス

`watchPaths` は `content`、`templates`、`static` の3つ（いずれも
`config.build` の値から組み立てる）。**出力ディレクトリは監視しない。**
自分のビルド出力を拾って無限ループになる。

`symlinkBoundary` は `.project(root: projectPath, excludingDirectoriesNamed:
[config.build.outputDirectory])` とし、ビルドが読むのと同じ範囲を監視する。

`HotReloadManager` の既定 `ignorePatterns` は `_site` をハードコードしているが、
`config.build.outputDirectory` は別名でありうる。設定された出力ディレクトリ名を
`ignorePatterns` に明示的に渡す。

`debounceInterval` は既定の 0.5 秒を用いる。

### シグナル処理

`withTaskCancellationHandler` による現行の Ctrl+C 処理を削除する。SIGINT では発火せず、
1秒ごとのポーリングも無駄である。

代わりに `signal(SIGINT, SIG_IGN)` / `signal(SIGTERM, SIG_IGN)` で既定動作を抑止し、
`DispatchSourceSignal` で捕捉する。待機は `withCheckedContinuation` で行い、
シグナル受信時に resume する。

停止順は **HTTP サーバ → 監視 → 進行中ビルドの完了待ち**。停止後は終了コード 0 で抜ける。
`SIG_IGN` はプロセス全体の状態なので、設定は `ServeCommand.run` の内部に閉じ、
`defer` で既定に戻す。

この repo は `EditorLauncher` と `TerminalForeground` で既に POSIX シグナルを
正面から扱っており、様式は揃う。

## テスト

| 対象 | 方法 |
|---|---|
| `LiveReloadScriptInjector` | 純関数のユニットテスト。`</body>` あり / 無し / 大文字 `</BODY>` / 複数出現 / 空文字列 |
| `LiveReloadHub` | fake `LiveReloadClient` で登録・解除・ブロードキャスト・二重解除 |
| `RebuildCoordinator` | fake builder。ビルド中の複数要求が2回に収束すること、失敗時に `onSuccess` が呼ばれないこと |
| `resolveListenAddress` | 上表の各入力と、ホスト名でエラーになること |
| `resolveServeOptions` | CLI 明示 / `config.server` のみ / どちらも無い の3通り × port・liveReload |
| `DevelopmentServer` | 既存の HTTP テストに追加。HTML には script が入り、CSS には入らないこと。`liveReload: false` では入らないこと |
| 統合 | 一時プロジェクトで `serve` を起動し、`content` の変更後に WebSocket へ `reload` が届くまで。既存 `HotReloadIntegrationTest` の隣に置く |

bind アドレスの実挙動（外部インターフェースから繋がらないこと）は CI で検証しにくいため、
純関数 `resolveListenAddress` のテストで代替する。

## ドキュメント

- `README.md` / `README.ja.md` の `hirundo serve` 節を書き直す。
  新設の `--drafts`、`--host` が実際に bind すること、`config.server` の優先順位を記載する。
  「`config.yaml` の `server.port` は `serve` からは参照されません」の記述は削除する。
- 「未実装の項目」から、ライブリロードに関して実装済みになった記述を削除する。
  WebSocket 認証が無い旨の記述は残す（本設計のスコープ外であり、事実として正しい）。
- `CLAUDE.md` の `hirundo serve` の説明を更新する。

## 未解決事項

無し。

# `hirundo serve` ライブリロード Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `hirundo serve` が初回ビルドを行い、`content` / `templates` / `static` の変更を監視して再ビルドし、`/livereload` WebSocket 経由で接続中のブラウザをリロードさせる。同時に `--host` を実際の bind アドレスにし、Ctrl+C を正しく捕捉し、`config.server` を尊重する。

**Architecture:** `DevelopmentServer` を神クラスにしないため、責務を 4 つに分割する。新規ユニットはすべて `Sources/HirundoCore/Serve/` に置き、`HirundoTests` からテストできるようにする。`ServeCommand`（CLI ターゲット）は配線とシグナル処理だけを持つ薄い層にする。

| ユニット | 置き場所 | 責務 |
|---|---|---|
| `LiveReloadScriptInjector`（新規 struct） | `Sources/HirundoCore/Serve/LiveReloadScriptInjector.swift` | HTML 文字列へのスクリプト挿入（純関数） |
| `LiveReloadHub`（新規 actor） | `Sources/HirundoCore/Serve/LiveReloadHub.swift` | 接続中クライアントの登録・解除・ブロードキャスト |
| `RebuildCoordinator`（新規 actor） | `Sources/HirundoCore/Serve/RebuildCoordinator.swift` | 変更バッチ→再ビルドの直列化→Hub への通知 |
| `resolveListenAddress`（新規 free function） | `Sources/HirundoCore/Serve/ListenAddress.swift` | `--host` → bind アドレス + address family |
| `resolveServeOptions`（新規 free function） | `Sources/HirundoCore/Serve/ServeOptions.swift` | CLI 明示 > `config.server` > 既定 の解決 |
| `DevelopmentServer`（既存・改修） | `Sources/HirundoCore/DevelopmentServer.swift` | HTTP 配信、bind、`/livereload` の受け口、HTML 注入 |
| `ServeCommand`（既存・改修） | `Sources/Hirundo/Commands/ServeCommand.swift` | 配線、初回ビルド、監視起動、シグナル処理、ブラウザ起動 |

**Tech Stack:** Swift 6 language mode / macOS 12+ / swift-argument-parser / Swifter 1.5 / Yams / XCTest

**Spec:** `docs/superpowers/specs/2026-09-05-hirundo-serve-live-reload-design.md`

## Global Constraints

- ビルドは `swift build`、テストは `swift test`。両方ともこのワークツリーのルートで実行する。
- **Swift 6 language mode が有効**（`swift-tools-version: 6.0`、`swiftLanguageMode` 未指定）。`Sendable` 制約は実際にコンパイルエラーになる。既存コードの様式にならい、必要なら `@unchecked Sendable` + 明示的なロック/actor を使う。
- テストターゲット `HirundoTests` は `HirundoCore` にのみ依存する。**`Sources/Hirundo`（CLI 実行可能ターゲット）のコードはテストできない。** テストしたいロジックを `ServeCommand` に置かないこと。
- 新規ソースは `Sources/HirundoCore/Serve/` に、新規テストは `Tests/HirundoTests/` に置く。`Package.swift` の変更は不要（ディレクトリ全体が自動で拾われる）。
- 既存のテストを 1 つも壊さないこと。特に `Tests/HirundoTests/DevelopmentServerTests.swift` の既存テストは `host: "localhost"` で起動して `http://127.0.0.1:<port>` に接続している。
- コード内のコメントと識別子は英語。ユーザー向け CLI 出力も英語（既存コマンドに合わせる）。ドキュメント（`README.ja.md`）のみ日本語。
- 送る WebSocket メッセージは `"reload"` のみ。プロトコルをこれ以上増やさない。
- 出力ディレクトリは**絶対に監視しない**（自分のビルド出力を拾って無限ループになる）。
- コミットメッセージは `<type>: <description>` 形式（`feat` / `fix` / `refactor` / `docs` / `test` / `chore`）。各タスクにつき 1 コミット以上。
- コミット末尾に以下を付ける:

  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_011BUhfABdSCM8akr5Tq11p9
  ```

### 依存関係（実装順）

Task 1〜5 は互いに独立。Task 6 は 1・2・4 に依存。Task 7 は 2・3・4・5・6 に依存。Task 8 は 6 に依存。Task 9 は 7 に依存。

---

### Task 1: `LiveReloadScriptInjector`

**Files:**
- Create: `Sources/HirundoCore/Serve/LiveReloadScriptInjector.swift`
- Test: `Tests/HirundoTests/LiveReloadScriptInjectorTests.swift`

**Interfaces:**
- Consumes: なし（純関数）
- Produces:

```swift
public struct LiveReloadScriptInjector: Sendable {
    public init(endpointPath: String = "/livereload")
    public func inject(into html: String) -> String
}
```

**Behavior:**

- `</body>` の直前に `<script>…</script>` を挿入する。
- `</body>` の検索は**大文字小文字を区別しない**（`</BODY>`、`</Body>` も一致）。
- 複数出現する場合は**最後の** `</body>` を使う。
- `</body>` が無い HTML には**末尾に追加**する。空文字列にはスクリプトだけが残る。
- 挿入するスクリプトは IIFE で包み、ページのグローバル空間を汚さない。
- スクリプトの中身の要件:
  - `new WebSocket((location.protocol === "https:" ? "wss://" : "ws://") + location.host + "<endpointPath>")`
  - `onmessage` で `event.data === "reload"` なら `location.reload()`
  - `onclose` で指数バックオフ再接続。**初回 500ms、上限 10000ms**（毎回 2 倍、上限で頭打ち）。再接続成功時にバックオフを 500ms へ戻す。
  - `onerror` は接続を閉じるだけにして `onclose` の再接続に任せる（二重再接続を作らない）。
- 生成する HTML 断片は `\n` で始めて `\n` で終える（既存の HTML の最終行と混ざらないように）。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/LiveReloadScriptInjectorTests.swift` を新規作成する。最低限これらのケースを網羅すること（テスト名は既存の `testX_whenY_doesZ` 様式に合わせる）:

1. `</body>` がある HTML → script が `</body>` の**前**に入る（`</body>` の後ろではない）。
2. `</body>` が無い HTML → script が末尾に付く。
3. `</BODY>`（大文字）→ その前に入る。
4. `</body>` が 2 回出現（`<pre>&lt;/body&gt;</pre>` ではなく実際に 2 回）→ **最後の** 1 つの前に入る。
5. 空文字列 → script のみが返る。
6. 注入されたスクリプトが `endpointPath` を含む。既定は `/livereload`、`init(endpointPath: "/lr")` なら `/lr`。
7. 注入されたスクリプトが `location.reload()` と `wss://` と `500`・`10000`（バックオフの下限・上限）を含む。
8. 二重注入しても構文的に壊れないこと（`inject(into:)` を 2 回通すと script が 2 個入る — これは想定内。**冪等性は要求しない**）。テストとしては「1 回通した結果に `</body>` が 1 つ残っていること」を確認する。

`swift test --filter LiveReloadScriptInjectorTests` が**コンパイルエラー**で落ちることを確認する（型がまだ無いので当然）。

- [ ] **Step 2: 実装してテストを通す**

`Sources/HirundoCore/Serve/LiveReloadScriptInjector.swift` を作成する。`range(of:options:[.caseInsensitive, .backwards])` で最後の `</body>` を探す。

`swift test --filter LiveReloadScriptInjectorTests` が全て通ることを確認する。

- [ ] **Step 3: コミット**

`feat: inject the live reload client into served HTML`

---

### Task 2: `LiveReloadHub`

**Files:**
- Create: `Sources/HirundoCore/Serve/LiveReloadHub.swift`
- Test: `Tests/HirundoTests/LiveReloadHubTests.swift`

**Interfaces:**
- Consumes: なし
- Produces:

```swift
public protocol LiveReloadClient: AnyObject, Sendable {
    var id: ObjectIdentifier { get }
    func send(_ text: String)
}

extension LiveReloadClient {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

public actor LiveReloadHub {
    public init()
    public func add(_ client: LiveReloadClient)
    public func remove(_ client: LiveReloadClient)
    public func remove(id: ObjectIdentifier)
    public func broadcast(_ message: String)
    public var clientCount: Int { get }
}
```

**Behavior:**

- 内部ストレージは `[ObjectIdentifier: LiveReloadClient]`。`id` をキーにする。
- `add` は同じ `id` を二度登録しても 1 件のまま（上書き）。
- `remove(_ client:)` は `remove(id: client.id)` に委譲する。
- 未登録の `id` を `remove` しても何も起きない（クラッシュしない、カウントも変わらない）。二重解除は無害でなければならない — Swifter の `disconnected` コールバックは実装によっては複数回来うる。
- `broadcast` は登録中の全クライアントに `send(_:)` を呼ぶ。クライアントが 0 件なら何もしない。
- `broadcast` 中に個々の `send` が失敗しても他のクライアントへの配信は続く（`send` は `throws` しない設計なので、実装は単に全件ループでよい）。

**なぜ actor か:** この repo に手書きロックをもう一つ増やさないため。`WebSocketSession` を直接抱えず `LiveReloadClient` 越しに扱うのは、テストで fake を差せるようにするため。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/LiveReloadHubTests.swift` を新規作成する。fake クライアントを用意する:

```swift
private final class FakeLiveReloadClient: LiveReloadClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _received: [String] = []
    var received: [String] { lock.lock(); defer { lock.unlock() }; return _received }
    func send(_ text: String) { lock.lock(); _received.append(text); lock.unlock() }
}
```

ケース:

1. `add` して `clientCount == 1`。
2. 同じクライアントを 2 回 `add` しても `clientCount == 1`。
3. 2 つ `add` して `broadcast("reload")` → 両方が `["reload"]` を受け取る。
4. `remove` 後に `broadcast` → そのクライアントは受け取らない、`clientCount == 0`。
5. 同じクライアントを 2 回 `remove` してもクラッシュせず `clientCount == 0` のまま。
6. 一度も `add` していないクライアントを `remove` しても既存の登録が消えない。
7. クライアント 0 件で `broadcast` しても例外にならない。

- [ ] **Step 2: 実装してテストを通す**

`swift test --filter LiveReloadHubTests` が全て通ることを確認する。

- [ ] **Step 3: コミット**

`feat: add a hub that broadcasts reloads to connected clients`

---

### Task 3: `RebuildCoordinator`

**Files:**
- Create: `Sources/HirundoCore/Serve/RebuildCoordinator.swift`
- Test: `Tests/HirundoTests/RebuildCoordinatorTests.swift`

**Interfaces:**
- Consumes: `BuildResult`（`Sources/HirundoCore/BuildTypes.swift` に既存）
- Produces:

```swift
/// Raised when the build ran to completion but reported failures.
public struct RebuildIncomplete: Error, LocalizedError {
    public let successCount: Int
    public let failCount: Int
    public let messages: [String]
    public var errorDescription: String? { get }
}

public actor RebuildCoordinator {
    public init(
        build: @escaping @Sendable () async throws -> BuildResult,
        onSuccess: @escaping @Sendable () async -> Void,
        onFailure: @escaping @Sendable (Error) async -> Void
    )
    public func requestRebuild()
    public func waitForQuiescence() async
}
```

**Behavior:**

- 状態は **in-flight と pending の 2 つだけ**。
  - `requestRebuild()` — ビルドが走っていなければ開始する。走っていれば `pending = true` を立てて即座に返る。
  - ビルド完了後、`pending` が立っていれば `pending` を降ろしてもう一度だけ走らせる。
  - 結果として、要求が 10 回来てもビルドは**最大 2 回**で収束する。
- `requestRebuild()` は `async` ではあるが（actor メソッドなので呼び出し側からは `await`）、**ビルドの完了を待たない**。内部で `Task { }` を起こしてループを回す。
- 成功時（`result.success == true`）は `onSuccess()` を呼ぶ。
- `result.success == false` は**失敗として扱う**。`RebuildIncomplete` を組み立てて `onFailure(_:)` に渡す。`messages` は `result.errors.prefix(10).map { "[\($0.stage)] \($0.file): \($0.error)" }`。
- `build()` が `throw` した場合はその Error をそのまま `onFailure(_:)` に渡す。
- **失敗時に `onSuccess` を呼んではならない。** 壊れたページに置き換わるより、直前の正しいページが残るほうが良い。
- `waitForQuiescence()` — ビルドが走っていなければ即座に返る。走っていれば、pending も含めて全て終わるまで待つ。停止シーケンスで使う。複数の待ち手を同時に受け付けられること（continuation の配列で保持する）。

**実装の骨子**（Swift 6 の actor 再入を利用する。`await` 中に `requestRebuild()` が入ってくるのが正しい動作）:

```swift
private var isBuilding = false
private var pending = false
private var waiters: [CheckedContinuation<Void, Never>] = []

public func requestRebuild() {
    guard !isBuilding else { pending = true; return }
    isBuilding = true
    Task { await self.runLoop() }
}

private func runLoop() async {
    repeat {
        pending = false
        await runOnce()
    } while pending
    isBuilding = false
    let resuming = waiters
    waiters = []
    for waiter in resuming { waiter.resume() }
}
```

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/RebuildCoordinatorTests.swift` を新規作成する。fake builder は「呼ばれた回数を数え、指定された時間だけ `Task.sleep` してから結果を返す」ものにする。`ThreadSafeBox`（`Tests/HirundoTests/ThreadSafeBox.swift` に既存）を再利用してよい。

ケース:

1. 1 回 `requestRebuild()` → `waitForQuiescence()` 後にビルド回数 1、`onSuccess` 1 回、`onFailure` 0 回。
2. **収束**: ビルドを 0.3 秒かかるようにし、`requestRebuild()` を 10 回連続で呼ぶ → `waitForQuiescence()` 後にビルド回数は **2**。
3. `BuildResult(success: false, …)` を返す builder → `onFailure` が 1 回呼ばれ、`onSuccess` は **0 回**。渡された Error は `RebuildIncomplete` で、`failCount` が伝わっている。
4. builder が `throw` する → `onFailure` に**その Error**が渡り、`onSuccess` は 0 回。
5. 失敗後にもう一度 `requestRebuild()` → 今度は成功して `onSuccess` が呼ばれる（失敗が coordinator を止めない）。
6. ビルドが走っていない状態で `waitForQuiescence()` を呼ぶと即座に返る（タイムアウトしない）。
7. `waitForQuiescence()` を 2 箇所から同時に待っても両方 resume する。

**テストの安定性:** 実時間の `sleep` に頼る箇所は 0.3 秒以上のマージンを取り、`XCTestExpectation` のタイムアウトは 10 秒にする。CI の遅さでフレークしないこと。

- [ ] **Step 2: 実装してテストを通す**

`swift test --filter RebuildCoordinatorTests` が全て通ることを確認する。

- [ ] **Step 3: コミット**

`feat: serialize rebuilds behind a coordinator`

---

### Task 4: `resolveListenAddress`

**Files:**
- Create: `Sources/HirundoCore/Serve/ListenAddress.swift`
- Test: `Tests/HirundoTests/ListenAddressTests.swift`

**Interfaces:**
- Consumes: `inet_pton`（`Foundation` 経由の POSIX）
- Produces:

```swift
public struct ListenAddress: Equatable, Sendable {
    /// Numeric address handed to Swifter's `listenAddressIPv4` / `listenAddressIPv6`.
    public let address: String
    /// Whether the socket must be created as AF_INET rather than AF_INET6.
    public let forceIPv4: Bool
    /// True when the address is the any-address, i.e. reachable from other machines.
    public let isWildcard: Bool
    /// Host as it should appear in a URL — IPv6 literals are bracketed.
    public var displayHost: String { get }
}

public enum ListenAddressError: Error, LocalizedError, Equatable {
    case notNumeric(String)
}

public func resolveListenAddress(host: String) throws -> ListenAddress
```

**Behavior:**

| 入力 | `address` | `forceIPv4` | `isWildcard` |
|---|---|---|---|
| `localhost`（大文字小文字問わず） | `127.0.0.1` | `true` | `false` |
| `127.0.0.1` | `127.0.0.1` | `true` | `false` |
| `0.0.0.0` | `0.0.0.0` | `true` | **`true`** |
| `::1` | `::1` | `false` | `false` |
| `::` | `::` | `false` | **`true`** |
| その他の IPv4 リテラル（例 `192.168.1.10`） | そのまま | `true` | `false` |
| その他の IPv6 リテラル（例 `fe80::1`） | そのまま | `false` | `false` |
| ホスト名（例 `example.com`、`my-host`） | — | — | `ListenAddressError.notNumeric` |
| 空文字列・空白のみ | — | — | `ListenAddressError.notNumeric` |

- 入力は `.trimmingCharacters(in: .whitespaces)` してから判定する。
- 判定順: (1) 小文字化して `localhost` なら IPv4 ループバックに倒す。(2) `inet_pton(AF_INET, …) == 1` なら IPv4。(3) `inet_pton(AF_INET6, …) == 1` なら IPv6。(4) それ以外は `notNumeric`。
- `address` は**入力をそのまま**返す（正規化しない）。`inet_pton` が受理した文字列は Swifter がもう一度 `inet_pton` に通すので、往復して同じ結果になる。
- `isWildcard` は `inet_pton` が書き込んだバイト列が全て 0 かどうかで判定する。文字列比較ではない（`0000:0000:…:0000` も wildcard として拾う）。
- `displayHost` は `forceIPv4 == false` かつ address が `:` を含むとき `[address]`、それ以外は `address`。
- `ListenAddressError.notNumeric` の `errorDescription` は「数値アドレスを渡せ」と促す文言にする。例:
  `"Server host must be a numeric IP address, not a host name: 'example.com'. Use 127.0.0.1 for local access or 0.0.0.0 to accept connections from other machines."`

**なぜ `localhost` を IPv4 に倒すか:** Swifter は AF_INET か AF_INET6 のどちらか一方にしか bind しない。ブラウザが `http://localhost:<port>` を `::1` に解決したときの接続失敗を避けるため、既定は `127.0.0.1` に倒す。起動メッセージとブラウザ起動 URL も `displayHost` を用い、名前解決の曖昧さを残さない。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/ListenAddressTests.swift` を新規作成し、上表の**全行**をテストする。加えて:

- `resolveListenAddress(host: "::1").displayHost == "[::1]"`
- `resolveListenAddress(host: "127.0.0.1").displayHost == "127.0.0.1"`
- `XCTAssertThrowsError` で `ListenAddressError.notNumeric` が投げられること（`as? ListenAddressError` で等値比較する）。
- `"  localhost  "` が `127.0.0.1` に解決されること。

- [ ] **Step 2: 実装してテストを通す**

`swift test --filter ListenAddressTests` が全て通ることを確認する。

- [ ] **Step 3: コミット**

`fix: make --host the address the development server actually binds`

---

### Task 5: `resolveServeOptions`

**Files:**
- Create: `Sources/HirundoCore/Serve/ServeOptions.swift`
- Test: `Tests/HirundoTests/ServeOptionsTests.swift`

**Interfaces:**
- Consumes: `Server`（`Sources/HirundoCore/Models/Server.swift` に既存、`port: Int` / `liveReload: Bool`）
- Produces:

```swift
/// What the user typed on the command line. `nil` means "not specified".
public struct ServeCommandLineOptions: Equatable, Sendable {
    public let port: Int?
    public let noReload: Bool
    public init(port: Int?, noReload: Bool)
}

/// The effective settings the server runs with.
public struct ServeOptions: Equatable, Sendable {
    public let port: Int
    public let liveReload: Bool
}

/// Resolves CLI over config over default.
public func resolveServeOptions(cli: ServeCommandLineOptions, config: Server) -> ServeOptions
```

**Behavior:**

- `port` = `cli.port ?? config.port`。`Server` の decoder が既に「省略時 8080」を与えるので、既定値の面倒は見なくてよい。
- `liveReload` = `cli.noReload ? false : config.liveReload`。
  `--no-reload` は Flag なので「指定されたら**必ず**無効、未指定なら `config.server.liveReload` に従う」。
- 純関数。副作用なし。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/ServeOptionsTests.swift` を新規作成する。ケース:

1. CLI に何も無く config が `Server(port: 3000, liveReload: false)` → `(3000, false)`。
2. CLI に何も無く config が既定の `Server()` → `(8080, true)`。
3. `cli.port = 9000`、config が `port: 3000` → `9000`（CLI が勝つ）。
4. `cli.noReload = true`、config が `liveReload: true` → `false`（CLI が勝つ）。
5. `cli.noReload = false`、config が `liveReload: false` → `false`（未指定なので config に従う。ここで `true` になってはいけない）。
6. `cli.port = 9000` かつ `cli.noReload = true`、config が `(3000, true)` → `(9000, false)`。

- [ ] **Step 2: 実装してテストを通す**

`swift test --filter ServeOptionsTests` が全て通ることを確認する。

- [ ] **Step 3: コミット**

`feat: let config.server supply serve's port and live reload`

---

### Task 6: `DevelopmentServer` の配線

**Files:**
- Modify: `Sources/HirundoCore/DevelopmentServer.swift`
- Modify: `Tests/HirundoTests/DevelopmentServerTests.swift`

**Interfaces:**
- Consumes: `LiveReloadHub`, `LiveReloadClient`（Task 2）、`LiveReloadScriptInjector`（Task 1）、`resolveListenAddress` / `ListenAddress`（Task 4）
- Produces:

```swift
public init(
    projectPath: String,
    port: Int,
    host: String,
    liveReload: Bool,
    fileManager: FileManager = .default,
    outputDirectory: String = "_site",
    hub: LiveReloadHub? = nil
)

/// The hub the `/livereload` endpoint registers its clients with.
public let liveReloadHub: LiveReloadHub
```

**変更点:**

1. **`hotReloadManager` プロパティを削除する。** `deinit` から非同期クリーンアップを `Task { }` で spawn する現行コードも削除する。ライフサイクルは `ServeCommand` が明示的に握る。`deinit` に残すのは `server.stop()` のみ。`stop()` から `hotReloadManager?.stop()` の行も消す。

2. **`liveReloadHub` を保持する。** `init` の `hub` 引数が `nil` なら `LiveReloadHub()` を新規に作る。`public let liveReloadHub: LiveReloadHub` として公開する（`ServeCommand` と統合テストが `broadcast` できるように）。

3. **`start()` で bind アドレスを設定する:**

```swift
public func start() async throws {
    let listen = try resolveListenAddress(host: host)
    if listen.forceIPv4 {
        server.listenAddressIPv4 = listen.address
    } else {
        server.listenAddressIPv6 = listen.address
    }
    try server.start(UInt16(port), forceIPv4: listen.forceIPv4, priority: .default)
    print("Development server started at http://\(listen.displayHost):\(port)")
}
```

   Swifter は `forceIPv4` が真なら `listenAddressIPv4` を、偽なら `listenAddressIPv6` を見る（`HttpServerIO.start` の実装がそうなっている）。両方を設定してはいけない。

4. **`/livereload` を `connected` / `disconnected` 付きに差し替える:**

```swift
server["/livereload"] = websocket(
    text: { session, text in
        if text == "ping" { session.writeText("pong") }
    },
    connected: { [hub = liveReloadHub] session in
        let client = WebSocketLiveReloadClient(session)
        Task { await hub.add(client) }
    },
    disconnected: { [hub = liveReloadHub] session in
        let id = ObjectIdentifier(session)
        Task { await hub.remove(id: id) }
    }
)
```

   薄いラッパーを同ファイル（または `Serve/LiveReloadHub.swift`）に置く:

```swift
/// Adapts Swifter's session to the hub's client protocol.
///
/// `id` is the *session's* identity, not the wrapper's: `connected` and `disconnected`
/// hand back the same session but this wrapper is built twice, so keying on the wrapper
/// would leave every disconnected client registered forever.
final class WebSocketLiveReloadClient: LiveReloadClient, @unchecked Sendable {
    private let session: WebSocketSession
    init(_ session: WebSocketSession) { self.session = session }
    var id: ObjectIdentifier { ObjectIdentifier(session) }
    func send(_ text: String) { session.writeText(text) }
}
```

   **`id` を session から取ること** — ここを間違えると解除が効かず、切れたクライアントが永久に溜まる。

5. **HTML への注入。** `handleStaticFileRequest` で、`liveReload` が真、かつ `contentType.hasPrefix("text/html")` のときだけ:

```swift
var body = data
if liveReload, contentType.hasPrefix("text/html"), let html = String(data: data, encoding: .utf8),
   let injected = injector.inject(into: html).data(using: .utf8) {
    body = injected
}
```

   **バイト列を UTF-8 文字列として解釈できない場合は無加工で返す。** 注入の失敗が配信の失敗になってはいけない。`injector` は `let injector = LiveReloadScriptInjector()` として `init` で持つ。

6. **`resolveFilePath` と `mimeType` は変更しない。**

- [ ] **Step 1: 失敗するテストを書く**

`Tests/HirundoTests/DevelopmentServerTests.swift` に追記する（既存テストは消さない）。ポート衝突を避けるため既存の `Int.random(in: 20000...30000)` の様式に合わせる。

ケース:

1. `liveReload: true` で HTML を GET → レスポンス本文に `/livereload` と `location.reload()` が含まれ、`</body>` の**前**にある。
2. `liveReload: false` で同じ HTML を GET → 本文に `/livereload` が含まれない（元の HTML と完全一致）。
3. `liveReload: true` で CSS を GET → 本文が `body {}` のまま（注入されない）。
4. `liveReload: true` で PNG（不正な UTF-8 バイト列でよい。例 `Data([0x89, 0x50, 0x4E, 0x47, 0xFF, 0xFE])`）を GET → バイト列が**そのまま**返る。
5. `host: "127.0.0.1"` で起動 → `http://127.0.0.1:<port>/` が 200。
6. `host: "::1"` で起動 → `http://[::1]:<port>/` が 200。（この環境で IPv6 ループバックが使えない可能性があるので、`try XCTSkipIf` でスキップ可能にしてよい。スキップ条件は「起動自体が失敗したら skip」。）
7. `host: "example.com"` で `start()` → `ListenAddressError.notNumeric` が投げられる。
8. 外部から渡した `hub` が `init(hub:)` で使われること: `let hub = LiveReloadHub()` を渡し、`server.liveReloadHub === hub` を確認する（actor 同士の `===` は可能）。

**サーバの後片付け:** 既存テストは `defer { Task { await server.stop() } }` を使っているが、新規テストでは `defer` の中で `Task` を起こすのではなく、テスト末尾で `await server.stop()` を明示的に呼ぶこと（ポートが解放される前に次のテストが走るのを防ぐ）。

- [ ] **Step 2: 実装してテストを通す**

`swift test --filter DevelopmentServerTests` が全て通ることを確認する。**既存の 12 テストも含めて全て通ること。**

- [ ] **Step 3: コミット**

`feat: wire the development server to the live reload hub`

---

### Task 7: `ServeCommand` の配線

**Files:**
- Modify: `Sources/Hirundo/Commands/ServeCommand.swift`

**Interfaces:**
- Consumes: `HirundoConfig`, `SiteGenerator`, `HotReloadManager`, `SymlinkBoundary`, `LiveReloadHub`, `RebuildCoordinator`, `DevelopmentServer`, `resolveServeOptions`, `resolveListenAddress`
- Produces: 動く `hirundo serve`

**CLI オプション（変更後）:**

```swift
@Option(name: .long, help: "Server port (defaults to server.port in config.yaml)")
var port: Int?

@Option(name: .long, help: "Numeric address to bind to. Use 0.0.0.0 to accept connections from other machines")
var host: String = "localhost"

@Flag(name: .long, help: "Disable live reload")
var noReload: Bool = false

@Flag(name: .long, help: "Don't open browser")
var noBrowser: Bool = false

@Flag(name: .long, help: "Include draft posts")
var drafts: Bool = false

@Flag(name: .long, help: "Show verbose error information")
var verbose: Bool = false
```

`--drafts` は `hirundo build --drafts` と**同じ綴り・同じ既定**（偽）にする。ローカルで見える内容と配信される内容が黙って食い違うのを防ぐため。

**起動シーケンス:**

1. `config.yaml` を CWD からロードする（`HirundoConfig.load(from:)`）。`serve` は `config.yaml` を決め打ちで読む — `--config` 相当のオプションは**今回追加しない**。
2. `let options = resolveServeOptions(cli: ServeCommandLineOptions(port: port, noReload: noReload), config: config.server)`
3. `let listen = try resolveListenAddress(host: host)`。失敗すればここで終了する（`handleError` → `ExitCode.failure`）。
   `listen.isWildcard` なら警告を出す:
   `⚠️  Listening on all interfaces. The live reload WebSocket has no authentication — do not use this on an untrusted network.`
4. `let generator = try SiteGenerator(projectPath: currentDirectory, config: config)` を作る。
5. **初回ビルドを実行する。** `try await generator.buildWithRecovery(clean: false, includeDrafts: drafts, environment: "development")`。
   **失敗しても起動は続ける。** 端末にエラーを出すだけ（stderr）。ビルドできない状態でもサーバが上がるほうが、原因を調べやすい。
6. `let hub = LiveReloadHub()` を作り、`DevelopmentServer(…, liveReload: options.liveReload, outputDirectory: config.build.outputDirectory, hub: hub)` に渡す。
7. `RebuildCoordinator` を組む:

```swift
let coordinator = RebuildCoordinator(
    build: { try await generator.buildWithRecovery(clean: false, includeDrafts: draftsValue, environment: "development") },
    onSuccess: { await hub.broadcast("reload") },
    onFailure: { error in /* print to stderr */ }
)
```

   `generator` は `SiteGenerator`（非 `Sendable` な `class`）なので、`@Sendable` クロージャに捕まえるとコンパイルエラーになる可能性がある。**その場合はクロージャの中で `SiteGenerator` を作り直す**（`try SiteGenerator(projectPath: path, config: config)`）。`HirundoConfig` は `Sendable` なので捕獲できる。どちらを選んだかは報告に書くこと。

8. **`HotReloadManager` を起動する:**

```swift
let watchPaths = [config.build.contentDirectory, config.build.templatesDirectory, config.build.staticDirectory]
    .map { URL(fileURLWithPath: currentDirectory).appendingPathComponent($0).path }
    .filter { isExistingDirectory($0) }
```

   - **出力ディレクトリは監視しない。** 自分のビルド出力を拾って無限ループになる。
   - 存在しないディレクトリは除外する（`HotReloadManager.start()` が `cannotOpenPath` で落ちる）。全部無ければ監視を起動せず、その旨を警告して続行する。
   - `ignorePatterns: [config.build.outputDirectory]` — 既定の `ignorePatterns` は `_site` をハードコードしているが、設定された出力ディレクトリは別名でありうる。
   - `symlinkBoundary: .project(root: currentDirectory, excludingDirectoriesNamed: [config.build.outputDirectory])` — ビルドが読むのと同じ範囲を監視する。
   - `debounceInterval` は既定の 0.5 秒（引数を省略する）。
   - コールバック: `{ _ in Task { await coordinator.requestRebuild() } }`
   - `options.liveReload` が偽なら監視自体を起動しない。

9. HTTP サーバを起動する（`try await server.start()`）。起動メッセージは `listen.displayHost` を使う:
   `✅ Development server is running at http://\(listen.displayHost):\(options.port)`
10. `--no-browser` でなければブラウザを開く。URL も `http://\(listen.displayHost):\(options.port)`。
11. シグナルを待つ。

**シグナル処理（現行の `withTaskCancellationHandler` を削除する）:**

`withTaskCancellationHandler` は SIGINT では発火しない。`stop()` は呼ばれず、サーバはプロセスごと即死する。1 秒ごとのポーリングも無駄である。代わりに:

```swift
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
defer {
    signal(SIGINT, SIG_DFL)
    signal(SIGTERM, SIG_DFL)
}

let queue = DispatchQueue(label: "com.hirundo.serve.signal")
let sources = [SIGINT, SIGTERM].map { DispatchSource.makeSignalSource(signal: $0, queue: queue) }
await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    let gate = ResumeOnce(continuation)          // NSLock-guarded, resumes at most once
    for source in sources {
        source.setEventHandler { gate.fire() }
        source.resume()
    }
}
for source in sources { source.cancel() }
```

- `SIG_IGN` はプロセス全体の状態なので、設定は `run()` の内部に閉じ、`defer` で既定に戻す。
- `ResumeOnce` は `NSLock` + `Bool` で二度 resume しないことを保証する小さな `final class`（`@unchecked Sendable`）。`CheckedContinuation` を二度 resume するとクラッシュする。同ファイル内の `private` 型でよい。
- `ServeCommand` は `struct` で `run()` は `mutating`。**クロージャに `self` を捕獲してはいけない。** 必要な値は全てローカル定数に写してから使う。

**停止順は HTTP サーバ → 監視 → 進行中ビルドの完了待ち:**

```swift
print("⏹️  Stopping server…")
await server.stop()
await hotReloadManager?.stop()
await coordinator.waitForQuiescence()
print("🛑 Server stopped")
```

停止後は**終了コード 0** で抜ける（`ExitCode.failure` を投げない）。

**エラー処理:** 既存の `do { … } catch { handleError(error, context: "Serve", verbose: verbose); throw ExitCode.failure }` の構造は残す。catch 節でもサーバと監視を停止すること。

- [ ] **Step 1: 実装する**

このタスクにはユニットテストが無い（`Sources/Hirundo` はテストターゲットから見えない）。**ロジックを新たにここへ足さないこと** — 判断が要るものは Task 4・5 の純関数に既に切り出されている。

- [ ] **Step 2: 手で検証する**

一時ディレクトリで実際に動かして確認する:

```bash
TMP=$(mktemp -d)
swift run hirundo init "$TMP/site" --blog
cd "$TMP/site"
swift run --package-path <このワークツリーのパス> hirundo serve --port 18080 --no-browser
```

確認すること（別の端末から `curl` する）:

- `_site` が無い状態から起動して `curl -s http://127.0.0.1:18080/` が 200 で HTML を返す（初回ビルドが走っている）。
- 返る HTML に `/livereload` を含む `<script>` が入っている。
- `content/index.md` を書き換えると端末に再ビルドのログが出て、`curl` が新しい内容を返す。
- Ctrl+C で `🛑 Server stopped` が出て、プロセスが終了コード 0 で終わる。
- `hirundo serve --host example.com` がエラーメッセージを出して失敗する。
- `hirundo serve --host 0.0.0.0 --no-browser` で警告が出る。

`swift build` と `swift test` が両方通ること。

**この検証の記録（実行したコマンドと出力）を report に貼ること。** 貼れない場合は、何が確認できて何が確認できなかったかを明記する。

- [ ] **Step 3: コミット**

`feat: make hirundo serve build, watch, and reload`

---

### Task 8: ライブリロードの統合テスト

**Files:**
- Create: `Tests/HirundoTests/ServeLiveReloadIntegrationTests.swift`

**Interfaces:**
- Consumes: `DevelopmentServer`, `LiveReloadHub`, `RebuildCoordinator`, `HotReloadManager`

`ServeCommand` はテストできないので、統合テストは **`DevelopmentServer` + `LiveReloadHub` + `RebuildCoordinator` + `HotReloadManager` の連結**を検証する。`SiteGenerator` は使わず fake builder を使う（本物のビルドはこのテストの対象ではないし、遅い）。

**ケース:**

1. **WebSocket が繋がってブロードキャストが届く**
   - `_site/index.html` を持つ一時ディレクトリで `DevelopmentServer(liveReload: true, hub: hub)` を起動する。
   - `URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/livereload")!)` で接続し `resume()` する。
   - `receive()` を先に仕掛けてから `await hub.broadcast("reload")` を呼ぶ。
   - 受信した文字列が `"reload"` であること。タイムアウト 10 秒。
   - 接続確立を待つため、`broadcast` の前に「`hub.clientCount == 1` になるまで最大 5 秒ポーリングする」ヘルパーを使う。固定 `sleep` に頼らない。

2. **切断でクライアントが解除される**
   - 接続 → `clientCount == 1` を待つ → `webSocketTask.cancel(with: .goingAway, reason: nil)` → `clientCount == 0` になるまで最大 5 秒ポーリング。
   - これが落ちるなら Task 6 の `WebSocketLiveReloadClient.id` が session ベースになっていない。

3. **ファイル変更 → 再ビルド → reload の連鎖**
   - `content/` を持つ一時ディレクトリを作る。
   - fake builder（`BuildResult(success: true, …)` を返す）で `RebuildCoordinator` を組み、`onSuccess` を `hub.broadcast("reload")` にする。
   - `HotReloadManager(watchPaths: [content], debounceInterval: 0.3, callback: { _ in Task { await coordinator.requestRebuild() } })` を起動する。
   - WebSocket を接続してから `content/new.md` を書く。
   - WebSocket に `"reload"` が届くこと。タイムアウト 20 秒（FSEvents の遅延 + debounce + ビルドを見込む）。
   - `tearDown` で manager と server を必ず停止する。

**既知のリスク:** `URLSessionWebSocketTask` と Swifter 1.5 のハンドシェイクが噛み合わない可能性がある（Swifter は `sec-websocket-key` を見て accept を返すが、`Sec-WebSocket-Version` や sub-protocol の扱いが緩い）。**まず `URLSessionWebSocketTask` で試すこと。** 3 回試して繋がらなければ、`URLSessionWebSocketTask` を諦めて生の `Socket` でハンドシェイクを書くのではなく、**ケース 1・2 を「`LiveReloadHub` に `WebSocketLiveReloadClient` を直接 add/remove する」レベルに落とし、ケース 3 は「WebSocket ではなく fake クライアントが `"reload"` を受け取ること」で検証する。** その判断と理由を report に明記すること。ここで時間を溶かさないこと。

`HotReloadIntegrationTest.swift` の様式（`tempDir`、`tearDown` での `await manager?.stop()`）に合わせる。

- [ ] **Step 1: テストを書いて通す**

`swift test --filter ServeLiveReloadIntegrationTests` が通ること。**フレークしないこと** — 3 回連続で実行して 3 回とも通ることを確認する。

- [ ] **Step 2: 全体テスト**

`swift test` が全て通ること。

- [ ] **Step 3: コミット**

`test: cover the path from a file change to a browser reload`

---

### Task 9: ドキュメント更新

**Files:**
- Modify: `README.md`
- Modify: `README.ja.md`
- Modify: `CLAUDE.md`

**変更点:**

1. **`README.md` の `### hirundo serve` 節（156 行目付近）を書き直す。**
   - オプション一覧に `--drafts`（`Include draft posts`）を追加し、`--port` の既定を「`config.yaml` の `server.port`」に改める。
   - `--host` が実際に bind すること、既定 `localhost` はループバックのみで、外部に出すには `--host 0.0.0.0` を明示すること、その場合ライブリロード WebSocket に認証が無いことを書く。**ホスト名は渡せない（数値アドレスのみ）**ことも書く。
   - 「`--port` and `--host` are command-line only — `server.port` in `config.yaml` is not consulted by `serve`.」（178〜179 行目）を**削除**し、**CLI 明示 > `config.server` > 既定**の優先順位の説明に差し替える。
   - `serve` が起動時に必ずビルドし、`content` / `templates` / `static` を監視して再ビルドし、`/livereload` 経由でブラウザをリロードさせることを書く。
   - 62〜70 行目付近の「`hirundo serve` serves whatever is already in the output directory. Run `hirundo build` at least once before the first `serve`, otherwise every request returns 404」という注記を**削除**する（もう真ではない）。
   - 384 行目付近の「`server` supports only `port` and `liveReload`. See Not Yet Implemented.」は事実として正しいので**残す**。

2. **`README.md` の「Not Yet Implemented」節（502 行目付近）から、ライブリロードについて実装済みになった記述を削除する。**
   - 530 行目付近の「**Development server**: WebSocket session cleanup and file-watcher teardown on shutdown.」は実装されたので削除する。
   - 512〜514 行目付近の「**WebSocket authentication for live reload.**」は**残す**（本設計のスコープ外であり、事実として正しい）。
   - 505〜506 行目の CORS の記述も残す。

3. **`README.ja.md` に同じ変更を日本語で施す。** 行番号は 156・178〜179・63〜70・502 以降が対応する。日本語の正書法を厳守すること。

4. **`CLAUDE.md` の「### 開発サーバーの起動」節を更新する。**
   現在は以下の 4 行:

   ```
   - ポート: 8080（デフォルト）
   - ライブリロード: 有効
   - URL: `http://localhost:8080`
   ```

   これを、`--port` / `--host` / `--drafts` / `--no-reload` / `--no-browser` の説明、`config.server` との優先順位、初回ビルドと監視対象（`content` / `templates` / `static`、出力ディレクトリは監視しない）に書き換える。
   併せて、末尾の「今後の拡張予定」にある「開発サーバーのCORS設定（`server.cors` ブロック）— 現在 `server` が解釈するのは `port` と `liveReload` のみです。」は**残す**（正しい）。

**制約:** ドキュメントは実装に合わせる。実装していないことを書かない。`README.md` と `README.ja.md` の内容は互いに対応していること。

- [ ] **Step 1: 3 ファイルを更新する**
- [ ] **Step 2: 書いた内容が実装と一致することを確認する**

`Sources/Hirundo/Commands/ServeCommand.swift` を読み、オプション名・既定値・ヘルプ文が README と一致していることを確認する。`swift run hirundo serve --help` の出力と突き合わせること。

- [ ] **Step 3: コミット**

`docs: document what hirundo serve now does`

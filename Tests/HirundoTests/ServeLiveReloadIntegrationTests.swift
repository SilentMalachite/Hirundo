import XCTest
@testable import HirundoCore

/// Polls `condition` until it returns `true` or `timeout` elapses, checking every
/// `pollInterval`. These integration tests are timing-dependent by nature (a WebSocket
/// handshake, FSEvents delivery, a debounce interval), so a fixed `sleep` before asserting would
/// either be flaky on a slow machine or slow on a fast one. Polling lets the test proceed the
/// moment the condition is true and only fail when it genuinely never becomes true.
/// Opens a live-reload socket the way the injected client does: from the page this very server
/// served. ``WebSocketOriginGuard`` refuses a handshake whose `Origin` names anything else, and a
/// `URLSessionWebSocketTask` sends no `Origin` of its own, so these tests have to supply it.
private func liveReloadTask(port: Int) -> URLSessionWebSocketTask {
    var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)/livereload")!)
    request.setValue("http://127.0.0.1:\(port)", forHTTPHeaderField: "Origin")
    return URLSession.shared.webSocketTask(with: request)
}

private func waitUntil(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.05,
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
    }
    return await condition()
}

/// Covers the chain that no unit test exercises: a real WebSocket client connects to
/// `DevelopmentServer`'s `/livereload` endpoint, registers with `LiveReloadHub`, and receives a
/// `"reload"` broadcast — first directly (cases 1-2), then as the tail end of a file change
/// picked up by `HotReloadManager` and turned into a rebuild by `RebuildCoordinator` (case 3).
/// `ServeCommand` itself cannot be under test here: `Sources/Hirundo` is an executable target the
/// test target cannot see. `SiteGenerator` is replaced with a fake build closure throughout —
/// a real build is not what this test is about, and it is slow.
final class ServeLiveReloadIntegrationTests: XCTestCase {

    var tempDir: URL!
    var server: DevelopmentServer!
    var manager: HotReloadManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("serve-livereload-\(UUID())")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        await manager?.stop()
        await server?.stop()
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    /// Starts a `DevelopmentServer` with live reload enabled, backed by `hub`, serving from a
    /// minimal `_site/index.html` under `tempDir`. Assigns the result to `self.server` so
    /// `tearDown` stops it.
    private func startServer(hub: LiveReloadHub, port: Int) async throws {
        let siteDir = tempDir.appendingPathComponent("_site")
        try FileManager.default.createDirectory(at: siteDir, withIntermediateDirectories: true)
        try "<html></html>".write(
            to: siteDir.appendingPathComponent("index.html"),
            atomically: true,
            encoding: .utf8
        )

        server = DevelopmentServer(
            projectPath: tempDir.path,
            port: port,
            host: "localhost",
            liveReload: true,
            hub: hub
        )
        try await server.start()
    }

    // MARK: - Case 1: WebSocket connects and receives a broadcast

    func testWebSocketClient_whenHubBroadcasts_receivesReloadMessage() async throws {
        let hub = LiveReloadHub()
        let port = Int.random(in: 20000...30000)
        try await startServer(hub: hub, port: port)

        let task = liveReloadTask(port: port)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        let connected = await waitUntil(timeout: 5.0) { await hub.clientCount == 1 }
        XCTAssertTrue(connected, "expected the WebSocket client to register with the hub within 5s")

        let received = ThreadSafeBox<String?>(nil)
        let messageReceived = self.expectation(description: "received a message over the socket")
        task.receive { result in
            if case .success(.string(let text)) = result {
                received.set(text)
            }
            messageReceived.fulfill()
        }

        await hub.broadcast("reload")

        await fulfillment(of: [messageReceived], timeout: 10.0)
        XCTAssertEqual(received.get(), "reload")
    }

    // MARK: - Case 2: disconnecting removes the client from the hub

    func testWebSocketClient_whenDisconnected_isRemovedFromHub() async throws {
        let hub = LiveReloadHub()
        let port = Int.random(in: 20000...30000)
        try await startServer(hub: hub, port: port)

        let task = liveReloadTask(port: port)
        task.resume()

        let connected = await waitUntil(timeout: 5.0) { await hub.clientCount == 1 }
        XCTAssertTrue(connected, "expected the WebSocket client to register with the hub within 5s")

        task.cancel(with: .goingAway, reason: nil)

        // If `WebSocketLiveReloadClient.id` were keyed off the wrapper instance rather than the
        // underlying session, this would never reach zero: `connected` and `disconnected` each
        // build their own wrapper around the same session, so `add`'s key and `disconnected`'s
        // `remove(id:)` key would never agree.
        let removed = await waitUntil(timeout: 5.0) { await hub.clientCount == 0 }
        XCTAssertTrue(removed, "expected the disconnected client to be removed from the hub within 5s")
    }

    // MARK: - Case 3: a file change triggers a rebuild that broadcasts reload

    func testFileChange_whenContentFileWritten_triggersRebuildThatBroadcastsReload() async throws {
        let contentDir = tempDir.appendingPathComponent("content")
        try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)

        let hub = LiveReloadHub()
        let port = Int.random(in: 20000...30000)
        try await startServer(hub: hub, port: port)

        let coordinator = RebuildCoordinator(
            build: { BuildResult(success: true, errors: [], successCount: 1, failCount: 0) },
            onSuccess: { await hub.broadcast("reload") },
            onFailure: { _ in }
        )

        manager = HotReloadManager(
            watchPaths: [contentDir.path],
            debounceInterval: 0.3
        ) { _ in
            Task { await coordinator.requestRebuild() }
        }
        try await manager.start()

        let task = liveReloadTask(port: port)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        let connected = await waitUntil(timeout: 5.0) { await hub.clientCount == 1 }
        XCTAssertTrue(connected, "expected the WebSocket client to register with the hub within 5s")

        let received = ThreadSafeBox<String?>(nil)
        let messageReceived = self.expectation(description: "received reload after a file change")
        task.receive { result in
            if case .success(.string(let text)) = result {
                received.set(text)
            }
            messageReceived.fulfill()
        }

        // Deliberately not asserting on this file's path or on any event/rebuild count:
        // `String.write(atomically: true)` produces a temporary `.sb-<hash>` sibling that
        // FSEvents reports instead of (or in addition to) the real path, and one logical write
        // can surface as more than one event. Only the end of the chain — a "reload" eventually
        // arriving — is stable enough to assert on.
        try "# New post".write(
            to: contentDir.appendingPathComponent("new.md"),
            atomically: true,
            encoding: .utf8
        )

        // Generous timeout: FSEvents latency + 0.3s debounce + the (fake, instant) build.
        await fulfillment(of: [messageReceived], timeout: 20.0)
        XCTAssertEqual(received.get(), "reload")
    }
}

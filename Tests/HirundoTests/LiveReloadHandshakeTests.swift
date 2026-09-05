import XCTest
@testable import HirundoCore

/// Waits for an actor-isolated condition to hold, or gives up.
///
/// Registration with the hub happens in a detached `Task` spawned from Swifter's `connected`
/// callback, so it is not observable the instant the socket opens.
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

/// Covers the `/livereload` route rather than the decision table behind it — that is
/// ``WebSocketOriginGuardTests``' job. What matters here is the wiring: that the check runs
/// *before* Swifter upgrades the connection, and that a refused handshake never becomes a client
/// the hub will broadcast to.
///
/// The refusal cases are driven with an ordinary GET instead of a real handshake. Foundation
/// reserves `Connection` and `Host`, so a `URLRequest` cannot forge a full upgrade — but it can
/// set `Origin`, and the status code alone distinguishes the two outcomes precisely: 403 is ours,
/// while 400 is Swifter complaining about the `Upgrade` header it never got, which it can only do
/// once the guard has let the request past.
final class LiveReloadHandshakeTests: XCTestCase {

    private var tempDir: URL!
    private var server: DevelopmentServer?

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("livereload-handshake-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        await server?.stop()
        server = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    /// Starts a server and returns the port it is listening on together with its hub.
    private func startServer(liveReload: Bool = true) async throws -> (port: Int, hub: LiveReloadHub) {
        let port = Int.random(in: 20000...30000)
        let hub = LiveReloadHub()
        let developmentServer = DevelopmentServer(
            projectPath: tempDir.path,
            port: port,
            host: "127.0.0.1",
            liveReload: liveReload,
            hub: hub
        )
        server = developmentServer
        try await developmentServer.start()
        return (port, hub)
    }

    /// `addressedAs` becomes the URL's host, and therefore the `Host` header — the header a
    /// `URLRequest` may not set directly.
    private func status(port: Int, origin: String?, addressedAs: String = "127.0.0.1") async throws -> Int? {
        var request = URLRequest(url: URL(string: "http://\(addressedAs):\(port)/livereload")!)
        if let origin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode
    }

    // MARK: - Refused before the upgrade

    func testLivereload_whenOriginIsAnotherSite_isRefusedWithForbidden() async throws {
        let (port, hub) = try await startServer()

        let code = try await status(port: port, origin: "http://evil.example")

        XCTAssertEqual(code, 403, "a cross-site handshake must not reach Swifter's upgrade")
        let count = await hub.clientCount
        XCTAssertEqual(count, 0, "a refused handshake must never register with the hub")
    }

    func testLivereload_whenOriginIsMissing_isRefusedWithForbidden() async throws {
        let (port, _) = try await startServer()

        let code = try await status(port: port, origin: nil)

        XCTAssertEqual(code, 403, "a handshake with no Origin did not come from a browser")
    }

    func testLivereload_whenOriginPortDiffers_isRefusedWithForbidden() async throws {
        let (port, _) = try await startServer()

        let code = try await status(port: port, origin: "http://127.0.0.1:\(port + 1)")

        XCTAssertEqual(code, 403, "the port is part of the origin, so a different one is another site")
    }

    // MARK: - Allowed through to the upgrade

    /// 400 rather than 403: the guard allowed the request, and Swifter then refused it for the
    /// reason it should — this GET is not an upgrade request. That distinction is the whole point
    /// of asserting on the status code.
    func testLivereload_whenOriginMatchesHost_reachesSwiftersUpgradeCheck() async throws {
        let (port, _) = try await startServer()

        let code = try await status(port: port, origin: "http://127.0.0.1:\(port)")

        XCTAssertEqual(code, 400, "a same-origin request must reach the upgrade check")
    }

    /// `localhost` is the guard's one exception to requiring an address, and the one a developer
    /// is most likely to type. Reaching the upgrade check proves the exception is wired up: the
    /// request really did arrive with `Host: localhost:<port>`, which a `URLRequest` cannot set
    /// itself.
    func testLivereload_whenAddressedAsLocalhost_reachesSwiftersUpgradeCheck() async throws {
        let (port, _) = try await startServer()

        let code = try await status(
            port: port,
            origin: "http://localhost:\(port)",
            addressedAs: "localhost"
        )

        XCTAssertEqual(code, 400, "localhost is the one name the guard accepts")
    }

    // MARK: - Not mounted at all

    /// With live reload off there is no socket to screen: the route is never registered, so the
    /// path falls through to static file serving and finds nothing. Worth pinning because the
    /// guard would be pointless if some other handler could still upgrade this path.
    func testLivereload_whenLiveReloadIsOff_isNotServedAtAll() async throws {
        let (port, hub) = try await startServer(liveReload: false)

        let code = try await status(port: port, origin: "http://127.0.0.1:\(port)")

        XCTAssertEqual(code, 404, "with live reload off, /livereload is just a missing file")
        let count = await hub.clientCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Over a real socket

    /// The end-to-end path the injected client actually takes.
    func testLivereload_whenBrowserConnectsSameOrigin_registersWithTheHub() async throws {
        let (port, hub) = try await startServer()

        var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)/livereload")!)
        request.setValue("http://127.0.0.1:\(port)", forHTTPHeaderField: "Origin")
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        let registered = await waitUntil(timeout: 10) { await hub.clientCount == 1 }
        XCTAssertTrue(registered, "a same-origin socket should be broadcast to")
    }

    /// The refusal is observed, not waited out. Asserting only that the hub stays empty for a
    /// while would pass just as well against a socket that was accepted but slow — and slowest of
    /// all on the loaded CI machine where a regression most needs catching. Waiting for the
    /// socket to fail is a positive result, so the assertion can only pass for the right reason.
    func testLivereload_whenBrowserConnectsCrossOrigin_isClosedAndNeverRegisters() async throws {
        let (port, hub) = try await startServer()

        var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)/livereload")!)
        request.setValue("http://evil.example", forHTTPHeaderField: "Origin")
        let task = URLSession.shared.webSocketTask(with: request)

        let refused = expectation(description: "the socket is closed instead of accepted")
        task.receive { result in
            if case .failure = result { refused.fulfill() }
        }
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        await fulfillment(of: [refused], timeout: 10)
        let count = await hub.clientCount
        XCTAssertEqual(count, 0, "a cross-site socket must never be broadcast to")
    }

    // MARK: - Reporting

    /// A refused client does not stop trying — the injected script reconnects for as long as its
    /// tab is open — so the terminal must not fill with the same line for the rest of the day.
    func testRefusalLog_reportsAReasonOnceUntilItChanges() {
        let log = RefusalLog()

        XCTAssertTrue(log.shouldReport("Origin mismatch"), "the first refusal is news")
        XCTAssertFalse(log.shouldReport("Origin mismatch"), "the same client retrying is not")
        XCTAssertFalse(log.shouldReport("Origin mismatch"))
        XCTAssertTrue(log.shouldReport("no Origin header"), "a different problem is news again")
        XCTAssertTrue(log.shouldReport("Origin mismatch"), "and so is the first one returning")
    }
}

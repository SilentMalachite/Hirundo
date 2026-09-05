import XCTest
@testable import HirundoCore

private final class FakeLiveReloadClient: LiveReloadClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _received: [String] = []
    var received: [String] { lock.lock(); defer { lock.unlock() }; return _received }
    func send(_ text: String) { lock.lock(); _received.append(text); lock.unlock() }
}

final class LiveReloadHubTests: XCTestCase {

    func testAdd_whenClientAdded_increasesClientCount() async {
        let hub = LiveReloadHub()
        let client = FakeLiveReloadClient()

        await hub.add(client)

        let count = await hub.clientCount
        XCTAssertEqual(count, 1)
    }

    func testAdd_whenSameClientAddedTwice_countStaysOne() async {
        let hub = LiveReloadHub()
        let client = FakeLiveReloadClient()

        await hub.add(client)
        await hub.add(client)

        let count = await hub.clientCount
        XCTAssertEqual(count, 1)
    }

    func testBroadcast_whenTwoClientsAdded_bothReceiveTheMessage() async {
        let hub = LiveReloadHub()
        let clientA = FakeLiveReloadClient()
        let clientB = FakeLiveReloadClient()

        await hub.add(clientA)
        await hub.add(clientB)
        await hub.broadcast("reload")

        XCTAssertEqual(clientA.received, ["reload"])
        XCTAssertEqual(clientB.received, ["reload"])
    }

    func testBroadcast_afterClientRemoved_removedClientDoesNotReceiveMessage() async {
        let hub = LiveReloadHub()
        let client = FakeLiveReloadClient()
        await hub.add(client)

        await hub.remove(client)
        await hub.broadcast("reload")

        XCTAssertEqual(client.received, [])
        let count = await hub.clientCount
        XCTAssertEqual(count, 0)
    }

    func testRemove_whenCalledTwiceForSameClient_doesNotCrashAndCountStaysZero() async {
        let hub = LiveReloadHub()
        let client = FakeLiveReloadClient()
        await hub.add(client)

        await hub.remove(client)
        await hub.remove(client)

        let count = await hub.clientCount
        XCTAssertEqual(count, 0)
    }

    func testRemove_whenClientWasNeverAdded_doesNotAffectExistingRegistrations() async {
        let hub = LiveReloadHub()
        let registered = FakeLiveReloadClient()
        let neverAdded = FakeLiveReloadClient()
        await hub.add(registered)

        await hub.remove(neverAdded)

        let count = await hub.clientCount
        XCTAssertEqual(count, 1)
    }

    func testBroadcast_whenNoClientsRegistered_doesNotThrowOrCrash() async {
        let hub = LiveReloadHub()

        await hub.broadcast("reload")

        let count = await hub.clientCount
        XCTAssertEqual(count, 0)
    }
}

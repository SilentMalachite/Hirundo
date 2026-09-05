import Foundation

/// Something that can receive a live-reload notification.
///
/// The hub talks to clients through this protocol rather than holding a Swifter
/// `WebSocketSession` directly, so that the hub itself never has to import Swifter. That keeps
/// this file testable with a plain fake and keeps the HTTP dependency confined to the adapter
/// that wraps a real `WebSocketSession` for the development server.
public protocol LiveReloadClient: AnyObject, Sendable {
    var id: ObjectIdentifier { get }
    func send(_ text: String)
}

extension LiveReloadClient {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

/// Tracks the browser tabs currently connected for live reload and fans a reload notification
/// out to all of them.
///
/// An actor rather than a hand-rolled lock: this repo already has one manual `NSLock` design in
/// `HotReloadManager`, and there is no reason to add a second locking strategy for what is
/// fundamentally the same problem (mutable shared state touched from concurrent WebSocket
/// callbacks). Swifter's `disconnected` callback is not guaranteed to fire exactly once per
/// connection, so `remove` has to tolerate being called more than once for the same client
/// without treating that as an error.
public actor LiveReloadHub {
    private var clients: [ObjectIdentifier: LiveReloadClient] = [:]

    public init() {}

    public var clientCount: Int {
        clients.count
    }

    public func add(_ client: LiveReloadClient) {
        clients[client.id] = client
    }

    public func remove(_ client: LiveReloadClient) {
        remove(id: client.id)
    }

    public func remove(id: ObjectIdentifier) {
        clients.removeValue(forKey: id)
    }

    public func broadcast(_ message: String) {
        for client in clients.values {
            client.send(message)
        }
    }
}

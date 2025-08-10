import Foundation

// Thread-safe wrapper for values that need to be mutated in concurrent code
final class ThreadSafeBox<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    
    init(_ value: T) {
        self.value = value
    }
    
    func get() -> T {
        lock.withLock { value }
    }
    
    func set(_ newValue: T) {
        lock.withLock { value = newValue }
    }
    
    func modify(_ modifier: (inout T) -> Void) {
        lock.withLock { modifier(&value) }
    }
}
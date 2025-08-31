import Foundation
@preconcurrency import Stencil

/// Manages template caching for performance (thread-safe, no GCD captures)
public final class TemplateCache {
    private var cache: [String: (template: Template, addedAt: Date)] = [:]
    private let lock = NSLock()

    // Cache management properties
    private let maxCacheSize = 100 // Maximum number of templates to cache
    private let cacheExpirationSeconds: TimeInterval = 3600.0 // 1 hour
    private let cleanupInterval: TimeInterval = 300.0 // 5 minutes
    private var lastCleanup: Date = Date()

    public init() {}

    /// Retrieves a template from cache
    public func getTemplate(for name: String) -> Template? {
        lock.lock()
        defer { lock.unlock() }

        performCleanupIfNeeded_locked()

        guard let entry = cache[name] else { return nil }
        // Expiration check
        if Date().timeIntervalSince(entry.addedAt) > cacheExpirationSeconds {
            cache.removeValue(forKey: name)
            return nil
        }
        return entry.template
    }

    /// Stores a template in cache
    public func setTemplate(_ template: Template, for name: String) {
        lock.lock()
        defer { lock.unlock() }

        // Size bound: evict oldest
        if cache.count >= maxCacheSize {
            let sorted = cache.sorted { $0.value.addedAt < $1.value.addedAt }
            let removeCount = cache.count - maxCacheSize + 1
            for (key, _) in sorted.prefix(removeCount) {
                cache.removeValue(forKey: key)
            }
        }
        cache[name] = (template: template, addedAt: Date())

        performCleanupIfNeeded_locked()
    }

    /// Clears all cached templates
    public func clearCache() {
        lock.lock()
        cache.removeAll()
        lastCleanup = Date()
        lock.unlock()
    }

    /// Removes a specific template from cache
    public func removeTemplate(for name: String) {
        lock.lock()
        cache.removeValue(forKey: name)
        lock.unlock()
    }

    /// Gets cache statistics
    public func getCacheStatistics() -> (count: Int, maxSize: Int, expirationSeconds: Double) {
        lock.lock()
        let stats = (count: cache.count, maxSize: maxCacheSize, expirationSeconds: cacheExpirationSeconds)
        lock.unlock()
        return stats
    }

    // MARK: - Cleanup helpers
    private func performCleanupIfNeeded_locked() {
        let now = Date()
        guard now.timeIntervalSince(lastCleanup) >= cleanupInterval else { return }
        lastCleanup = now

        let expiredKeys = cache.compactMap { (key, value) -> String? in
            now.timeIntervalSince(value.addedAt) > cacheExpirationSeconds ? key : nil
        }
        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }
    }
}

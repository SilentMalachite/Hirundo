import Foundation

/// A simplified in-memory cache manager with basic dependency invalidation.
public actor MemoryEfficientCacheManager {
    // MARK: - Types
    public struct CacheStatistics: Sendable {
        public var hits: Int = 0
        public var misses: Int = 0
        public var evictions: Int = 0
        public var invalidations: Int = 0
        public var currentSize: Int = 0
        public var entryCount: Int = 0

        public var hitRate: Double {
            let total = hits + misses
            return total > 0 ? Double(hits) / Double(total) : 0.0
        }

        public init() {}
    }

    // MARK: - Storage
    private var cache: [String: Data] = [:]
    private var dependencyIndex: [String: Set<String>] = [:] // dependency -> keys
    private var statistics = CacheStatistics()

    // Optional soft limits (not strictly enforced)
    private let maxMemorySize: Int
    private let maxEntries: Int

    // MARK: - Init
    public init(maxMemorySize: Int = 50_000_000, maxEntries: Int = 5000) {
        self.maxMemorySize = maxMemorySize
        self.maxEntries = maxEntries
    }

    // MARK: - Public API
    public func store(key: String, value: Data, dependencies: Set<String> = []) async {
        // Replace existing value and adjust size
        if let old = cache[key] {
            statistics.currentSize -= old.count
            // Remove old dependency links
            for (dep, var keys) in dependencyIndex {
                if keys.remove(key) != nil {
                    if keys.isEmpty { dependencyIndex.removeValue(forKey: dep) }
                    else { dependencyIndex[dep] = keys }
                }
            }
        }

        // Basic soft limiting (no complex eviction)
        if value.count > maxMemorySize { return }
        if cache.count >= maxEntries { return }

        cache[key] = value
        statistics.currentSize += value.count
        statistics.entryCount = cache.count

        // Index dependencies
        for dep in dependencies {
            var keys = dependencyIndex[dep] ?? []
            keys.insert(key)
            dependencyIndex[dep] = keys
        }
    }

    public func retrieve(key: String) async -> Data? {
        guard let data = cache[key] else {
            statistics.misses += 1
            return nil
        }
        statistics.hits += 1
        return data
    }

    public func invalidate(key: String, cascade: Bool = true) async {
        if let removed = cache.removeValue(forKey: key) {
            statistics.currentSize -= removed.count
            statistics.entryCount = cache.count
            statistics.invalidations += 1
        }

        // Remove reverse links
        for (dep, var keys) in dependencyIndex {
            if keys.remove(key) != nil {
                if keys.isEmpty { dependencyIndex.removeValue(forKey: dep) }
                else { dependencyIndex[dep] = keys }
            }
        }

        if cascade, let dependents = dependencyIndex[key] {
            for k in dependents { await invalidate(key: k, cascade: true) }
        }
    }

    public func invalidatePattern(_ pattern: String) async {
        // Simple wildcard support: treat '*' as a substring wildcard.
        let components = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        for key in Array(cache.keys) {
            var idx = key.startIndex
            var matched = true
            for part in components where !part.isEmpty {
                if let range = key.range(of: part, range: idx..<key.endIndex) {
                    idx = range.upperBound
                } else {
                    matched = false
                    break
                }
            }
            if matched { await invalidate(key: key, cascade: false) }
        }
    }

    public func currentSize() async -> Int { statistics.currentSize }
    public func getStatistics() async -> CacheStatistics { statistics }

    public func clear() async {
        cache.removeAll()
        dependencyIndex.removeAll()
        statistics = CacheStatistics()
    }

    public func invalidate(dependency: String) async {
        guard let dependents = dependencyIndex[dependency] else { return }
        for key in dependents { await invalidate(key: key, cascade: false) }
    }
}

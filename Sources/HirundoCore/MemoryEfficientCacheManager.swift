import Foundation
import CryptoKit
import os
#if canImport(Darwin)
import Darwin
#endif

/// Memory-efficient cache manager
/// With memory pressure monitoring, staged eviction, and streaming compression
public actor MemoryEfficientCacheManager {
    
    // MARK: - Types
    
    /// Simple cache entry
    private struct CacheEntry {
        let key: String
        let value: Data
        let dependencies: Set<String>
        let created: Date
        var accessed: Date
        var accessCount: Int
        
        init(key: String, value: Data, dependencies: Set<String>) {
            self.key = key
            self.value = value
            self.dependencies = dependencies
            self.created = Date()
            self.accessed = Date()
            self.accessCount = 1
        }
        
        mutating func updateAccess() {
            accessed = Date()
            accessCount += 1
        }
    }
    
    /// Cache statistics
    public struct CacheStatistics: Sendable {
        var hits: Int = 0
        var misses: Int = 0
        var evictions: Int = 0
        var invalidations: Int = 0
        var currentSize: Int = 0
        var entryCount: Int = 0
        
        var hitRate: Double {
            let total = hits + misses
            return total > 0 ? Double(hits) / Double(total) : 0.0
        }
    }
    
    // MARK: - Properties
    
    private let maxMemorySize: Int
    private let maxEntries: Int
    private var cache: [String: CacheEntry] = [:]
    private var dependencyIndex: [String: Set<String>] = [:]
    private var statistics = CacheStatistics()
    private var memoryPressureMonitor: DispatchSourceMemoryPressure?
    private let memoryPressureQueue = DispatchQueue(label: "cache.memory.pressure")
    
    // MARK: - Initialization
    
    public init(maxMemorySize: Int = 50_000_000, maxEntries: Int = 5000) {
        self.maxMemorySize = maxMemorySize
        self.maxEntries = maxEntries
        Task { await setupMemoryPressureMonitoring() }
    }
    
    deinit {
        memoryPressureMonitor?.cancel()
    }
    
    // MARK: - Public API
    
    /// Store data in cache
    public func store(
        key: String,
        value: Data,
        dependencies: Set<String> = []
    ) async {
        // Size limit check
        if value.count > maxMemorySize / 10 {
            return // Reject if exceeds 10% of max size
        }
        
        await ensureCapacity(for: value.count)
        
        // Remove old entry if exists
        if let oldEntry = cache[key] {
            statistics.currentSize -= oldEntry.value.count
        }
        
        // Add new entry
        let entry = CacheEntry(key: key, value: value, dependencies: dependencies)
        cache[key] = entry
        statistics.currentSize += value.count
        statistics.entryCount = cache.count
        
        // Update dependencies
        updateDependencies(key: key, dependencies: dependencies)
    }
    
    /// Retrieve data from cache
    public func retrieve(key: String) async -> Data? {
        guard var entry = cache[key] else {
            statistics.misses += 1
            return nil
        }
        
        // Update access info
        entry.updateAccess()
        cache[key] = entry
        statistics.hits += 1
        
        return entry.value
    }
    
    /// Invalidate cache entry
    public func invalidate(key: String, cascade: Bool = true) async {
        guard let entry = cache[key] else { return }
        
        // Update statistics
        statistics.currentSize -= entry.value.count
        statistics.entryCount -= 1
        statistics.invalidations += 1
        
        cache.removeValue(forKey: key)
        
        if cascade {
            await cascadeInvalidation(from: key)
        }
        
        removeDependencies(for: key)
    }
    
    /// Invalidate entries matching pattern
    public func invalidatePattern(_ pattern: String) async {
        let keysToInvalidate = cache.keys.filter { key in
            return matchesPattern(key, pattern: pattern)
        }
        
        for key in keysToInvalidate {
            await invalidate(key: key, cascade: false)
        }
    }
    
    /// Get current cache size
    public func currentSize() async -> Int {
        return statistics.currentSize
    }
    
    /// Get cache statistics
    public func getStatistics() async -> CacheStatistics {
        return statistics
    }
    
    /// Clear all cache entries
    public func clear() async {
        cache.removeAll()
        dependencyIndex.removeAll()
        statistics = CacheStatistics()
    }

    
    /// Invalidate all entries that depend on the given dependency key (e.g., a content path)
    public func invalidate(dependency: String) async {
        if let dependents = dependencyIndex[dependency] {
            for key in dependents {
                await invalidate(key: key, cascade: true)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func ensureCapacity(for newSize: Int) async {
        let projectedSize = statistics.currentSize + newSize
        
        if projectedSize > maxMemorySize || cache.count >= maxEntries {
            await performEviction(targetReduction: newSize * 2)
        }
    }
    
    private func performEviction(targetReduction: Int) async {
        var evictedSize = 0
        
        // Enhanced LRU: Sort by access time with frequency consideration
        let sortedEntries = cache.values.sorted { entry1, entry2 in
            // Primary sort: least recently accessed
            if entry1.accessed != entry2.accessed {
                return entry1.accessed < entry2.accessed
            }
            // Secondary sort: prefer smaller entries if access time is equal
            return entry1.value.count < entry2.value.count
        }
        
        var keysToRemove: [String] = []
        
        for entry in sortedEntries {
            if evictedSize >= targetReduction && keysToRemove.count > 0 {
                break
            }
            
            keysToRemove.append(entry.key)
            evictedSize += entry.value.count
        }
        
        // Batch removal for better performance
        for key in keysToRemove {
            if let entry = cache.removeValue(forKey: key) {
                removeDependencies(for: key)
                statistics.evictions += 1
                statistics.currentSize -= entry.value.count
            }
        }
        
        statistics.entryCount = cache.count
    }
    
    private func cascadeInvalidation(from key: String) async {
        guard let dependents = dependencyIndex[key] else { return }
        
        for dependent in dependents {
            if cache[dependent] != nil {
                await invalidate(key: dependent, cascade: true)
            }
        }
    }
    
    private func updateDependencies(key: String, dependencies: Set<String>) {
        for dependency in dependencies {
            if dependencyIndex[dependency] == nil {
                dependencyIndex[dependency] = Set<String>()
            }
            dependencyIndex[dependency]?.insert(key)
        }
    }
    
    private func removeDependencies(for key: String) {
        for (dependency, var dependents) in dependencyIndex {
            if dependents.contains(key) {
                dependents.remove(key)
                if dependents.isEmpty {
                    dependencyIndex.removeValue(forKey: dependency)
                } else {
                    dependencyIndex[dependency] = dependents
                }
            }
        }
    }
    
    private func matchesPattern(_ string: String, pattern: String) -> Bool {
        if pattern.contains("*") {
            let regexPattern = pattern.replacingOccurrences(of: "*", with: ".*")
            do {
                let regex = try NSRegularExpression(pattern: "^" + regexPattern + "$")
                let range = NSRange(location: 0, length: string.count)
                return regex.firstMatch(in: string, range: range) != nil
            } catch {
                return string == pattern
            }
        } else {
            return string == pattern
        }
    }
    
    // MARK: - Memory Pressure Monitoring
    
    private func setupMemoryPressureMonitoring() async {
        #if canImport(Darwin)
        memoryPressureMonitor = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: memoryPressureQueue
        )
        
        memoryPressureMonitor?.setEventHandler { [weak self] in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                await strongSelf.handleMemoryPressure()
            }
        }
        
        memoryPressureMonitor?.resume()
        #endif
    }
    
    private func handleMemoryPressure() async {
        os_log(.info, log: .default, "Memory pressure detected, performing aggressive cache cleanup")
        
        // Perform aggressive eviction under memory pressure
        let targetReduction = statistics.currentSize / 2 // Remove 50% of cache
        await performEviction(targetReduction: targetReduction)
        
        // Update statistics
        statistics.evictions += 1
    }
}
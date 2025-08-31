import Foundation
import CryptoKit

/// Manages template rendering cache
public class TemplateCacheManager {
    private let cacheManager: MemoryEfficientCacheManager
    
    public init() {
        self.cacheManager = MemoryEfficientCacheManager()
    }
    
    /// Generates a cache key for template rendering
    public func generateCacheKey(
        for content: ProcessedContent,
        htmlContent: String,
        pagesCount: Int,
        postsCount: Int
    ) -> String {
        // Create a stable SHA256-based key
        let keyComponents = [
            content.url.path,
            content.metadata.title,
            String(content.metadata.date.timeIntervalSince1970),
            content.metadata.template ?? "default",
            String(pagesCount),
            String(postsCount),
            String(htmlContent.count)
        ]
        let combined = keyComponents.joined(separator: "|")
        let digest = SHA256.hash(data: Data(combined.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        // Use 32 chars for readability
        return "template_" + String(hex.prefix(32))
    }
    
    /// Retrieves cached template result
    public func retrieve(key: String) async -> String? {
        guard let cachedData = await cacheManager.retrieve(key: key),
              let cachedResult = String(data: cachedData, encoding: .utf8) else {
            return nil
        }
        return cachedResult
    }
    
    /// Stores template result in cache
    public func store(
        key: String,
        value: String,
        content: ProcessedContent,
        pagesCount: Int,
        postsCount: Int
    ) async {
        guard let renderedData = value.data(using: .utf8) else { return }
        
        let dependencies = Set([
            content.url.path,
            content.metadata.template ?? "default",
            "pages_\(pagesCount)",
            "posts_\(postsCount)"
        ])
        
        await cacheManager.store(
            key: key,
            value: renderedData,
            dependencies: dependencies
        )
    }
    
    /// Invalidates cache for a specific content piece
    public func invalidateCache(for content: ProcessedContent) async {
        // Invalidate by dependency (content path) to cascade to all dependent entries
        await cacheManager.invalidate(dependency: content.url.path)
    }
    
    /// Clears all template cache
    public func clearCache() async {
        await cacheManager.clear()
    }
    
    /// Gets cache statistics
    public func getCacheStatistics() async -> MemoryEfficientCacheManager.CacheStatistics {
        return await cacheManager.getStatistics()
    }
}
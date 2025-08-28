import Foundation
import Stencil
import PathKit

public class TemplateEngine: @unchecked Sendable {
    private var environment: Environment
    private let templatesDirectory: String
    private var cache: [String: (template: Template, addedAt: Date)] = [:]
    private let cacheQueue = DispatchQueue(label: "com.hirundo.templatecache", attributes: .concurrent)
    private var siteConfig: Site?
    private let environmentQueue = DispatchQueue(label: "com.hirundo.environment", attributes: .concurrent)
    
    // Cache management properties
    private let maxCacheSize = 100 // Maximum number of templates to cache
    private let cacheExpirationSeconds = 3600.0 // Cache entries expire after 1 hour
    private var cacheCleanupTimer: DispatchSourceTimer?
    private let cleanupQueue = DispatchQueue(label: "com.hirundo.cleanup", attributes: .concurrent)
    
    public init(templatesDirectory: String) {
        self.templatesDirectory = templatesDirectory
        let loader = FileSystemLoader(paths: [Path(templatesDirectory)])
        
        var ext = Extension()
        TemplateEngine.registerStaticFilters(to: &ext)
        
        self.environment = Environment(
            loader: loader,
            extensions: [ext]
        )
        
        // Start cache cleanup timer
        startCacheCleanupTimer()
    }
    
    deinit {
        cacheCleanupTimer?.cancel()
    }
    
    public func configure(with siteConfig: Site) {
        environmentQueue.sync(flags: .barrier) {
            self.siteConfig = siteConfig
            
            // Re-register filters with site config
            var ext = Extension()
            TemplateEngine.registerStaticFilters(to: &ext)
            registerDynamicFilters(to: &ext, siteConfig: siteConfig)
            
            // Update environment with new extension
            let loader = FileSystemLoader(paths: [Path(templatesDirectory)])
            self.environment = Environment(
                loader: loader,
                extensions: [ext]
            )
            
            // Clear template cache since environment changed
            cache.removeAll()
        }
    }
    
    public func render(template: String, context: [String: Any]) throws -> String {
        do {
            let templateObj = try getTemplate(name: template)
            return try templateObj.render(context)
        } catch _ as TemplateDoesNotExist {
            throw TemplateError.templateNotFound(template)
        } catch {
            throw TemplateError.renderError(error.localizedDescription)
        }
    }
    
    public func clearCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
        }
    }
    
    public func registerCustomFilters() {
        // Filters are already registered in init
        // This method exists for compatibility with tests
    }
    
    /// Validate template syntax without rendering
    public func validateTemplate(name: String) throws {
        let templatePath = Path(templatesDirectory) + name
        guard templatePath.exists else {
            throw TemplateEngineError.templateNotFound(name)
        }
        
        do {
            let templateContent: String = try templatePath.read()
            _ = environment.templateClass.init(templateString: templateContent, environment: environment)
        } catch {
            throw TemplateEngineError.syntaxError(name, error.localizedDescription)
        }
    }
    
    /// Validate all templates in the templates directory
    public func validateAllTemplates() throws {
        let templatesPath = Path(templatesDirectory)
        guard templatesPath.exists else {
            throw TemplateEngineError.templatesDirectoryNotFound(templatesDirectory)
        }
        
        var errors: [String] = []
        
        for file in try templatesPath.recursiveChildren() {
            if file.extension == "html" || file.extension == "stencil" {
                do {
                    try validateTemplate(name: file.lastComponent)
                } catch {
                    errors.append("Template \(file.lastComponent): \(error.localizedDescription)")
                }
            }
        }
        
        if !errors.isEmpty {
            throw TemplateEngineError.multipleValidationErrors(errors)
        }
    }
    
    private func getTemplate(name: String) throws -> Template {
        // First, check cache with concurrent read access
        let now = Date()
        let cachedEntry: Template? = cacheQueue.sync {
            if let entry = cache[name] {
                // Check if entry is expired
                if now.timeIntervalSince(entry.addedAt) < cacheExpirationSeconds {
                    return entry.template
                }
            }
            return nil
        }
        
        if let cached = cachedEntry {
            return cached
        }
        
        // If not in cache or expired, load template with barrier write access
        return try cacheQueue.sync(flags: .barrier) {
            // Double-check pattern: another thread might have loaded it
            if let entry = cache[name] {
                if now.timeIntervalSince(entry.addedAt) < cacheExpirationSeconds {
                    return entry.template
                }
            }
            
            // Get environment safely
            let env = environmentQueue.sync {
                return environment
            }
            
            // Detect circular inheritance proactively to avoid runtime crashes
            try detectCircularInheritance(for: name)
            
            let template = try env.loadTemplate(name: name)
            
            // Enforce cache size limit using LRU eviction
            if cache.count >= maxCacheSize {
                evictOldestCacheEntries()
            }
            
            cache[name] = (template: template, addedAt: now)
            return template
        }
    }

    // MARK: - Circular inheritance detection
    /// Parses the template chain starting at `name` and throws if a cycle is detected.
    private func detectCircularInheritance(for name: String) throws {
        var visited = Set<String>()
        var chain: [String] = []
        var current: String? = name
        let rootPath = Path(templatesDirectory)
        
        while let templateName = current {
            // If we've seen this template already, a cycle exists
            if visited.contains(templateName) {
                chain.append(templateName)
                let pathStr = chain.joined(separator: " -> ")
                throw TemplateError.renderError("Circular template inheritance detected: \(pathStr)")
            }
            visited.insert(templateName)
            chain.append(templateName)
            
            // Read the template file content; if missing, stop checking and let loader handle it later
            let filePath = rootPath + templateName
            guard filePath.exists else {
                break
            }
            let content: String
            do {
                content = try filePath.read()
            } catch {
                // If we cannot read, stop cycle detection and let the environment throw a descriptive error
                break
            }
            
            // Extract parent template from an extends tag with a string literal
            if let parent = TemplateEngine.parentTemplateName(in: content) {
                current = parent
            } else {
                break
            }
        }
    }
    
    /// Extracts the parent template name from an `{% extends "..." %}` or `{% extends '...' %}` tag.
    private static func parentTemplateName(in content: String) -> String? {
        // Simple regex to capture quoted literal in extends tag
        // Supports both double and single quotes
        let patterns = [
            #"\{\%\s*extends\s*\"([^\"]+)\"\s*\%\}"#,
            #"\{\%\s*extends\s*\'([^\']+)\'\s*\%\}"#
        ]
        for pattern in patterns {
            if let range = content.range(of: pattern, options: [.regularExpression]) {
                let match = String(content[range])
                // Extract the first quoted group
                if let quoteStart = match.firstIndex(where: { $0 == "\"" || $0 == "'" }) {
                    let quote = match[quoteStart]
                    if let quoteEnd = match[match.index(after: quoteStart)...].firstIndex(of: quote) {
                        let nameRange = match.index(after: quoteStart)..<quoteEnd
                        return String(match[nameRange])
                    }
                }
            }
        }
        return nil
    }
    
    private func evictOldestCacheEntries() {
        // Remove 20% of oldest entries when cache is full
        let entriesToRemove = max(1, maxCacheSize / 5)
        let sortedEntries = cache.sorted { $0.value.addedAt < $1.value.addedAt }
        
        for (key, _) in sortedEntries.prefix(entriesToRemove) {
            cache.removeValue(forKey: key)
        }
    }
    
    private func startCacheCleanupTimer() {
        // Use cacheQueue for timer to ensure proper synchronization
        let timer = DispatchSource.makeTimerSource(queue: cacheQueue)
        timer.schedule(deadline: .now() + 300, repeating: 300)
        timer.setEventHandler { [weak self] in
            self?.cleanupExpiredCacheEntries()
        }
        timer.resume()
        cacheCleanupTimer = timer
    }
    
    private func cleanupExpiredCacheEntries() {
        let now = Date()
        // Since timer now runs on cacheQueue, we're already in the queue context
        // No need for async - directly operate with proper synchronization
        guard !cache.isEmpty else { return }
        
        // Remove expired entries
        cache = cache.filter { _, entry in
            now.timeIntervalSince(entry.addedAt) < cacheExpirationSeconds
        }
        
        // Also enforce max cache size using LRU eviction
        if cache.count > maxCacheSize {
            // Sort by access time and keep only the most recent entries
            let sortedEntries = cache.sorted { $0.value.addedAt > $1.value.addedAt }
            let entriesToKeep = Array(sortedEntries.prefix(maxCacheSize))
            cache = Dictionary(uniqueKeysWithValues: entriesToKeep.map { ($0.key, $0.value) })
        }
    }
    
    private static func registerStaticFilters(to ext: inout Extension) {
        // Date filter
        ext.registerFilter("date") { (value, args) in
            guard let date = value as? Date else { return value }
            
            let format = args.first as? String ?? "yyyy-MM-dd"
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            
            // Convert special format strings
            let convertedFormat = format
                .replacingOccurrences(of: "%Y", with: "yyyy")
                .replacingOccurrences(of: "%m", with: "MM")
                .replacingOccurrences(of: "%d", with: "dd")
                .replacingOccurrences(of: "%B", with: "MMMM")
                .replacingOccurrences(of: "%b", with: "MMM")
                .replacingOccurrences(of: "%H", with: "HH")
                .replacingOccurrences(of: "%M", with: "mm")
                .replacingOccurrences(of: "%S", with: "ss")
            
            formatter.dateFormat = convertedFormat
            return formatter.string(from: date)
        }
        
        // Slugify filter (Unicode-aware)
        ext.registerFilter("slugify") { value in
            guard let string = value as? String else { return value }
            return string.slugify()
        }
        
        // Excerpt filter
        ext.registerFilter("excerpt") { (value, args) in
            guard let string = value as? String else { return value }
            
            let length = args.first as? Int ?? 200
            
            if string.count <= length {
                return string
            }
            
            let index = string.index(string.startIndex, offsetBy: length)
            return String(string[..<index]) + "..."
        }
        
        // Note: absolute_url filter is registered dynamically with site config
        
        // Markdown filter
        ext.registerFilter("markdown") { value in
            guard let string = value as? String else { return value }
            
            // Simple markdown to HTML conversion
            // In real implementation, this would use the MarkdownParser
            var result = string
            
            // Replace bold text
            while let range = result.range(of: "\\*\\*(.*?)\\*\\*", options: .regularExpression) {
                let match = String(result[range])
                let text = match.dropFirst(2).dropLast(2)
                result = result.replacingCharacters(in: range, with: "<strong>\(text)</strong>")
            }
            
            return result
        }
    }
    
    // Register filters that depend on site configuration
    private func registerDynamicFilters(to ext: inout Extension, siteConfig: Site) {
        // Absolute URL filter with actual site config
        ext.registerFilter("absolute_url") { value in
            guard let path = value as? String else { return value }
            
            let siteUrl = siteConfig.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            
            if path.hasPrefix("http://") || path.hasPrefix("https://") {
                return path
            }
            
            if path.hasPrefix("/") {
                return siteUrl + path
            }
            
            return siteUrl + "/" + path
        }
        
        // Site-aware URL filter that can handle relative links
        ext.registerFilter("site_url") { value in
            guard let path = value as? String else { return value }
            
            let baseUrl = siteConfig.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            
            // Handle absolute URLs
            if path.hasPrefix("http://") || path.hasPrefix("https://") {
                return path
            }
            
            // Handle root-relative URLs
            if path.hasPrefix("/") {
                return baseUrl + path
            }
            
            // Handle relative URLs
            return baseUrl + "/" + path
        }
        
        // Language-aware date filter
        ext.registerFilter("localized_date") { (value, args) in
            guard let date = value as? Date else { return value }
            
            let format = args.first as? String ?? "yyyy-MM-dd"
            let formatter = DateFormatter()
            formatter.dateFormat = format
            
            // Use site language for locale
            if let languageCode = siteConfig.language {
                formatter.locale = Locale(identifier: languageCode)
            }
            
            return formatter.string(from: date)
        }
    }
}

// MARK: - Template Engine Errors

public enum TemplateEngineError: LocalizedError {
    case templateNotFound(String)
    case syntaxError(String, String)
    case templatesDirectoryNotFound(String)
    case multipleValidationErrors([String])
    
    public var errorDescription: String? {
        switch self {
        case .templateNotFound(let name):
            return "Template not found: \(name)"
        case .syntaxError(let name, let error):
            return "Syntax error in template \(name): \(error)"
        case .templatesDirectoryNotFound(let path):
            return "Templates directory not found: \(path)"
        case .multipleValidationErrors(let errors):
            return "Multiple template validation errors:\n" + errors.joined(separator: "\n")
        }
    }
}

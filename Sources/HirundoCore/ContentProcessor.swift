import Foundation
import Markdown

// Content processing responsibility separated from SiteGenerator
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

/// Thread-safety: ContentProcessor has no shared mutable state across tasks; per-file processing avoids shared mutation.
public class ContentProcessor: @unchecked Sendable {
    private let markdownParser: MarkdownParser
    private let config: HirundoConfig
    private let projectPath: String
    
    public init(config: HirundoConfig, projectPath: String) {
        self.config = config
        self.markdownParser = MarkdownParser()
        self.projectPath = projectPath
    }
    
    // Process a markdown file and return parsed content
    public func processMarkdownFile(
        at fileURL: URL,
        projectPath: String,
        includeDrafts: Bool
    ) async throws -> ProcessedContent? {
        // Read file content
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            // Convert file reading errors to appropriate MarkdownError
            if let nsError = error as NSError? {
                if nsError.domain == NSCocoaErrorDomain && nsError.code == 259 {
                    // Code 259 is NSFileReadUnknownStringEncodingError (invalid encoding)
                    throw MarkdownError.invalidEncoding
                }
            }
            // Re-throw other errors as-is
            throw error
        }
        
        // Parse markdown
        let result = try markdownParser.parse(content)
        
        // Check if it's a draft
        if let isDraft = result.frontMatter?["draft"] as? Bool, isDraft && !includeDrafts {
            return nil
        }
        
        // Determine content type
        let contentType = determineContentType(from: fileURL, metadata: result.frontMatter ?? [:])
        
        // Create processed content
        return ProcessedContent(
            url: fileURL,
            markdown: result,
            type: contentType,
            metadata: try extractMetadata(from: result.frontMatter ?? [:])
        )
    }
    
    // Process all content in a directory with memory-efficient batching
    public func processDirectory(
        at directoryURL: URL,
        includeDrafts: Bool
    ) async throws -> [ProcessedContent] {
        return try await processDirectoryInBatches(
            at: directoryURL,
            includeDrafts: includeDrafts,
            batchSize: 50 // Process 50 files at a time
        )
    }
    
    // Memory-efficient batch processing for large directories
    public func processDirectoryInBatches(
        at directoryURL: URL,
        includeDrafts: Bool,
        batchSize: Int = 50
    ) async throws -> [ProcessedContent] {
        // First, collect all markdown file URLs
        var markdownURLs: [URL] = []
        
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ContentProcessorError.cannotEnumerateDirectory(directoryURL.path)
        }
        
        // Use manual iteration to avoid makeIterator() async issue
        var pendingURLs: [URL] = []
        let processEnumerator = {
            while let fileURL = enumerator.nextObject() as? URL {
                guard fileURL.pathExtension == "md" || fileURL.pathExtension == "markdown" else {
                    continue
                }
                
                // Check file size to warn about potentially large files
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   fileSize > self.config.limits.maxMarkdownFileSize {
                    print("Warning: Large markdown file detected: \(fileURL.lastPathComponent) (\(fileSize) bytes)")
                    // Skip files that are too large to prevent memory issues
                    if fileSize > self.config.limits.maxMarkdownFileSize * 2 {
                        print("Skipping extremely large file: \(fileURL.lastPathComponent)")
                        continue
                    }
                }
                
                pendingURLs.append(fileURL)
            }
        }
        
        // Execute enumeration in non-async context
        await Task {
            processEnumerator()
        }.value
        
        markdownURLs = pendingURLs
        
        // Process files in batches to control memory usage
        var allProcessedContents: [ProcessedContent] = []
        let batches = markdownURLs.chunked(into: batchSize)
        
        for (batchIndex, batch) in batches.enumerated() {
            print("Processing batch \(batchIndex + 1)/\(batches.count) (\(batch.count) files)")
            
            // Process batch efficiently with async/await and memory management
            let batchContents = try await withThrowingTaskGroup(of: ProcessedContent?.self) { group in
                var results: [ProcessedContent] = []
                
                for fileURL in batch {
                    group.addTask { [self] in
                        return try await self.processMarkdownFile(
                            at: fileURL,
                            projectPath: self.projectPath,
                            includeDrafts: includeDrafts
                        )
                    }
                }
                
                for try await result in group {
                    if let processed = result {
                        results.append(processed)
                    }
                }
                
                return results
            }
            
            allProcessedContents.append(contentsOf: batchContents)
            
            // Optional: Add small delay between batches to reduce system pressure
            if batchIndex < batches.count - 1 {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
        
        return allProcessedContents
    }
    
    // Process directory with error recovery and memory efficiency
    public func processDirectoryWithRecovery(
        at directoryURL: URL,
        includeDrafts: Bool,
        batchSize: Int = 50
    ) async throws -> (contents: [ProcessedContent], errors: [(url: URL, error: Error)]) {
        var allProcessedContents: [ProcessedContent] = []
        var allErrors: [(url: URL, error: Error)] = []
        
        // Collect markdown files first
        var markdownURLs: [URL] = []
        
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ContentProcessorError.cannotEnumerateDirectory(directoryURL.path)
        }
        
        // Use manual iteration to avoid makeIterator() async issue
        var pendingURLs: [URL] = []
        let processEnumerator = {
            while let fileURL = enumerator.nextObject() as? URL {
                guard fileURL.pathExtension == "md" || fileURL.pathExtension == "markdown" else {
                    continue
                }
                pendingURLs.append(fileURL)
            }
        }
        
        // Execute enumeration in non-async context
        await Task {
            processEnumerator()
        }.value
        
        markdownURLs = pendingURLs
        
        let batches = markdownURLs.chunked(into: batchSize)
        
        for (batchIndex, batch) in batches.enumerated() {
            print("Processing batch \(batchIndex + 1)/\(batches.count) (\(batch.count) files) with error recovery")
            
            // Process batch with async error handling and parallel processing
            let (batchContents, batchErrors) = await withTaskGroup(of: (ProcessedContent?, (URL, Error)?).self) { group in
                var contents: [ProcessedContent] = []
                var errors: [(URL, Error)] = []
                
                for fileURL in batch {
                    group.addTask { [self] in
                        do {
                            let processed = try await self.processMarkdownFile(
                                at: fileURL,
                                projectPath: self.projectPath,
                                includeDrafts: includeDrafts
                            )
                            return (processed, nil)
                        } catch {
                            return (nil, (fileURL, error))
                        }
                    }
                }
                
                for await result in group {
                    if let content = result.0 {
                        contents.append(content)
                    }
                    if let error = result.1 {
                        errors.append(error)
                    }
                }
                
                return (contents, errors)
            }
            
            allProcessedContents.append(contentsOf: batchContents)
            allErrors.append(contentsOf: batchErrors)
            
            // Log batch completion
            print("[ContentProcessor] Batch \(batchIndex + 1) completed: \(batchContents.count) files processed, \(batchErrors.count) errors")
            
            // Memory pressure relief between batches
            if batchIndex < batches.count - 1 {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
        
        return (contents: allProcessedContents, errors: allErrors)
    }
    
    public func renderMarkdownContent(_ result: MarkdownParseResult) -> String {
        // Use the built-in HTML formatter from swift-markdown for robustness and accuracy.
        return result.document?.htmlString ?? ""
    }
    
    private func determineContentType(from url: URL, metadata: [String: Any]) -> ProcessedContentType {
        // Check if explicitly specified in metadata
        if let typeString = metadata["type"] as? String {
            switch typeString.lowercased() {
            case "post", "blog":
                return .post
            case "page":
                return .page
            default:
                break
            }
        }
        
        // Determine by path
        let path = url.path.lowercased()
        if path.contains("/posts/") || path.contains("/blog/") {
            return .post
        }
        
        return .page
    }
    
    private func extractMetadata(from metadata: [String: Any]) throws -> ContentMetadata {
        let date: Date
        if let dateValue = metadata["date"] {
            if let parsedDate = dateValue as? Date {
                date = parsedDate
            } else if let dateString = dateValue as? String {
                // Try to parse common ISO 8601 formats from string values
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                if let d = formatter.date(from: dateString) {
                    date = d
                } else {
                    throw MarkdownError.invalidFrontMatter("Invalid date format. Expected ISO 8601 format (e.g., YYYY-MM-DDTHH:MM:SSZ).")
                }
            } else {
                throw MarkdownError.invalidFrontMatter("Invalid date value type in front matter")
            }
        } else {
            // Default to the current date if not provided.
            date = Date()
        }

        return ContentMetadata(
            title: metadata["title"] as? String ?? "Untitled",
            description: metadata["description"] as? String,
            date: date,
            author: metadata["author"] as? String,
            categories: extractStringArray(from: metadata["categories"]),
            tags: extractStringArray(from: metadata["tags"]),
            template: metadata["template"] as? String,
            slug: metadata["slug"] as? String
        )
    }
    
    private func extractStringArray(from value: Any?) -> [String] {
        if let array = value as? [String] {
            return array
        } else if let string = value as? String {
            return [string]
        }
        return []
    }
}

// Array extension is defined elsewhere

// Processed content model
public struct ProcessedContent: Sendable {
    public let url: URL
    public let markdown: MarkdownParseResult
    public let type: ProcessedContentType
    public let metadata: ContentMetadata
}

// Content metadata
public struct ContentMetadata: Sendable {
    public let title: String
    public let description: String?
    public let date: Date
    public let author: String?
    public let categories: [String]
    public let tags: [String]
    public let template: String?
    public let slug: String?
}

// Content type enum
public enum ProcessedContentType: Sendable {
    case page
    case post
}

// Content processor errors
public enum ContentProcessorError: LocalizedError {
    case cannotEnumerateDirectory(String)
    case invalidContent(String)
    case fileSizeExceeded(String, Int)
    case batchProcessingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .cannotEnumerateDirectory(let path):
            return "Cannot enumerate directory: \(path)"
        case .invalidContent(let reason):
            return "Invalid content: \(reason)"
        case .fileSizeExceeded(let path, let size):
            return "File size exceeded limit: \(path) (\(size) bytes)"
        case .batchProcessingFailed(let reason):
            return "Batch processing failed: \(reason)"
        }
    }
}

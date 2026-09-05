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

/// Thread-safe content processor with immutable configuration
public final class ContentProcessor: Sendable {
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

        for fileURL in try collectMarkdownFiles(in: directoryURL) {
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

            markdownURLs.append(fileURL)
        }

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
        let markdownURLs = try collectMarkdownFiles(in: directoryURL)

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
    
    // MARK: - Content discovery

    /// Collects every Markdown file under `directoryURL`, following symlinks to directories.
    ///
    /// The traversal itself lives in ``SymlinkFollowingWalk``, which `HotReloadManager` walks
    /// the same tree with: a build that includes content the watcher never notices changing is
    /// the same silent-staleness bug one level over, so the two must not be able to diverge.
    ///
    /// Every file is reported at its *logical* path — the one under `directoryURL` — never at
    /// the resolved one. `SiteGenerator` derives the output URL from the path relative to the
    /// content directory, so a file found through `content/shared` has to come back as
    /// `content/shared/page.md` or its page moves.
    ///
    /// Only links that stay inside the project are followed, and never into the directories the
    /// project builds from or into. Every decision is printed, because a walk that silently
    /// changes what it includes is the failure this whole traversal exists to fix.
    ///
    /// - Parameter directoryURL: Content directory to walk. May itself be a symlink.
    /// - Returns: Logical URLs of the `.md` and `.markdown` files found, in enumeration order.
    /// - Throws: `ContentProcessorError.cannotEnumerateDirectory` when `directoryURL` cannot
    ///   be enumerated.
    func collectMarkdownFiles(in directoryURL: URL) throws -> [URL] {
        var collected: [URL] = []
        try Self.walk(projectPath: projectPath, build: config.build).walk(directoryURL) { entry in
            guard Self.isMarkdown(entry) else { return }
            collected.append(entry)
        }
        return collected
    }

    /// The walk a build performs: contained in the project, never into a build directory, and
    /// printing what it decided.
    ///
    /// Exposed so a watcher over the same tree can be given the identical boundary rather than
    /// a second one that drifts.
    static func walk(projectPath: String, build: Build) -> SymlinkFollowingWalk {
        return SymlinkFollowingWalk(
            boundary: .project(
                root: projectPath,
                excludingDirectoriesNamed: [
                    build.outputDirectory,
                    build.staticDirectory,
                    build.templatesDirectory
                ]
            ),
            announcesDecisions: true
        )
    }

    private static func isMarkdown(_ url: URL) -> Bool {
        return url.pathExtension == "md" || url.pathExtension == "markdown"
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

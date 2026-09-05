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
    /// `FileManager`'s enumerator stops at a symlinked directory instead of walking into it,
    /// so a site keeping part of its content elsewhere — `content/posts -> ../shared-posts` —
    /// built without those files and said nothing. `ContentScaffolder` writes to the literal
    /// path the user names, symlinks included, so `hirundo new` was creating files the build
    /// then ignored; the walk has to reach whatever the scaffolder can write.
    ///
    /// Every file is reported at its *logical* path — the one under `directoryURL` — never at
    /// the resolved one. `SiteGenerator` derives the output URL from the path relative to the
    /// content directory, so a file found through `content/shared` has to come back as
    /// `content/shared/page.md` or its page moves.
    ///
    /// - Parameter directoryURL: Content directory to walk. May itself be a symlink.
    /// - Returns: Logical URLs of the `.md` and `.markdown` files found, in enumeration order.
    /// - Throws: `ContentProcessorError.cannotEnumerateDirectory` when `directoryURL` cannot
    ///   be enumerated.
    func collectMarkdownFiles(in directoryURL: URL) throws -> [URL] {
        var collected: [URL] = []
        // Seeded with the content directory itself, so `content/here -> .` is recognised as a
        // loop rather than walked a second time.
        var visitedDirectories: Set<String> = [Self.canonicalPath(of: directoryURL)]

        // A content directory that is itself a symlink enumerates as empty, so walk its target.
        if let target = Self.directorySymlinkTarget(of: directoryURL) {
            collectMarkdownFiles(
                inResolved: target,
                reportedAs: directoryURL,
                visitedDirectories: &visitedDirectories,
                into: &collected
            )
            return collected
        }

        // Unchanged from before directory symlinks were followed: same call, same options, so
        // a site with no symlinked content walks exactly as it always did.
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ContentProcessorError.cannotEnumerateDirectory(directoryURL.path)
        }

        while let fileURL = enumerator.nextObject() as? URL {
            // Checked before the extension filter: a linked directory rarely ends in `.md`,
            // and the filter would drop it before it could be followed.
            if let target = Self.directorySymlinkTarget(of: fileURL),
               let logicalURL = Self.logicalURL(for: fileURL, enumeratedFrom: directoryURL) {
                guard visitedDirectories.insert(Self.canonicalPath(of: target)).inserted else {
                    continue
                }
                collectMarkdownFiles(
                    inResolved: target,
                    reportedAs: logicalURL,
                    visitedDirectories: &visitedDirectories,
                    into: &collected
                )
                continue
            }

            guard Self.isMarkdown(fileURL) else {
                continue
            }
            collected.append(fileURL)
        }

        return collected
    }

    /// Walks a directory reached through a symlink, reporting what it holds under
    /// `logicalDirectory`.
    ///
    /// Shallow reads plus recursion rather than a second `enumerator`, because the logical
    /// path is then built one component at a time — no arithmetic against a prefix the
    /// enumerator is free to normalise (`/var` to `/private/var` on macOS).
    ///
    /// - Parameters:
    ///   - resolvedDirectory: Directory to read, with its symlinks already resolved.
    ///   - logicalDirectory: Path this directory is reported at, under the content directory.
    ///   - visitedDirectories: Canonical paths already walked; a directory is entered once, so
    ///     `content/loop -> ..` and links pointing at each other terminate instead of looping.
    ///   - collected: Accumulates the Markdown files found, at their logical paths.
    private func collectMarkdownFiles(
        inResolved resolvedDirectory: URL,
        reportedAs logicalDirectory: URL,
        visitedDirectories: inout Set<String>,
        into collected: inout [URL]
    ) {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: resolvedDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            // The enumerator skips directories it cannot read; say so rather than fail the
            // build, since the whole point of this walk is that silence hides content.
            print("Warning: Cannot read linked content directory: \(logicalDirectory.path) (\(error.localizedDescription))")
            return
        }

        for entry in entries {
            let logicalURL = logicalDirectory.appendingPathComponent(entry.lastPathComponent)

            if let target = Self.directorySymlinkTarget(of: entry) {
                guard visitedDirectories.insert(Self.canonicalPath(of: target)).inserted else {
                    continue
                }
                collectMarkdownFiles(
                    inResolved: target,
                    reportedAs: logicalURL,
                    visitedDirectories: &visitedDirectories,
                    into: &collected
                )
                continue
            }

            if Self.isDirectory(entry) {
                guard visitedDirectories.insert(Self.canonicalPath(of: entry)).inserted else {
                    continue
                }
                collectMarkdownFiles(
                    inResolved: entry,
                    reportedAs: logicalURL,
                    visitedDirectories: &visitedDirectories,
                    into: &collected
                )
                continue
            }

            guard Self.isMarkdown(entry) else {
                continue
            }
            collected.append(logicalURL)
        }
    }

    /// Rewrites an enumerated URL so it is rooted at `root` exactly as the caller wrote it.
    ///
    /// The enumerator hands back its own normalisation of the path it was given, which on
    /// macOS turns `/var/…` into `/private/var/…`. Left alone, that prefix travels with every
    /// file found through a symlink and lands in the output path, so it is mapped back here.
    /// Only the entry's ancestors need resolving, and they are always real directories — the
    /// enumerator never descends through a link.
    ///
    /// - Returns: The entry under `root`, or `nil` if it is not below `root` at all.
    private static func logicalURL(for entry: URL, enumeratedFrom root: URL) -> URL? {
        let rootPath = canonicalPath(of: root)
        let parentPath = canonicalPath(of: entry.deletingLastPathComponent())

        if parentPath == rootPath {
            return root.appendingPathComponent(entry.lastPathComponent)
        }
        guard parentPath.hasPrefix(rootPath + "/") else {
            return nil
        }
        let relativeParent = String(parentPath.dropFirst(rootPath.count + 1))
        return root
            .appendingPathComponent(relativeParent)
            .appendingPathComponent(entry.lastPathComponent)
    }

    /// Resolves `url` when it is a symlink pointing at a directory, `nil` otherwise.
    ///
    /// Symlinks to files need no help: the enumerator reports them like any other entry and
    /// reading one already follows the link.
    private static func directorySymlinkTarget(of url: URL) -> URL? {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
              values.isSymbolicLink == true else {
            return nil
        }
        let resolved = url.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            // Broken link, or a link to a file.
            return nil
        }
        return resolved
    }

    /// Identity a directory is remembered by, so the same one is never entered twice.
    ///
    /// `resolvingSymlinksInPath` gives one spelling per directory whichever link chain, `..`
    /// segment, or `/private` prefix led there — the property the cycle check rests on.
    private static func canonicalPath(of url: URL) -> String {
        return url.resolvingSymlinksInPath().path
    }

    private static func isDirectory(_ url: URL) -> Bool {
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
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

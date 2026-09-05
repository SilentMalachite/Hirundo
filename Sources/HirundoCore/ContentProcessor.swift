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
    /// Only links that stay inside the project are followed, and never into the directories the
    /// project builds from or into; see `shouldFollowSymlink(at:reportedAs:to:visitedDirectories:)`.
    /// Every decision is printed, because a walk that silently changes what it includes is the
    /// failure this whole traversal exists to fix.
    ///
    /// - Parameter directoryURL: Content directory to walk. May itself be a symlink.
    /// - Returns: Logical URLs of the `.md` and `.markdown` files found, in enumeration order.
    /// - Throws: `ContentProcessorError.cannotEnumerateDirectory` when `directoryURL` cannot
    ///   be enumerated.
    func collectMarkdownFiles(in directoryURL: URL) throws -> [URL] {
        var collected: [URL] = []
        var visitedDirectories: Set<String> = []

        // A content directory that is itself a symlink enumerates as empty, so walk its target.
        if let target = Self.directorySymlinkTarget(of: directoryURL) {
            guard shouldFollowSymlink(
                at: directoryURL,
                reportedAs: directoryURL,
                to: target,
                visitedDirectories: &visitedDirectories
            ) else {
                return collected
            }
            collectMarkdownFiles(
                inResolved: target,
                reportedAs: directoryURL,
                visitedDirectories: &visitedDirectories,
                into: &collected
            )
            return collected
        }
        // Recorded before the walk starts, so `content/here -> .` is recognised as a loop
        // rather than walked a second time.
        visitedDirectories.insert(Self.canonicalPath(of: directoryURL))

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
                guard shouldFollowSymlink(
                    at: fileURL,
                    reportedAs: logicalURL,
                    to: target,
                    visitedDirectories: &visitedDirectories
                ) else {
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
                guard shouldFollowSymlink(
                    at: entry,
                    reportedAs: logicalURL,
                    to: target,
                    visitedDirectories: &visitedDirectories
                ) else {
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

    /// Decides whether the walk descends into `target`, the directory `linkURL` resolves to,
    /// and says out loud what it decided.
    ///
    /// Writing *through* a symlink is the scaffolder's business and needs write access to the
    /// content directory first. Reading through one needs no privilege at all, and what it
    /// exposes is not the single file somebody named but every Markdown file under the target,
    /// transitively. Content directories are routinely populated from starter kits, theme
    /// repositories, submodules and contributor branches, and git records a symlink verbatim,
    /// so `content/leak -> /Users/someone` can arrive in a branch a maintainer builds. Two
    /// boundaries keep that from turning into published pages:
    ///
    /// - The target has to sit *inside* the project. The project root itself does not count:
    ///   `content/up -> ..` would otherwise publish the repository — its `README.md`, `docs/`,
    ///   `vendor/`, `node_modules/` — as pages.
    /// - The target may not be the output, static or templates directory, or anything under
    ///   one, however it was reached. Re-publishing the previous build, or publishing a
    ///   template as a page, is never what a link meant.
    ///
    /// The case the feature exists for — `content/posts -> ../shared-posts`, a sibling inside
    /// the project — passes both and needs no configuration to work.
    ///
    /// - Parameters:
    ///   - linkURL: The symlink itself, where it really sits on disk.
    ///   - logicalURL: Path the link is reported at, used for the printed line.
    ///   - target: `linkURL` with its symlinks resolved.
    ///   - visitedDirectories: Canonical paths already walked. The target is recorded here only
    ///     when it is about to be walked, so a refused link never shadows a later legitimate one.
    private func shouldFollowSymlink(
        at linkURL: URL,
        reportedAs logicalURL: URL,
        to target: URL,
        visitedDirectories: inout Set<String>
    ) -> Bool {
        let description = describeSymlink(at: linkURL, reportedAs: logicalURL, to: target)
        let targetPath = Self.canonicalPath(of: target)
        let projectRoot = Self.canonicalPath(of: URL(fileURLWithPath: projectPath))

        if targetPath == projectRoot {
            print("Skipping content symlink to the project root: \(description)")
            return false
        }
        guard targetPath.hasPrefix(projectRoot + "/") else {
            print("Skipping content symlink outside the project: \(description)")
            return false
        }
        if excludedDirectories.contains(where: { targetPath == $0 || targetPath.hasPrefix($0 + "/") }) {
            print("Skipping content symlink into a build directory: \(description)")
            return false
        }
        guard visitedDirectories.insert(targetPath).inserted else {
            print("Skipping content symlink already walked: \(description)")
            return false
        }
        print("Following content symlink: \(description)")
        return true
    }

    /// Directories the walk refuses to enter whichever link leads there.
    ///
    /// All three sit next to the content directory, so any link reaching the project root
    /// reaches them too. Both spellings of each are collected — as configured and with symlinks
    /// resolved — because the target is compared canonically and the project root itself may be
    /// reached through a link (`/var` is `/private/var` on macOS).
    private var excludedDirectories: Set<String> {
        let root = URL(fileURLWithPath: projectPath)
        let canonicalRoot = URL(fileURLWithPath: Self.canonicalPath(of: root))
        var excluded: Set<String> = []
        for name in [
            config.build.outputDirectory,
            config.build.staticDirectory,
            config.build.templatesDirectory
        ] {
            excluded.insert(root.appendingPathComponent(name).path)
            excluded.insert(canonicalRoot.appendingPathComponent(name).path)
            excluded.insert(Self.canonicalPath(of: root.appendingPathComponent(name)))
        }
        return excluded
    }

    /// Renders a link the way the site owner wrote it: `content/posts -> ../shared-posts`.
    ///
    /// The left side is the logical path relative to the project, so a link found behind
    /// another link still reads as a path under `content/`. The right side is the link's own
    /// destination text rather than the resolved path, because that is what is on disk to fix.
    private func describeSymlink(at linkURL: URL, reportedAs logicalURL: URL, to target: URL) -> String {
        let prefix = projectPath.hasSuffix("/") ? projectPath : projectPath + "/"
        var displayed = logicalURL.path
        if displayed.hasPrefix(prefix) {
            displayed = String(displayed.dropFirst(prefix.count))
        }
        let destination = (try? FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)) ?? target.path
        return "\(displayed) -> \(destination)"
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

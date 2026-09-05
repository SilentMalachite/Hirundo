import Foundation

/// Where a symlink-following walk of a content tree is allowed to go.
///
/// Reading through a symlink needs no privilege at all, and what it exposes is not the single
/// file somebody named but every file under the target, transitively. Content directories are
/// routinely populated from starter kits, theme repositories, submodules and contributor
/// branches, and git records a symlink verbatim, so `content/leak -> /Users/someone` can arrive
/// in a branch a maintainer builds. Two boundaries keep that from turning into published pages:
///
/// - The target has to sit *inside* ``root``. The root itself does not count: `content/up -> ..`
///   would otherwise publish the whole repository — its `README.md`, `docs/`, `vendor/`,
///   `node_modules/` — as pages.
/// - The target may not be one of ``excludedDirectoryNames`` under the root, or anything below
///   one, however it was reached. Re-publishing the previous build, or publishing a template as
///   a page, is never what a link meant.
///
/// The case the feature exists for — `content/posts -> ../shared-posts`, a sibling inside the
/// project — passes both and needs no configuration to work.
public struct SymlinkBoundary: Sendable, Equatable {
    /// Directory every followed target must sit strictly inside, or `nil` for "the directory
    /// being walked", which is the boundary that needs nothing configured.
    let root: String?
    /// Names, relative to ``root``, of directories the walk refuses to enter whichever link
    /// leads there.
    let excludedDirectoryNames: [String]

    /// Follows only links that stay inside the directory being walked.
    ///
    /// Nothing outside the walked tree is reachable, so no build directory can be, which is why
    /// this needs no exclusions.
    public static let walkedDirectory = SymlinkBoundary(root: nil, excludedDirectoryNames: [])

    /// Follows exactly what a build follows: strictly inside `root`, never into a build
    /// directory.
    /// - Parameters:
    ///   - root: Project root. A target equal to it, or outside it, is refused.
    ///   - names: Directory names, relative to `root`, never entered.
    public static func project(root: String, excludingDirectoriesNamed names: [String]) -> SymlinkBoundary {
        return SymlinkBoundary(root: root, excludedDirectoryNames: names)
    }
}

/// Walks a directory tree, descending into the directory symlinks ``boundary`` allows.
///
/// `FileManager`'s enumerator stops at a symlinked directory instead of walking into it, so a
/// site keeping part of its content elsewhere — `content/posts -> ../shared-posts` — built
/// without those files and said nothing. `ContentScaffolder` writes to the literal path the user
/// names, symlinks included, so `hirundo new` was creating files the build then ignored.
///
/// Shared by the build and the file watcher on purpose. Two traversals of the same tree that
/// disagree about symlinks is the failure this type exists to prevent: the build would include
/// content the watcher never notices changing, and `hirundo serve` would serve a page that
/// silently stops updating.
///
/// Every entry is reported at its *logical* path — the one under the walked root — never at the
/// resolved one. `SiteGenerator` derives the output URL from the path relative to the content
/// directory, so a file found through `content/shared` has to come back as
/// `content/shared/page.md` or its page moves.
struct SymlinkFollowingWalk {
    /// Where followed links may lead.
    let boundary: SymlinkBoundary
    /// Prints every follow/skip decision. The build says so out loud, because a walk that
    /// silently changes what it includes is the failure this traversal exists to fix; the
    /// watcher stays quiet, since it would only repeat what the build has already printed.
    let announcesDecisions: Bool

    /// Walks `root` and reports what it holds.
    ///
    /// - Parameters:
    ///   - root: Directory to walk. May itself be a symlink, which enumerates as completely
    ///     empty and is the same silent failure one level up.
    ///   - onEntry: Called for every entry that was not descended into, at its logical path.
    ///     Directories the enumerator yields are included, because filtering them out here
    ///     would cost a `stat` the callers already do their own way.
    ///   - onFollowedDirectory: Called with the *resolved* target of every symlink actually
    ///     followed. A watcher needs these: FSEvents watches inodes, not names, so a linked
    ///     directory delivers no events unless it is registered in its own right.
    /// - Throws: `ContentProcessorError.cannotEnumerateDirectory` when `root` cannot be
    ///   enumerated.
    func walk(
        _ root: URL,
        onEntry: (URL) -> Void,
        onFollowedDirectory: (URL) -> Void = { _ in }
    ) throws {
        var visitedDirectories: Set<String> = []
        let excluded = excludedPaths(under: root)

        // A walked directory that is itself a symlink enumerates as empty, so walk its target.
        if let target = Self.directorySymlinkTarget(of: root) {
            guard shouldFollow(
                link: root,
                reportedAs: root,
                to: target,
                under: root,
                excluding: excluded,
                visitedDirectories: &visitedDirectories
            ) else {
                return
            }
            onFollowedDirectory(target)
            walk(
                resolved: target,
                reportedAs: root,
                under: root,
                excluding: excluded,
                visitedDirectories: &visitedDirectories,
                onEntry: onEntry,
                onFollowedDirectory: onFollowedDirectory
            )
            return
        }
        // Recorded before the walk starts, so `content/here -> .` is recognised as a loop
        // rather than walked a second time.
        visitedDirectories.insert(Self.canonicalPath(of: root))

        // Unchanged from before directory symlinks were followed: same call, same options, so
        // a tree with no symlinks walks exactly as it always did — same files, same order.
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ContentProcessorError.cannotEnumerateDirectory(root.path)
        }

        while let fileURL = enumerator.nextObject() as? URL {
            // Checked before the caller's own filter: a linked directory rarely looks like the
            // files being collected, and the filter would drop it before it could be followed.
            if let target = Self.directorySymlinkTarget(of: fileURL),
               let logicalURL = Self.logicalURL(for: fileURL, enumeratedFrom: root) {
                guard shouldFollow(
                    link: fileURL,
                    reportedAs: logicalURL,
                    to: target,
                    under: root,
                    excluding: excluded,
                    visitedDirectories: &visitedDirectories
                ) else {
                    continue
                }
                onFollowedDirectory(target)
                walk(
                    resolved: target,
                    reportedAs: logicalURL,
                    under: root,
                    excluding: excluded,
                    visitedDirectories: &visitedDirectories,
                    onEntry: onEntry,
                    onFollowedDirectory: onFollowedDirectory
                )
                continue
            }

            onEntry(fileURL)
        }
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
    ///   - logicalDirectory: Path this directory is reported at, under the walked root.
    ///   - root: The directory the walk started from, used for the printed line.
    ///   - excluded: Directories never entered.
    ///   - visitedDirectories: Canonical paths already walked; a directory is entered once, so
    ///     `content/loop -> ..` and links pointing at each other terminate instead of looping.
    private func walk(
        resolved resolvedDirectory: URL,
        reportedAs logicalDirectory: URL,
        under root: URL,
        excluding excluded: Set<String>,
        visitedDirectories: inout Set<String>,
        onEntry: (URL) -> Void,
        onFollowedDirectory: (URL) -> Void
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
                guard shouldFollow(
                    link: entry,
                    reportedAs: logicalURL,
                    to: target,
                    under: root,
                    excluding: excluded,
                    visitedDirectories: &visitedDirectories
                ) else {
                    continue
                }
                onFollowedDirectory(target)
                walk(
                    resolved: target,
                    reportedAs: logicalURL,
                    under: root,
                    excluding: excluded,
                    visitedDirectories: &visitedDirectories,
                    onEntry: onEntry,
                    onFollowedDirectory: onFollowedDirectory
                )
                continue
            }

            if Self.isDirectory(entry) {
                guard visitedDirectories.insert(Self.canonicalPath(of: entry)).inserted else {
                    continue
                }
                walk(
                    resolved: entry,
                    reportedAs: logicalURL,
                    under: root,
                    excluding: excluded,
                    visitedDirectories: &visitedDirectories,
                    onEntry: onEntry,
                    onFollowedDirectory: onFollowedDirectory
                )
                continue
            }

            onEntry(logicalURL)
        }
    }

    /// Decides whether the walk descends into `target`, the directory `linkURL` resolves to,
    /// and says out loud what it decided.
    ///
    /// - Parameters:
    ///   - linkURL: The symlink itself, where it really sits on disk.
    ///   - logicalURL: Path the link is reported at, used for the printed line.
    ///   - target: `linkURL` with its symlinks resolved.
    ///   - root: The directory the walk started from; the boundary when none was configured.
    ///   - excluded: Directories never entered.
    ///   - visitedDirectories: Canonical paths already walked. The target is recorded here only
    ///     when it is about to be walked, so a refused link never shadows a later legitimate one.
    private func shouldFollow(
        link linkURL: URL,
        reportedAs logicalURL: URL,
        to target: URL,
        under root: URL,
        excluding excluded: Set<String>,
        visitedDirectories: inout Set<String>
    ) -> Bool {
        let boundaryRoot = boundary.root ?? root.path
        let description = describe(link: linkURL, reportedAs: logicalURL, to: target, under: boundaryRoot)
        let targetPath = Self.canonicalPath(of: target)
        let canonicalBoundary = Self.canonicalPath(of: URL(fileURLWithPath: boundaryRoot))

        if targetPath == canonicalBoundary {
            announce("Skipping content symlink to the project root: \(description)")
            return false
        }
        guard targetPath.hasPrefix(canonicalBoundary + "/") else {
            announce("Skipping content symlink outside the project: \(description)")
            return false
        }
        if excluded.contains(where: { targetPath == $0 || targetPath.hasPrefix($0 + "/") }) {
            announce("Skipping content symlink into a build directory: \(description)")
            return false
        }
        guard visitedDirectories.insert(targetPath).inserted else {
            announce("Skipping content symlink already walked: \(description)")
            return false
        }
        announce("Following content symlink: \(description)")
        return true
    }

    /// Directories the walk refuses to enter whichever link leads there.
    ///
    /// Both spellings of each are collected — as configured and with symlinks resolved —
    /// because the target is compared canonically and the boundary itself may be reached
    /// through a link (`/var` is `/private/var` on macOS).
    private func excludedPaths(under walkedRoot: URL) -> Set<String> {
        guard !boundary.excludedDirectoryNames.isEmpty else { return [] }
        let root = URL(fileURLWithPath: boundary.root ?? walkedRoot.path)
        let canonicalRoot = URL(fileURLWithPath: Self.canonicalPath(of: root))
        var excluded: Set<String> = []
        for name in boundary.excludedDirectoryNames {
            excluded.insert(root.appendingPathComponent(name).path)
            excluded.insert(canonicalRoot.appendingPathComponent(name).path)
            excluded.insert(Self.canonicalPath(of: root.appendingPathComponent(name)))
        }
        return excluded
    }

    private func announce(_ message: String) {
        guard announcesDecisions else { return }
        print(message)
    }

    /// Renders a link the way the site owner wrote it: `content/posts -> ../shared-posts`.
    ///
    /// The left side is the logical path relative to the boundary root, so a link found behind
    /// another link still reads as a path under `content/`. The right side is the link's own
    /// destination text rather than the resolved path, because that is what is on disk to fix.
    private func describe(link linkURL: URL, reportedAs logicalURL: URL, to target: URL, under boundaryRoot: String) -> String {
        let prefix = boundaryRoot.hasSuffix("/") ? boundaryRoot : boundaryRoot + "/"
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
}

import ArgumentParser
import Foundation
import HirundoCore

struct NewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Create new content",
        subcommands: [
            NewPostCommand.self,
            NewPageCommand.self
        ]
    )
}

/// Settings `hirundo new` needs from `config.yaml`, with the fallback used when there is
/// no config file to read.
///
/// Only `build.contentDirectory` and the two length limits matter here, so this resolves
/// to `Build`/`Limits` rather than a whole `HirundoConfig` — synthesising a `HirundoConfig`
/// would mean inventing a `site.title` and `site.url` that nothing reads.
struct NewContentContext {
    let projectRoot: URL
    let build: Build
    let limits: Limits

    /// Reads `config.yaml` from `projectRoot`, falling back to defaults when it is absent
    /// or unreadable. Matches how `hirundo clean` resolves its output directory: a missing
    /// config is not a reason to refuse to create a file.
    static func resolve(projectRoot: URL) -> NewContentContext {
        let configURL = projectRoot.appendingPathComponent("config.yaml")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return NewContentContext(
                projectRoot: projectRoot,
                build: Build.defaultBuild(),
                limits: Limits()
            )
        }
        guard let config = try? HirundoConfig.load(from: configURL) else {
            FileHandle.standardError.write(Data(
                "⚠️  Could not read config.yaml; using default directories.\n".utf8
            ))
            return NewContentContext(
                projectRoot: projectRoot,
                build: Build.defaultBuild(),
                limits: Limits()
            )
        }
        return NewContentContext(projectRoot: projectRoot, build: config.build, limits: config.limits)
    }
}

/// Prints the created path and, when asked, hands the file to the user's editor.
func reportCreatedContent(_ result: ContentScaffoldResult, openInEditor: Bool) {
    print("✅ Created \(result.relativePath)")
    if openInEditor {
        FileHandle.standardError.write(Data(
            "⚠️  --open is not wired up yet.\n".utf8
        ))
    }
}

struct NewPostCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "post",
        abstract: "Create a new blog post"
    )

    @Argument(help: "Post title")
    var title: String

    @Option(name: .long, help: "File name for the post, without the .md extension")
    var slug: String?

    @Option(name: .long, help: "Comma-separated categories")
    var categories: String?

    @Option(name: .long, help: "Comma-separated tags")
    var tags: String?

    @Option(name: .long, help: "Template file name (default: post.html)")
    var template: String?

    @Flag(name: .long, help: "Create as draft")
    var draft: Bool = false

    @Flag(name: .long, help: "Open in editor")
    var open: Bool = false

    @Flag(name: .long, help: "Show verbose error information")
    var verbose: Bool = false

    mutating func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let context = NewContentContext.resolve(projectRoot: cwd)

        do {
            let result = try ContentScaffolder().scaffold(
                in: context.projectRoot,
                build: context.build,
                limits: context.limits,
                kind: .post,
                options: ContentScaffoldOptions(
                    title: title,
                    slug: slug,
                    categories: ContentScaffoldOptions.parseList(categories),
                    tags: ContentScaffoldOptions.parseList(tags),
                    draft: draft,
                    template: template
                )
            )
            reportCreatedContent(result, openInEditor: open)
        } catch {
            handleError(error, context: "New post", verbose: verbose)
            throw ExitCode.failure
        }
    }
}

struct NewPageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "page",
        abstract: "Create a new page"
    )

    @Argument(help: "Page title")
    var title: String

    @Option(name: .long, help: "Path for the page, relative to the content directory")
    var path: String?

    @Option(name: .long, help: "Template file name (default: default.html)")
    var template: String?

    @Flag(name: .long, help: "Open in editor")
    var open: Bool = false

    @Flag(name: .long, help: "Show verbose error information")
    var verbose: Bool = false

    mutating func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let context = NewContentContext.resolve(projectRoot: cwd)

        do {
            let result = try ContentScaffolder().scaffold(
                in: context.projectRoot,
                build: context.build,
                limits: context.limits,
                kind: .page,
                options: ContentScaffoldOptions(
                    title: title,
                    path: path,
                    template: template
                )
            )
            reportCreatedContent(result, openInEditor: open)
        } catch {
            handleError(error, context: "New page", verbose: verbose)
            throw ExitCode.failure
        }
    }
}

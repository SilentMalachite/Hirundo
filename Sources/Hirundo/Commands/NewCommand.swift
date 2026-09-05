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

/// Warns on stderr when `NewContentContext.resolve` fell back to default directories
/// instead of the values in `config.yaml`.
///
/// Both fallbacks are worth saying out loud, and they say different things. No config file
/// usually means the command was run outside a site: the file is still created, but nothing
/// there will ever build, because `SiteGenerator` requires a `config.yaml`. A config that
/// exists but will not parse is a broken site, not a missing one. Either way the file has
/// been written, so this is a warning and the exit code stays 0.
func warnAboutConfigFallback(_ context: NewContentContext) {
    let message: String
    switch context.fallback {
    case nil:
        return
    case .missing:
        message = "No config.yaml here, so default directories were used. "
            + "Run this from a Hirundo site root, or create one with 'hirundo init'."
    case .unreadable:
        message = "Could not read config.yaml; using default directories. "
            + "Fix the config so the site builds with the settings you meant."
    }
    FileHandle.standardError.write(Data("⚠️  \(message)\n".utf8))
}

/// Prints the created path and, when asked, hands the file to the user's editor.
func reportCreatedContent(_ result: ContentScaffoldResult, openInEditor: Bool) {
    print("✅ Created \(result.relativePath)")
    if openInEditor {
        EditorLauncher.open(result.url)
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
        warnAboutConfigFallback(context)

        do {
            let result = try ContentScaffolder().scaffold(
                in: cwd,
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
        warnAboutConfigFallback(context)

        do {
            let result = try ContentScaffolder().scaffold(
                in: cwd,
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

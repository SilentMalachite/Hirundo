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

/// Warns on stderr when `NewContentContext.resolve` fell back to defaults because
/// `config.yaml` could not be read or parsed. A missing config stays silent — that is
/// normal, matching how `hirundo clean` resolves its output directory.
func warnIfConfigUnreadable(_ context: NewContentContext) {
    guard context.fallback == .unreadable else { return }
    FileHandle.standardError.write(Data(
        "⚠️  Could not read config.yaml; using default directories.\n".utf8
    ))
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
        warnIfConfigUnreadable(context)

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
        warnIfConfigUnreadable(context)

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

import ArgumentParser
import Foundation
import HirundoCore

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create a new Hirundo site"
    )
    
    @Argument(help: "Path where the new site will be created")
    var path: String = "."
    
    @Option(name: .long, help: "Site title")
    var title: String = "My Hirundo Site"
    
    @Flag(name: .long, help: "Include blog functionality")
    var blog: Bool = false
    
    @Flag(name: .long, help: "Force creation in non-empty directory")
    var force: Bool = false
    
    @Flag(name: .long, help: "Show verbose error information")
    var verbose: Bool = false
    
    mutating func run() throws {
        print("🚀 Creating new Hirundo site at: \(path)")
        print("📝 Title: \(title)")
        print("📚 Blog functionality: \(blog ? "enabled" : "disabled")")
        if force { print("💪 Force mode: enabled") }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        do {
            let destination = try InitDestinationResolver.resolve(path: path, currentDirectory: cwd)
            let result = try SiteScaffolder().scaffold(
                at: destination.url,
                options: SiteScaffoldOptions(title: title, includeBlog: blog, force: force)
            )
            for relative in result.createdRelativePaths.sorted() {
                print("✅ Created \(relative)")
            }
            for relative in result.modifiedRelativePaths.sorted() {
                print("📝 Updated \(relative)")
            }
            print("✅ Site created. Next:")
            if let changeDirectory = destination.changeDirectoryCommand {
                print("   \(changeDirectory)")
            }
            print("   hirundo serve")
        } catch {
            handleError(error, context: "Init", verbose: verbose)
            throw ExitCode.failure
        }
    }
}



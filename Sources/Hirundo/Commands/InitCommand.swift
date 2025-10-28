import ArgumentParser
import Foundation

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
        print("💪 Force mode: \(force ? "enabled" : "disabled")")
        
        let fileManager = FileManager.default
        let siteURL = URL(fileURLWithPath: path)
        
        // Check if directory exists and is not empty
        if fileManager.fileExists(atPath: path) {
            do {
                let contents = try fileManager.contentsOfDirectory(at: siteURL, includingPropertiesForKeys: nil)
                if !contents.isEmpty && !force {
                    let err = NSError(domain: "Init", code: 1, userInfo: [NSLocalizedDescriptionKey: "Directory is not empty. Use --force to override."])
                    handleError(err, context: "Init", verbose: verbose)
                    throw ExitCode.failure
                }
            } catch {
                handleError(error, context: "Init", verbose: verbose)
                throw ExitCode.failure
            }
        }
        
        print("✅ Init command executed successfully!")
        print("💡 Full implementation would create directory structure and files")
    }
}



import ArgumentParser
import HirundoCore
import Foundation

struct BuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the static site"
    )
    
    @Option(name: .long, help: "Configuration file path")
    var config: String = "config.yaml"
    
    @Option(name: .long, help: "Build environment (development/production)")
    var environment: String = "production"
    
    @Flag(name: .long, help: "Include draft posts")
    var drafts: Bool = false
    
    @Flag(name: .long, help: "Clean output before building")
    var clean: Bool = false
    
    @Flag(name: .long, help: "Continue building even if some files fail (error recovery mode)")
    var continueOnError: Bool = false
    
    mutating func run() throws {
        print("🔨 BUILD COMMAND IS RUNNING!")
        print("✅ ParsableCommand is working!")
        print("📁 Config: \(config)")
        print("🏗️ Environment: \(environment)")
        print("📄 Include drafts: \(drafts)")
        print("🧹 Clean: \(clean)")
        
        // For now, just test that the command works
        let currentDirectory = FileManager.default.currentDirectoryPath
        print("📁 Current directory: \(currentDirectory)")
        
        // Test SiteGenerator initialization
        do {
            print("🔧 Initializing SiteGenerator...")
            _ = try SiteGenerator(projectPath: currentDirectory)
            print("✅ SiteGenerator initialized successfully!")
        } catch {
            print("❌ Failed to initialize SiteGenerator:")
            print("Error: \(error)")
            handleError(error, context: "SiteGenerator initialization")
            throw ExitCode.failure
        }
    }
}

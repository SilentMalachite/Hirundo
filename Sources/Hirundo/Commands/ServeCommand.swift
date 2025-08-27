import ArgumentParser
import HirundoCore
import Foundation

struct ServeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start development server with live reload"
    )
    
    @Option(name: .long, help: "Server port")
    var port: Int = 8080
    
    @Option(name: .long, help: "Server host")
    var host: String = "localhost"
    
    @Flag(name: .long, help: "Disable live reload")
    var noReload: Bool = false
    
    @Flag(name: .long, help: "Don't open browser")
    var noBrowser: Bool = false
    
    mutating func run() throws {
        print("🌐 Starting development server...")
        print("🏠 Host: \(host)")
        print("🔌 Port: \(port)")
        print("🔄 Live reload: \(!noReload ? "enabled" : "disabled")")
        print("🌍 Open browser: \(!noBrowser ? "yes" : "no")")
        
        let currentDirectory = FileManager.default.currentDirectoryPath
        
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
        
        print("✅ Serve command executed successfully!")
        print("💡 Full implementation would start DevelopmentServer")
    }
}

import ArgumentParser
import HirundoCore
import Foundation
#if os(macOS)
import AppKit
#endif

struct ServeCommand: AsyncParsableCommand {
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
    
    mutating func run() async throws {
        print("🌐 Starting development server…")
        print("🏠 Host: \(host)")
        print("🔌 Port: \(port)")
        print("🔄 Live reload: \(!noReload ? "enabled" : "disabled")")
        print("🌍 Open browser: \(!noBrowser ? "yes" : "no")")
        
        let currentDirectory = FileManager.default.currentDirectoryPath
        
        do {
            // Load configuration to respect CORS, WS auth, and output directory
            let configURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent("config.yaml")
            let config = try HirundoConfig.load(from: configURL)
            
            let server = DevelopmentServer(
                projectPath: currentDirectory,
                port: port,
                host: host,
                liveReload: !noReload,
                fileManager: .default,
                outputDirectory: config.build.outputDirectory
            )
            try await server.start()
            print("✅ Development server is running at http://\(host):\(port)")
            
            #if os(macOS)
            if !noBrowser, let url = URL(string: "http://\(host):\(port)") {
                _ = NSWorkspace.shared.open(url)
            }
            #endif
            
            print("🔚 Press Ctrl+C to stop")
            while true {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } catch {
            handleError(error, context: "Serve")
            throw ExitCode.failure
        }
    }
}


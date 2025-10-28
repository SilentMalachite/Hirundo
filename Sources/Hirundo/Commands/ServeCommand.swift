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
    
    @Flag(name: .long, help: "Show verbose error information")
    var verbose: Bool = false
    
    mutating func run() async throws {
        print("🌐 Starting development server…")
        print("🏠 Host: \(host)")
        print("🔌 Port: \(port)")
        let liveReloadStatus = !noReload ? "enabled" : "disabled"
        print("🔄 Live reload: \(liveReloadStatus)")
        let openBrowserStatus = !noBrowser ? "yes" : "no"
        print("🌍 Open browser: \(openBrowserStatus)")
        
        let currentDirectory = FileManager.default.currentDirectoryPath
        
        var server: DevelopmentServer?
        do {
            // Load configuration to respect CORS, WS auth, and output directory
            let configURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent("config.yaml")
            let config = try HirundoConfig.load(from: configURL)
            
            let s = DevelopmentServer(
                projectPath: currentDirectory,
                port: port,
                host: host,
                liveReload: !noReload,
                fileManager: .default,
                outputDirectory: config.build.outputDirectory
            )
            server = s
            try await s.start()
            print("✅ Development server is running at http://\(host):\(port)")
            
            #if os(macOS)
            if !noBrowser, let url = URL(string: "http://\(host):\(port)") {
                _ = NSWorkspace.shared.open(url)
            }
            #endif
            
            print("🔚 Press Ctrl+C to stop")
            try await withTaskCancellationHandler {
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            } onCancel: {
                print("⏹️ Stopping server…")
                if let server = server {
                    Task {
                        await server.stop()
                        print("🛑 Server stopped")
                    }
                }
            }
            // If the loop exited without cancellation, ensure server is stopped
            if let server = server {
                await server.stop()
            }
        } catch {
            // Ensure server is stopped even on error
            if let server = server {
                await server.stop()
            }
            handleError(error, context: "Serve", verbose: verbose)
            throw ExitCode.failure
        }
    }
}


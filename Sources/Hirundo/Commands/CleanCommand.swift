import ArgumentParser
import Foundation
import HirundoCore

struct CleanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Clean output directory and caches"
    )
    
    @Flag(name: .long, help: "Also clean asset cache")
    var cache: Bool = false
    
    @Flag(name: .long, help: "Skip confirmation")
    var force: Bool = false
    
    mutating func run() throws {
        print("🧹 Cleaning...")
        print("🗂️ Clean cache: \(cache ? "yes" : "no")")
        print("💪 Force mode: \(force ? "yes" : "no")")
        
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        // Determine output directory from config if available
        let defaultOutputDir = "_site"
        let configURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent("config.yaml")
        let outputDirName: String
        if fileManager.fileExists(atPath: configURL.path) {
            if let config = try? HirundoConfig.load(from: configURL) {
                outputDirName = config.build.outputDirectory
            } else {
                outputDirName = defaultOutputDir
            }
        } else {
            outputDirName = defaultOutputDir
        }
        let outputURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent(outputDirName)
        let cacheURL = URL(fileURLWithPath: currentDirectory).appendingPathComponent(".hirundo-cache")
        
        if !force {
            print("⚠️  This would delete:")
            if fileManager.fileExists(atPath: outputURL.path) {
                print("  - Output directory: \(outputURL.path)")
            }
            if cache && fileManager.fileExists(atPath: cacheURL.path) {
                print("  - Cache directory: \(cacheURL.path)")
            }
            print("💡 Use --force to actually perform the cleanup")
        } else {
            // Clean output directory
            if fileManager.fileExists(atPath: outputURL.path) {
                do {
                    try fileManager.removeItem(at: outputURL)
                    print("✅ Removed output directory")
                } catch {
                    print("❌ Failed to remove output directory: \(error)")
                }
            }
            
            // Clean cache if requested
            if cache && fileManager.fileExists(atPath: cacheURL.path) {
                do {
                    try fileManager.removeItem(at: cacheURL)
                    print("✅ Removed cache directory")
                } catch {
                    print("❌ Failed to remove cache directory: \(error)")
                }
            }
        }
        
        print("✅ Clean command executed successfully!")
    }
}

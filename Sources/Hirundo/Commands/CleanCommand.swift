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
    
    @Flag(name: .long, help: "Actually delete; without this the command only lists what would be removed")
    var force: Bool = false
    
    @Flag(name: .long, help: "Show verbose error information")
    var verbose: Bool = false
    
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
                print("  - Everything inside the output directory: \(outputURL.path)")
            }
            if cache && fileManager.fileExists(atPath: cacheURL.path) {
                print("  - Cache directory: \(cacheURL.path)")
            }
            print("💡 Use --force to actually perform the cleanup")
            print("✅ Clean command executed successfully!")
            return
        }

        var failed = false

        // The contents, not the directory. `hirundo build --clean` has emptied it rather than
        // removing it since the confinement landed, and this used to `removeItem` the root — so
        // the same word meant two things, and on a site whose `_site` is a symbolic link to a
        // build volume, `hirundo clean --force` took the link out and the next build wrote to a
        // fresh directory beside it. Both commands go through `emptyOutputDirectory` now.
        if fileManager.fileExists(atPath: outputURL.path) {
            do {
                try SiteFileManager.emptyOutputDirectory(at: outputURL)
                print("✅ Emptied output directory")
            } catch {
                handleError(error, context: "Clean", verbose: verbose)
                failed = true
            }
        }

        // The cache is this tool's own directory rather than a configured root, so it goes.
        if cache && fileManager.fileExists(atPath: cacheURL.path) {
            do {
                try fileManager.removeItem(at: cacheURL)
                print("✅ Removed cache directory")
            } catch {
                handleError(error, context: "Clean", verbose: verbose)
                failed = true
            }
        }

        // Reporting success after printing an error, and exiting 0 while doing it, is how a
        // failed clean in a script looked like a clean one.
        guard !failed else {
            throw ExitCode.failure
        }
        print("✅ Clean command executed successfully!")
    }
}

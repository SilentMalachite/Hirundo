import ArgumentParser
import HirundoCore
import Foundation

struct BuildCommand: AsyncParsableCommand {
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
    
    mutating func run() async throws {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        
        // Resolve projectPath from config option if possible
        var projectPath = cwd
        let configURL = URL(fileURLWithPath: config, relativeTo: URL(fileURLWithPath: cwd)).standardized
        if fm.fileExists(atPath: configURL.path) {
            projectPath = configURL.deletingLastPathComponent().path
            if configURL.lastPathComponent != "config.yaml" {
                print("⚠️ Custom config filenames are not yet supported; expecting 'config.yaml'. Using \(configURL.path) only if named 'config.yaml'.")
            }
        }

        do {
            let generator = try SiteGenerator(projectPath: projectPath)
            print("🔨 Building site (env=\(environment), drafts=\(drafts), clean=\(clean))…")
            if continueOnError {
                let result = try await generator.buildWithRecovery(clean: clean, includeDrafts: drafts)
                if !result.success {
                    print("❌ Build completed with errors. Success: \(result.successCount), Failed: \(result.failCount)")
                    for detail in result.errors.prefix(10) {
                        print("- [\(detail.stage)] \(detail.file): \(detail.error)")
                    }
                    throw ExitCode.failure
                }
            } else {
                try await generator.build(clean: clean, includeDrafts: drafts)
            }
            print("✅ Build finished successfully")
        } catch {
            handleError(error, context: "Build")
            throw ExitCode.failure
        }
    }
}

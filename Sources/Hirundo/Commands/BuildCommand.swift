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
        
        // Resolve configuration URL if provided (supports arbitrary filename)
        let configURL = URL(fileURLWithPath: config, relativeTo: URL(fileURLWithPath: cwd)).standardized

        do {
            let generator: SiteGenerator
            if fm.fileExists(atPath: configURL.path) {
                generator = try SiteGenerator(configURL: configURL)
            } else {
                generator = try SiteGenerator(projectPath: cwd)
            }
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

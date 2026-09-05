import ArgumentParser
import Foundation
import HirundoCore

struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Check the configuration file for errors and ignored keys"
    )

    @Option(name: .long, help: "Configuration file path")
    var config: String = "config.yaml"

    @Flag(name: .long, help: "Show verbose error information")
    var verbose: Bool = false

    mutating func run() throws {
        let cwd = FileManager.default.currentDirectoryPath
        let configURL = URL(fileURLWithPath: config, relativeTo: URL(fileURLWithPath: cwd)).standardized

        let report: ConfigDiagnostics.Report
        do {
            report = try ConfigDiagnostics.inspect(fileAt: configURL)
        } catch {
            // Deliberately not `handleError`: its stock suggestion for a configuration error is
            // "Run 'hirundo validate'", which is the command already running.
            // Missing, a directory, or unreadable — none of which is a problem with the
            // configuration's *content*, so none of them should be called invalid.
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: configURL.path, isDirectory: &isDirectory)
            let readable = exists
                && !isDirectory.boolValue
                && FileManager.default.isReadableFile(atPath: configURL.path)
            eprint("❌ \(configURL.path) \(readable ? "is not valid" : "could not be read")")
            eprint("")
            eprint("📍 \(error.localizedDescription)")
            if verbose {
                eprint("")
                eprint("Full error: \(error)")
            }
            throw ExitCode.failure
        }

        // "Valid" is claimed only when nothing was silently dropped. A file that parses but has
        // keys Hirundo ignores is exactly the situation this command exists to surface, so it
        // must not be reported with a plain checkmark.
        // The count goes in the headline so that stdout alone still says something is wrong —
        // the warnings themselves go to stderr, and the two streams are often separated.
        if report.warnings.isEmpty {
            print("✅ \(configURL.path) is valid")
        } else {
            print("⚠️  \(configURL.path) parses, but \(report.warnings.count) key(s) are ignored")
        }
        print("   Site: \(report.config.site.title) <\(report.config.site.url)>")
        print("   Content: \(report.config.build.contentDirectory) → \(report.config.build.outputDirectory)")

        // Warnings do not fail the command: an unrecognized key is legal YAML that Hirundo
        // simply does not act on.
        guard !report.warnings.isEmpty else { return }
        // stdout is fully buffered when redirected, so without this the warnings below would
        // appear above the summary they belong to.
        fflush(stdout)
        eprint("")
        for warning in report.warnings {
            eprint("⚠️  \(warning)")
        }
    }
}

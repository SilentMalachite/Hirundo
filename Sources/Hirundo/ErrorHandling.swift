import Foundation
import HirundoCore

/// Write to standard error with newline
@inline(__always)
private func eprint(_ message: String) {
    if let data = (message + "\n").data(using: .utf8) {
        try? FileHandle.standardError.write(contentsOf: data)
    }
}

/// Error handling helper function for CLI commands
func handleError(_ error: Error, context: String, verbose: Bool = false) {
    if let hirundoError = error as? HirundoErrorInfo {
        eprint(hirundoError.userMessage)
        if verbose {
            eprint("\nDebug Details:")
            eprint("  Error Code: \(hirundoError.category.rawValue)-\(hirundoError.code)")
            eprint("  Details: \(hirundoError.details)")
            if !hirundoError.debugInfo.isEmpty {
                eprint("  Debug Info: \(hirundoError.debugInfo)")
            }
        }
    } else if let configError = error as? ConfigError {
        let hirundoError = configError.toHirundoError()
        eprint(hirundoError.userMessage)
        eprint("\n📍 Specific issue: \(configError.localizedDescription)")
    } else if let markdownError = error as? MarkdownError {
        let hirundoError = markdownError.toHirundoError()
        eprint(hirundoError.userMessage)
        eprint("\n📍 Specific issue: \(markdownError.localizedDescription)")
    } else if let templateError = error as? TemplateError {
        let hirundoError = templateError.toHirundoError()
        eprint(hirundoError.userMessage)
        eprint("\n📍 Specific issue: \(templateError.localizedDescription)")
    } else if let buildError = error as? BuildError {
        let hirundoError = buildError.toHirundoError()
        eprint(hirundoError.userMessage)
        eprint("\n📍 Specific issue: \(buildError.localizedDescription)")
    } else {
        // Generic error handling
        eprint("\n❌ \(context) failed")
        eprint("\n📍 Error: \(error.localizedDescription)")
        eprint("\n💡 Suggestion: Check the error message above for details")
        if verbose {
            eprint("\nFull error: \(error)")
        }
    }
}
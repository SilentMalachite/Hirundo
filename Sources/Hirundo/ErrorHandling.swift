import Foundation
import HirundoCore

/// Error handling helper function for CLI commands
func handleError(_ error: Error, context: String, verbose: Bool = false) {
    if let hirundoError = error as? HirundoErrorInfo {
        print(hirundoError.userMessage)
        if verbose {
            print("\nDebug Details:")
            print("  Error Code: \(hirundoError.category.rawValue)-\(hirundoError.code)")
            print("  Details: \(hirundoError.details)")
            if !hirundoError.debugInfo.isEmpty {
                print("  Debug Info: \(hirundoError.debugInfo)")
            }
        }
    } else if let configError = error as? ConfigError {
        let hirundoError = configError.toHirundoError()
        print(hirundoError.userMessage)
        print("\n📍 Specific issue: \(configError.localizedDescription)")
    } else if let markdownError = error as? MarkdownError {
        let hirundoError = markdownError.toHirundoError()
        print(hirundoError.userMessage)
        print("\n📍 Specific issue: \(markdownError.localizedDescription)")
    } else if let templateError = error as? TemplateError {
        let hirundoError = templateError.toHirundoError()
        print(hirundoError.userMessage)
        print("\n📍 Specific issue: \(templateError.localizedDescription)")
    } else if let buildError = error as? BuildError {
        let hirundoError = buildError.toHirundoError()
        print(hirundoError.userMessage)
        print("\n📍 Specific issue: \(buildError.localizedDescription)")
    } else {
        // Generic error handling
        print("\n❌ \(context) failed")
        print("\n📍 Error: \(error.localizedDescription)")
        print("\n💡 Suggestion: Check the error message above for details")
        if verbose {
            print("\nFull error: \(error)")
        }
    }
}
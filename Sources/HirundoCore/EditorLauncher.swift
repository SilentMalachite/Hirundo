import Foundation

/// Opens a file in the user's configured editor.
///
/// The command comes from the environment, so it is attacker-influenced in exactly the
/// way `SecurityUtilities.validateAndSanitizeEditorCommand` was written to handle: every
/// candidate goes through that allow-list before anything is executed, and the process is
/// spawned directly rather than through a shell, so there is no metacharacter to abuse.
public enum EditorLauncher {

    /// The outcome of looking for an editor in the environment.
    ///
    /// `notConfigured` and `rejected` are kept apart because they are different problems:
    /// the first means the user has no editor set, the second means they have one that the
    /// allow-list refuses — `code --wait` or `/opt/homebrew/bin/emacs`, say. Telling the
    /// second user to "set $EDITOR" would be wrong and confusing, so `rejected` carries the
    /// variable and the value that was refused.
    public enum EditorResolution: Sendable, Equatable {
        /// A validated command name, ready to run.
        case resolved(String)
        /// Neither `$VISUAL` nor `$EDITOR` holds a non-blank value.
        case notConfigured
        /// A value was set but did not pass validation.
        case rejected(variable: String, value: String)
    }

    /// Picks an editor command from the environment.
    ///
    /// `$VISUAL` wins over `$EDITOR` (the long-standing convention: `$VISUAL` names a
    /// full-screen editor, `$EDITOR` may be a line editor). A `$VISUAL` that fails
    /// validation falls through to `$EDITOR` rather than giving up, so one bad value does
    /// not shadow a usable one.
    /// - Parameter environment: Environment to read. Injectable for tests.
    /// - Returns: A validated command name, or `nil` when nothing usable is configured.
    ///   Use ``resolveEditor(environment:)`` when the caller needs to tell "nothing set"
    ///   apart from "set but refused".
    public static func resolveEditorCommand(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if case .resolved(let command) = resolveEditor(environment: environment) {
            return command
        }
        return nil
    }

    /// Picks an editor command from the environment, reporting why when there is none.
    ///
    /// When every candidate is refused, the reported one is the first that was set —
    /// `$VISUAL` if both are — because that is the value that would have been used.
    /// - Parameter environment: Environment to read. Injectable for tests.
    /// - Returns: The validated command, or the reason there is not one.
    public static func resolveEditor(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> EditorResolution {
        var firstRejected: EditorResolution?
        for key in ["VISUAL", "EDITOR"] {
            guard let raw = environment[key] else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let validated = SecurityUtilities.validateAndSanitizeEditorCommand(raw) {
                return .resolved(validated)
            }
            if firstRejected == nil {
                firstRejected = .rejected(variable: key, value: trimmed)
            }
        }
        return firstRejected ?? .notConfigured
    }

    /// Opens `fileURL` in the configured editor and waits for it to exit.
    ///
    /// Failure is reported on stderr and nothing else: the file has already been written,
    /// and reporting that as a failure would misrepresent what happened.
    /// - Parameter fileURL: File to open.
    /// - Returns: `true` when an editor ran to completion.
    @discardableResult
    public static func open(_ fileURL: URL) -> Bool {
        let command: String
        switch resolveEditor() {
        case .resolved(let resolved):
            command = resolved
        case .notConfigured:
            warn("Set $EDITOR to a supported editor to use --open.")
            return false
        case .rejected(let variable, let value):
            warn("$\(variable) is set to '\(displayable(value))', which --open will not "
                + "run. Use a plain editor name from the allow-list (vim, nvim, nano, "
                + "emacs, code, subl, vi, open) with no arguments.")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // Arguments are passed as a list, never joined into a shell command line.
        process.arguments = [command, fileURL.path]
        // Terminal editors need the real terminal, so the standard streams are inherited.

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            warn("Could not start '\(command)': \(error.localizedDescription)")
            return false
        }
    }

    private static func warn(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("⚠️  \(message)\n".utf8))
    }

    /// Makes an environment value safe to quote back at the user: the value is
    /// attacker-influenced, so line breaks (which could forge a second warning line) and
    /// other control characters are stripped, and a long value is cut short.
    private static func displayable(_ value: String) -> String {
        let cleaned = String(String.UnicodeScalarView(
            value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        ))
        guard cleaned.count > 80 else { return cleaned }
        return cleaned.prefix(80) + "…"
    }
}

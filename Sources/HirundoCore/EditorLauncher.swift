import Foundation

/// Opens a file in the user's configured editor.
///
/// The command comes from the environment, so it is attacker-influenced in exactly the
/// way `SecurityUtilities.validateAndSanitizeEditorCommand` was written to handle: every
/// candidate goes through that allow-list before anything is executed, and the process is
/// spawned directly rather than through a shell, so there is no metacharacter to abuse.
public enum EditorLauncher {

    /// Picks an editor command from the environment.
    ///
    /// `$VISUAL` wins over `$EDITOR` (the long-standing convention: `$VISUAL` names a
    /// full-screen editor, `$EDITOR` may be a line editor). A `$VISUAL` that fails
    /// validation falls through to `$EDITOR` rather than giving up, so one bad value does
    /// not shadow a usable one.
    /// - Parameter environment: Environment to read. Injectable for tests.
    /// - Returns: A validated command name, or `nil` when nothing usable is configured.
    public static func resolveEditorCommand(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        for key in ["VISUAL", "EDITOR"] {
            guard let raw = environment[key],
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            if let validated = SecurityUtilities.validateAndSanitizeEditorCommand(raw) {
                return validated
            }
        }
        return nil
    }

    /// Opens `fileURL` in the configured editor and waits for it to exit.
    ///
    /// Failure is reported on stderr and nothing else: the file has already been written,
    /// and reporting that as a failure would misrepresent what happened.
    /// - Parameter fileURL: File to open.
    /// - Returns: `true` when an editor ran to completion.
    @discardableResult
    public static func open(_ fileURL: URL) -> Bool {
        guard let command = resolveEditorCommand() else {
            warn("Set $EDITOR to a supported editor to use --open.")
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
}

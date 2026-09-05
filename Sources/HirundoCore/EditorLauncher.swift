import Foundation

/// Opens a file in the user's configured editor.
///
/// The command comes from the environment, so it is attacker-influenced in exactly the
/// way `SecurityUtilities.validateAndSanitizeEditorCommand` was written to handle: every
/// candidate goes through that allow-list before anything is executed, and the process is
/// spawned directly rather than through a shell, so there is no metacharacter to abuse.
///
/// What runs is always what was validated: a value naming an absolute path is spawned as
/// that path, and only a bare command name is resolved on `PATH`.
public enum EditorLauncher {

    /// A validated editor, together with the environment value it was validated from.
    ///
    /// Both halves are needed at launch time. `SecurityUtilities` returns only the command
    /// name, deliberately, but the value it checked may have been an absolute path — and
    /// running the name through `PATH` would then execute a different file from the one
    /// that was validated. Keeping `rawValue` alongside lets ``invocation`` spawn exactly
    /// what was approved.
    public struct ResolvedEditor: Sendable, Equatable {
        /// The allow-listed command name returned by validation.
        public let command: String
        /// The trimmed `$VISUAL`/`$EDITOR` value the command was validated from.
        public let rawValue: String

        /// Creates a resolved editor.
        public init(command: String, rawValue: String) {
            self.command = command
            self.rawValue = rawValue
        }

        /// How the editor should be spawned.
        var invocation: Invocation {
            guard rawValue.hasPrefix("/") else {
                // A bare name is a request for a `PATH` lookup: that is what the user
                // asked for, and there is no specific file to pin it to.
                return .pathLookup(command)
            }
            guard URL(fileURLWithPath: rawValue).lastPathComponent == command else {
                return .inconsistent
            }
            return .executable(rawValue)
        }
    }

    /// How a resolved editor is turned into a process.
    enum Invocation: Sendable, Equatable {
        /// Run this exact executable: the user named an absolute path, and that path is
        /// what validation checked.
        case executable(String)
        /// Resolve this command name on `PATH`: the user named a bare command.
        case pathLookup(String)
        /// The value is an absolute path whose last component is not the validated command
        /// name. The two must never disagree, so nothing is run.
        case inconsistent
    }

    /// The outcome of looking for an editor in the environment.
    ///
    /// `notConfigured` and `rejected` are kept apart because they are different problems:
    /// the first means the user has no editor set, the second means they have one that the
    /// allow-list refuses — `code --wait` or `/opt/homebrew/bin/emacs`, say. Telling the
    /// second user to "set $EDITOR" would be wrong and confusing, so `rejected` carries the
    /// variable and the value that was refused.
    public enum EditorResolution: Sendable, Equatable {
        /// A validated editor, ready to run.
        case resolved(ResolvedEditor)
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
        if case .resolved(let editor) = resolveEditor(environment: environment) {
            return editor.command
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
                return .resolved(ResolvedEditor(command: validated, rawValue: trimmed))
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
        let editor: ResolvedEditor
        switch resolveEditor() {
        case .resolved(let resolved):
            editor = resolved
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
        // Arguments are passed as a list, never joined into a shell command line.
        switch editor.invocation {
        case .executable(let path):
            // The user named one specific executable, and that exact file is what
            // validation checked. Running it through `/usr/bin/env` would throw the path
            // away and re-resolve the bare name on `PATH`, where a writable directory
            // earlier in the search order would win — executing something other than the
            // file that was approved.
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = [fileURL.path]
        case .pathLookup(let command):
            // A bare command name *is* a request for `PATH` resolution, so `env` does
            // exactly what the user asked for.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command, fileURL.path]
        case .inconsistent:
            warn("$VISUAL/$EDITOR is set to '\(displayable(editor.rawValue))', which does "
                + "not name the validated command '\(editor.command)'. Refusing to run it.")
            return false
        }
        // Terminal editors need the real terminal, so the standard streams are inherited.

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            warn("Could not start '\(displayable(editor.rawValue))': \(error.localizedDescription)")
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

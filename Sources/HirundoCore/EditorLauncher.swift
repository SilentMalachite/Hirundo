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

        // Arguments are passed as a list, never joined into a shell command line.
        let executable: String
        let arguments: [String]
        switch editor.invocation {
        case .executable(let path):
            // The user named one specific executable, and that exact file is what
            // validation checked. Running it through `/usr/bin/env` would throw the path
            // away and re-resolve the bare name on `PATH`, where a writable directory
            // earlier in the search order would win — executing something other than the
            // file that was approved.
            executable = path
            arguments = [path, fileURL.path]
        case .pathLookup(let command):
            // A bare command name *is* a request for `PATH` resolution, so `env` does
            // exactly what the user asked for.
            executable = "/usr/bin/env"
            arguments = [executable, command, fileURL.path]
        case .inconsistent:
            warn("$VISUAL/$EDITOR is set to '\(displayable(editor.rawValue))', which does "
                + "not name the validated command '\(editor.command)'. Refusing to run it.")
            return false
        }
        // Terminal editors need the real terminal, so the standard streams are inherited.

        let pid: pid_t
        switch spawn(executable: executable, arguments: arguments) {
        case .spawned(let spawned):
            pid = spawned
        case .failed(let code):
            warn("Could not start '\(displayable(editor.rawValue))': \(String(cString: strerror(code)))")
            return false
        }

        // Inherited streams alone leave the editor unable to drive the terminal: the child
        // is in a process group of its own, which is not the terminal's *foreground* group,
        // so the first `tcsetattr` it makes to enter raw mode stops it with SIGTTOU and the
        // command appears to hang. Lend it the foreground for the duration; the terminal is
        // handed back on every exit path, including a throw. When there is no controlling
        // terminal — a pipe, a file, CI — this does nothing and the launch is as it was.
        let plan = TerminalForeground.plan(forChild: pid)
        return TerminalForeground.withForeground(givenTo: plan) {
            wait(for: pid, holding: plan)
        }
    }

    /// Spawns `executable` with `arguments`, in a process group of its own.
    ///
    /// `posix_spawn` rather than `Process`, because Foundation reaps its own children: the
    /// only supported way to wait for one is `waitUntilExit()`, which waits without
    /// `WUNTRACED`, and calling `waitpid` alongside it races with Foundation's reaper. Waiting
    /// without `WUNTRACED` is what made Ctrl-Z an unrecoverable hang — the editor stops, the
    /// wait never returns, the hand-back never runs, and the terminal is left owned by a
    /// stopped process group with nothing reading it. Owning the wait is what makes job
    /// control possible.
    ///
    /// It also closes a race: `Process.processIdentifier` is only readable after `run()` has
    /// returned, by which time the child may already have stopped itself. `POSIX_SPAWN_SETPGROUP`
    /// with a group of 0 puts the child in a group of its own id before it execs, so the pid
    /// and the group are both known the instant the call returns.
    ///
    /// - Parameters:
    ///   - executable: Absolute path of the file to execute. Never a shell.
    ///   - arguments: Full argument vector, `argv[0]` included.
    /// - Returns: The child's process id, or the error number the spawn failed with.
    private static func spawn(executable: String, arguments: [String]) -> SpawnOutcome {
        var attributes: posix_spawnattr_t?
        // The `posix_spawnattr_*` and `posix_spawn_file_actions_*` families return the error
        // number directly and leave `errno` alone, so reporting `errno` here would surface
        // whatever number some unrelated earlier call happened to leave behind.
        let attributesCode = posix_spawnattr_init(&attributes)
        guard attributesCode == 0 else { return .failed(attributesCode) }
        defer { posix_spawnattr_destroy(&attributes) }

        // A group of its own, so the terminal can be lent to the editor alone and a Ctrl-Z
        // stops the editor rather than us.
        posix_spawnattr_setpgroup(&attributes, 0)
        // An inherited mask that blocks SIGTTOU would turn the editor's first `tcsetattr`
        // into an `EIO` failure instead of the stop the hand-over is there to prevent, so
        // the child starts with an empty one whatever this process happens to be blocking.
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        posix_spawnattr_setsigmask(&attributes, &emptyMask)
        // A disposition of `SIG_IGN` survives an `exec` where a handler does not, so an
        // editor started from a process that ignores, say, SIGINT would ignore it too and
        // Ctrl-C would do nothing. Resetting every signal to its default is what `Process`
        // did before this code owned the spawn.
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        posix_spawnattr_setflags(
            &attributes,
            Int16(
                POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK
                    | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT
            )
        )

        // `POSIX_SPAWN_CLOEXEC_DEFAULT` closes every descriptor that no file action names,
        // so the editor sees the three it needs and nothing else — no cache file, no socket,
        // no log handle this process happens to have open. A `dup2` of a descriptor onto
        // itself is the documented way to say "keep this one": it copies nothing and only
        // exempts the descriptor from the close. Without these three the editor would start
        // with no terminal at all, which is why `Process` issues exactly the same ones.
        var fileActions: posix_spawn_file_actions_t?
        let actionsCode = posix_spawn_file_actions_init(&fileActions)
        guard actionsCode == 0 else { return .failed(actionsCode) }
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            let dupCode = posix_spawn_file_actions_adddup2(&fileActions, descriptor, descriptor)
            guard dupCode == 0 else { return .failed(dupCode) }
        }

        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        argv.append(nil)
        defer { for pointer in argv { free(pointer) } }

        var pid: pid_t = 0
        let code = posix_spawn(&pid, executable, &fileActions, &attributes, argv, environ)
        guard code == 0 else { return .failed(code) }
        return .spawned(pid)
    }

    /// What ``spawn(executable:arguments:)`` came back with.
    private enum SpawnOutcome {
        case spawned(pid_t)
        /// The error number reported by whichever of `posix_spawn`, `posix_spawnattr_*` or
        /// `posix_spawn_file_actions_*` failed. All of them return it directly rather than
        /// through the global `errno`.
        case failed(Int32)
    }

    /// Waits for the editor, handling a Ctrl-Z the way a shell does.
    ///
    /// `WUNTRACED` is the whole point: without it the wait blocks forever on a stopped child.
    /// When the editor stops, the terminal it owns has nothing reading it, so we take it back,
    /// stop ourselves — which is what makes the user's shell report the job as stopped and
    /// hand back the prompt — and, when the shell continues us with `fg`, lend the terminal
    /// out again, continue the editor, and go back to waiting.
    ///
    /// Where there is no shell to stop for — hirundo as the session leader, under `ssh -t` or
    /// `docker run -it` — the stop is discarded and the same two lines simply resume the
    /// editor instead. See the comment on the `raise` below.
    ///
    /// - Parameters:
    ///   - pid: The child to wait for.
    ///   - plan: The hand-over in force, which names the group to give the terminal back to.
    ///   - descriptor: The terminal. Defaults to stdin, as the hand-over does.
    /// - Returns: `true` when the editor exited with status 0.
    private static func wait(
        for pid: pid_t,
        holding plan: ForegroundPlan,
        on descriptor: Int32 = STDIN_FILENO
    ) -> Bool {
        while true {
            var status: Int32 = 0
            guard waitpid(pid, &status, WUNTRACED) >= 0 else {
                if errno == EINTR { continue }
                // Nothing left to wait for, and nothing sensible to report.
                return false
            }
            guard isStopped(status) else {
                return exitedCleanly(status)
            }

            guard case .handOver(let childGroup, let previousGroup) = plan else {
                // We never lent the terminal out, so the editor cannot be the foreground
                // group and a keyboard stop cannot have reached it. Something else stopped
                // it; continue it rather than wait on a process nothing will resume.
                kill(pid, SIGCONT)
                continue
            }

            // Take the terminal back before stopping, so the shell finds it where it left it
            // rather than owned by a stopped process group.
            TerminalForeground.setForegroundGroup(previousGroup, on: descriptor)
            // `SIGTSTP` rather than `SIGSTOP`, and the discard is the reason. POSIX throws a
            // keyboard stop away when the process group is orphaned — no member has a parent
            // in another group of the same session, so no shell is left to continue it —
            // precisely so nothing can stop itself where nothing can resume it. That is our
            // situation whenever hirundo is the session leader: `ssh -t host 'hirundo new
            // … --open'`, `docker run -it`, any shell without job control. `SIGSTOP` there
            // would be the unrecoverable hang this whole hand-over exists to remove, because
            // it cannot be discarded. When the signal is discarded the code below simply runs
            // on: the terminal goes back to the editor, the editor is continued, and the wait
            // resumes — which is the right answer when there is no job control to return to.
            raise(SIGTSTP)
            // Resumed by `fg`: the shell has given us the terminal back. Pass it on to the
            // editor, continue it, and carry on waiting.
            TerminalForeground.setForegroundGroup(childGroup, on: descriptor)
            kill(-childGroup, SIGCONT)
        }
    }

    /// Whether a wait status describes a process that has stopped rather than ended.
    ///
    /// `WIFSTOPPED` and friends are C macros, so they are not imported into Swift. Darwin
    /// spells a stop as the low byte being `0177`.
    ///
    /// Internal rather than private so the replacement for the macro can be tested against
    /// the statuses `waitpid` actually produces: getting it wrong turns a stopped editor into
    /// a reported failure, or an exit into a stop that is waited on forever.
    static func isStopped(_ status: Int32) -> Bool {
        return (status & 0xFF) == 0x7F
    }

    /// Whether a wait status describes a normal exit with code 0. A process killed by a
    /// signal has not edited anything successfully either.
    ///
    /// Internal for the same reason as ``isStopped(_:)``.
    static func exitedCleanly(_ status: Int32) -> Bool {
        return (status & 0x7F) == 0 && ((status >> 8) & 0xFF) == 0
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

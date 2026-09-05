import Foundation

/// What to do about the controlling terminal's foreground process group while a child
/// process runs.
///
/// Kept as a value so the decision is a pure function of four observable numbers and can
/// be tested without a terminal — the execution below is the only part that needs one.
enum ForegroundPlan: Equatable {
    /// Leave the terminal alone. There is no controlling terminal, we are not the job
    /// that currently owns it, or the child is already in the foreground group.
    case leaveAlone
    /// Make `childGroup` the foreground process group, and put `restoringTo` back once
    /// the child is done.
    case handOver(childGroup: pid_t, restoringTo: pid_t)
}

/// Hands the controlling terminal's foreground process group to a child for the duration
/// of its run, and takes it back afterwards.
///
/// Inheriting the standard streams is not enough to run a full-screen terminal editor.
/// Foundation's `Process` puts its child in a process group of its own, so the child is
/// not the terminal's *foreground* group — and the first `tcsetattr` an editor makes to
/// enter raw mode then raises `SIGTTOU`, whose default action is to stop the process. The
/// editor never draws, `waitUntilExit()` never returns, and the command looks like a hang.
///
/// Measured on macOS under an isolated pty: with the streams merely inherited, both a
/// `tcsetattr` probe and `/usr/bin/vi` reached state `T`, stopped by signal 22 (SIGTTOU).
/// With the hand-over below, `vi` drew its screen, accepted `:q!` and exited 0.
enum TerminalForeground {

    /// Decides whether the terminal's foreground group has to be handed to a child.
    ///
    /// Only the job that currently *owns* the terminal may pass it on: when `hirundo` is
    /// itself a background job, `foregroundGroup` belongs to somebody else and taking it
    /// would disturb whatever is actually running in front of the user.
    /// - Parameters:
    ///   - isTerminal: Whether the descriptor refers to a terminal at all.
    ///   - foregroundGroup: The terminal's current foreground group, or a non-positive
    ///     value when the descriptor is not our controlling terminal.
    ///   - ownGroup: The calling process's own process group.
    ///   - childGroup: The process group the child actually landed in, or a non-positive
    ///     value when it could not be read (the child has already gone).
    /// - Returns: The plan to execute.
    static func plan(
        isTerminal: Bool,
        foregroundGroup: pid_t,
        ownGroup: pid_t,
        childGroup: pid_t
    ) -> ForegroundPlan {
        // No terminal to hand over: stdin is a pipe or a file, as under CI, a test
        // harness, or `hirundo new --open < /dev/null`. Nothing to do, and touching the
        // terminal machinery here is what would turn a working case into a failing one.
        guard isTerminal else { return .leaveAlone }
        // A non-positive foreground group means the descriptor is not our controlling
        // terminal, so there is no foreground group of ours to give away.
        guard foregroundGroup > 0, ownGroup > 0 else { return .leaveAlone }
        // Not our terminal to lend: we are a background job.
        guard foregroundGroup == ownGroup else { return .leaveAlone }
        // The child is already gone, or already the foreground group (which is what a
        // `Process` that left the child in our own group would look like).
        guard childGroup > 0, childGroup != foregroundGroup else { return .leaveAlone }
        return .handOver(childGroup: childGroup, restoringTo: foregroundGroup)
    }

    /// Reads the terminal and the child's placement, and decides.
    /// - Parameters:
    ///   - pid: The child's process identifier.
    ///   - descriptor: The descriptor to treat as the terminal. Defaults to stdin, the
    ///     one an editor will read its keystrokes from.
    static func plan(forChild pid: pid_t, descriptor: Int32 = STDIN_FILENO) -> ForegroundPlan {
        plan(
            isTerminal: isatty(descriptor) != 0,
            foregroundGroup: tcgetpgrp(descriptor),
            ownGroup: getpgrp(),
            childGroup: getpgid(pid)
        )
    }

    /// Runs `body` with `plan` in force, restoring the terminal afterwards.
    ///
    /// The restore is in a `defer`, so it happens on every exit path out of `body`,
    /// including a thrown error. `.leaveAlone` touches nothing at all.
    @discardableResult
    static func withForeground<T>(
        givenTo plan: ForegroundPlan,
        on descriptor: Int32 = STDIN_FILENO,
        do body: () throws -> T
    ) rethrows -> T {
        guard case .handOver(let childGroup, let previousGroup) = plan else {
            return try body()
        }

        // `tcsetpgrp` from a process that is not currently the foreground group raises
        // SIGTTOU on the caller — which is precisely what the hand-back does, since by
        // then the child owns the terminal. Blocking the job-control signals across the
        // whole span keeps both calls from stopping us. The mask is per-thread, and both
        // calls happen on this thread.
        var jobControlSignals = sigset_t()
        sigemptyset(&jobControlSignals)
        sigaddset(&jobControlSignals, SIGTTOU)
        sigaddset(&jobControlSignals, SIGTTIN)
        var previousMask = sigset_t()
        let masked = pthread_sigmask(SIG_BLOCK, &jobControlSignals, &previousMask) == 0
        defer { if masked { pthread_sigmask(SIG_SETMASK, &previousMask, nil) } }

        guard tcsetpgrp(descriptor, childGroup) == 0 else {
            // The child exited before we got here, or the terminal went away. Either way
            // nothing changed, so there is nothing to put back.
            return try body()
        }
        defer {
            // Every exit path, including a throw out of `body`: the user's shell must get
            // its terminal back even when something above went wrong.
            tcsetpgrp(descriptor, previousGroup)
        }

        // Closes the race in reading the child's pid only after it has been spawned: in
        // the window before the hand-over the child may already have tried `tcsetattr`
        // and been stopped by SIGTTOU. `SIGCONT` resumes it, and the interrupted call is
        // restarted — this time in the foreground, so it succeeds. Sending SIGCONT to a
        // process that never stopped does nothing, so this is safe unconditionally.
        kill(-childGroup, SIGCONT)

        return try body()
    }
}

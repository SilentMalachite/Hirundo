import XCTest
@testable import HirundoCore

/// Covers the decision to hand the terminal's foreground process group to a child.
///
/// Nothing here spawns a process or touches a real terminal: the decision is a pure
/// function of four observable numbers, which is exactly why it was split out. The
/// behaviour that needs a controlling terminal was verified separately under an isolated
/// pty and is not something to assert against whatever terminal a test runner happens to
/// have.
final class TerminalForegroundTests: XCTestCase {

    // MARK: - When the hand-over must not happen

    func testLeavesTheTerminalAloneWhenStdinIsNotATerminal() {
        // CI, `hirundo new --open < /dev/null`, a test harness. Reaching for terminal
        // control here is what would break a case that works today.
        XCTAssertEqual(
            TerminalForeground.plan(
                isTerminal: false, foregroundGroup: 500, ownGroup: 500, childGroup: 700
            ),
            .leaveAlone
        )
    }

    func testLeavesTheTerminalAloneWhenThereIsNoForegroundGroup() {
        // `tcgetpgrp` reports -1 when the descriptor is not our controlling terminal.
        XCTAssertEqual(
            TerminalForeground.plan(
                isTerminal: true, foregroundGroup: -1, ownGroup: 500, childGroup: 700
            ),
            .leaveAlone
        )
    }

    func testLeavesTheTerminalAloneWhenWeAreABackgroundJob() {
        // The foreground group belongs to somebody else; taking it would disturb whatever
        // is actually in front of the user.
        XCTAssertEqual(
            TerminalForeground.plan(
                isTerminal: true, foregroundGroup: 400, ownGroup: 500, childGroup: 700
            ),
            .leaveAlone
        )
    }

    func testLeavesTheTerminalAloneWhenTheChildIsAlreadyInTheForegroundGroup() {
        // What a `Process` that left the child in our own group would look like: there is
        // nothing to hand over, and the editor can already drive the terminal.
        XCTAssertEqual(
            TerminalForeground.plan(
                isTerminal: true, foregroundGroup: 500, ownGroup: 500, childGroup: 500
            ),
            .leaveAlone
        )
    }

    func testLeavesTheTerminalAloneWhenTheChildsGroupCannotBeRead() {
        // `getpgid` reports -1 once the child has gone.
        XCTAssertEqual(
            TerminalForeground.plan(
                isTerminal: true, foregroundGroup: 500, ownGroup: 500, childGroup: -1
            ),
            .leaveAlone
        )
    }

    // MARK: - When it must

    func testHandsOverToAChildInItsOwnGroupAndRemembersWhatToRestore() {
        XCTAssertEqual(
            TerminalForeground.plan(
                isTerminal: true, foregroundGroup: 500, ownGroup: 500, childGroup: 700
            ),
            .handOver(childGroup: 700, restoringTo: 500)
        )
    }

    // MARK: - Restore bookkeeping

    func testLeaveAloneStillRunsTheBody() {
        var ran = false
        TerminalForeground.withForeground(givenTo: .leaveAlone) { ran = true }

        XCTAssertTrue(ran, "A no-op plan must not skip the work it wraps")
    }

    func testLeaveAloneReturnsTheBodysValue() {
        XCTAssertEqual(TerminalForeground.withForeground(givenTo: .leaveAlone) { 42 }, 42)
    }

    func testLeaveAlonePropagatesAThrownError() {
        struct Boom: Error {}

        XCTAssertThrowsError(
            try TerminalForeground.withForeground(givenTo: .leaveAlone) { throw Boom() }
        )
    }

    func testARealHandOverIsNeverPlannedForTheTestProcessItself() {
        // The suite must not fight the runner's terminal. Whatever stdin the runner has,
        // planning for our own pid can only ever come out `.leaveAlone`, because a
        // process is always already in its own process group.
        XCTAssertEqual(TerminalForeground.plan(forChild: getpid()), .leaveAlone)
    }
}

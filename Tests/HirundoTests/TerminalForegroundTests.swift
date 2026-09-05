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

    // MARK: - The hand-over branch, without a terminal

    /// A `.handOver` on a descriptor that is not a terminal takes the fallback path: the
    /// `tcsetpgrp` fails, nothing was changed, and `body` still runs. That is the shape of
    /// every case where the child has already gone or the terminal has — and it must never
    /// turn into "the work silently did not happen".
    ///
    /// A descriptor of our own opening, never the runner's stdin, so this cannot touch a real
    /// terminal whatever the runner was started from.
    func testHandOverStillRunsTheBodyWhenTheDescriptorIsNotATerminal() throws {
        let descriptor = try nonTerminalDescriptor()
        defer { close(descriptor) }
        var ran = false

        TerminalForeground.withForeground(
            givenTo: .handOver(childGroup: 700, restoringTo: 500),
            on: descriptor
        ) { ran = true }

        XCTAssertTrue(ran, "the hand-over must not swallow the work it wraps")
    }

    func testHandOverReturnsTheBodysValueWhenTheDescriptorIsNotATerminal() throws {
        let descriptor = try nonTerminalDescriptor()
        defer { close(descriptor) }

        XCTAssertEqual(
            TerminalForeground.withForeground(
                givenTo: .handOver(childGroup: 700, restoringTo: 500),
                on: descriptor
            ) { 42 },
            42
        )
    }

    func testHandOverPropagatesAThrownError() throws {
        struct Boom: Error {}
        let descriptor = try nonTerminalDescriptor()
        defer { close(descriptor) }

        XCTAssertThrowsError(
            try TerminalForeground.withForeground(
                givenTo: .handOver(childGroup: 700, restoringTo: 500),
                on: descriptor
            ) { throw Boom() }
        )
    }

    // MARK: - Mask bookkeeping

    /// The job-control signals have to be blocked *around* `body`, not just around the two
    /// `tcsetpgrp` calls: the wait inside reclaims and re-lends the terminal itself when the
    /// editor is stopped, and an unblocked SIGTTOU there would stop us instead.
    func testHandOverBlocksTheJobControlSignalsForTheDurationOfTheBody() throws {
        let descriptor = try nonTerminalDescriptor()
        defer { close(descriptor) }

        var blockedInside = (ttou: false, ttin: false)
        TerminalForeground.withForeground(
            givenTo: .handOver(childGroup: 700, restoringTo: 500),
            on: descriptor
        ) {
            blockedInside = (Self.isBlocked(SIGTTOU), Self.isBlocked(SIGTTIN))
        }

        XCTAssertTrue(blockedInside.ttou, "SIGTTOU must be blocked while the child holds the terminal")
        XCTAssertTrue(blockedInside.ttin, "SIGTTIN must be blocked while the child holds the terminal")
    }

    /// `.leaveAlone` is the case where nothing at all should be touched — including the mask.
    func testLeaveAloneDoesNotBlockAnything() {
        var blockedInside = true
        TerminalForeground.withForeground(givenTo: .leaveAlone) {
            blockedInside = Self.isBlocked(SIGTTOU)
        }

        XCTAssertFalse(blockedInside, "a no-op plan must not touch the signal mask")
    }

    func testHandOverRestoresTheSignalMaskAfterwards() throws {
        let descriptor = try nonTerminalDescriptor()
        defer { close(descriptor) }
        let before = Self.isBlocked(SIGTTOU)

        TerminalForeground.withForeground(
            givenTo: .handOver(childGroup: 700, restoringTo: 500),
            on: descriptor
        ) {}

        XCTAssertEqual(Self.isBlocked(SIGTTOU), before, "the mask must be put back")
    }

    /// The restore is a `defer`, so a throw out of `body` must not leave the process with the
    /// job-control signals blocked for the rest of its life.
    func testHandOverRestoresTheSignalMaskWhenTheBodyThrows() throws {
        struct Boom: Error {}
        let descriptor = try nonTerminalDescriptor()
        defer { close(descriptor) }
        let before = Self.isBlocked(SIGTTOU)

        XCTAssertThrowsError(
            try TerminalForeground.withForeground(
                givenTo: .handOver(childGroup: 700, restoringTo: 500),
                on: descriptor
            ) { throw Boom() }
        )

        XCTAssertEqual(Self.isBlocked(SIGTTOU), before, "a throw must still put the mask back")
    }

    // MARK: - Reclaiming the terminal mid-wait

    /// What the wait calls when the editor is stopped by a Ctrl-Z. On a descriptor that is not
    /// a terminal it can only fail, and it has to say so rather than stop the caller: with
    /// SIGTTOU unblocked, this call from a process that is not the foreground group is exactly
    /// what would stop us.
    func testSettingTheForegroundGroupReportsFailureOnANonTerminal() throws {
        let descriptor = try nonTerminalDescriptor()
        defer { close(descriptor) }
        let before = Self.isBlocked(SIGTTOU)

        XCTAssertFalse(TerminalForeground.setForegroundGroup(500, on: descriptor))
        XCTAssertEqual(Self.isBlocked(SIGTTOU), before, "the mask must be put back")
    }

    // MARK: - Helpers

    /// A descriptor that is definitely not a terminal, so a hand-over takes its fallback path
    /// without the suite ever touching the runner's own terminal.
    private func nonTerminalDescriptor(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Int32 {
        let descriptor = open("/dev/null", O_RDONLY)
        try XCTSkipIf(descriptor < 0, "cannot open /dev/null", file: file, line: line)
        XCTAssertEqual(isatty(descriptor), 0, "the fixture must not be a terminal", file: file, line: line)
        return descriptor
    }

    private static func isBlocked(_ signal: Int32) -> Bool {
        var mask = sigset_t()
        guard pthread_sigmask(SIG_BLOCK, nil, &mask) == 0 else { return false }
        return sigismember(&mask, signal) == 1
    }
}

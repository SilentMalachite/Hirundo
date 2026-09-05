import XCTest
@testable import HirundoCore

/// A fake build closure target: counts invocations, can be told to sleep for a fixed duration
/// before returning (to simulate a real build's duration), and can be reconfigured mid-test to
/// switch between succeeding, reporting a failure, and throwing.
private final class FakeBuilder: @unchecked Sendable {
    private let callCountBox = ThreadSafeBox<Int>(0)
    private let delayBox: ThreadSafeBox<TimeInterval>
    private let resultBox: ThreadSafeBox<() throws -> BuildResult>

    init(
        delay: TimeInterval = 0,
        result: @escaping () throws -> BuildResult = {
            BuildResult(success: true, errors: [], successCount: 1, failCount: 0)
        }
    ) {
        self.delayBox = ThreadSafeBox(delay)
        self.resultBox = ThreadSafeBox(result)
    }

    var callCount: Int { callCountBox.get() }

    func setResult(_ result: @escaping () throws -> BuildResult) {
        resultBox.set(result)
    }

    func build() async throws -> BuildResult {
        callCountBox.modify { $0 += 1 }
        let delay = delayBox.get()
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return try resultBox.get()()
    }
}

private enum FakeBuildError: Error, Equatable {
    case boom
}

final class RebuildCoordinatorTests: XCTestCase {

    func testRequestRebuild_whenCalledOnce_buildsOnceAndSignalsSuccess() async {
        let builder = FakeBuilder()
        let successCount = ThreadSafeBox<Int>(0)
        let failureCount = ThreadSafeBox<Int>(0)
        let coordinator = RebuildCoordinator(
            build: { try await builder.build() },
            onSuccess: { successCount.modify { $0 += 1 } },
            onFailure: { _ in failureCount.modify { $0 += 1 } }
        )

        await coordinator.requestRebuild()
        await coordinator.waitForQuiescence()

        XCTAssertEqual(builder.callCount, 1)
        XCTAssertEqual(successCount.get(), 1)
        XCTAssertEqual(failureCount.get(), 0)
    }

    func testRequestRebuild_whenCalledTenTimesInBurst_convergesToAtMostTwoBuilds() async {
        // A 0.3s build is slow enough that all ten requests land while the first build is
        // still running, so they must all fold into a single pending flag rather than each
        // starting their own build.
        //
        // The contract is "at most two": the build already running, plus one follow-up covering
        // everything that arrived while it ran. Whether the burst costs one build or two depends
        // on when the run loop's task is first scheduled relative to the remaining nine calls —
        // one build is the better outcome, not a regression, so asserting an exact 2 would pin
        // down a scheduling artifact rather than the guarantee. Ten uncoalesced builds still
        // fail this: every request would start its own build, each `FakeBuilder.build()` bumps
        // the counter before it sleeps, and 0.3s is far longer than ten task spawns take.
        let builder = FakeBuilder(delay: 0.3)
        let coordinator = RebuildCoordinator(
            build: { try await builder.build() },
            onSuccess: {},
            onFailure: { _ in }
        )

        for _ in 0..<10 {
            await coordinator.requestRebuild()
        }
        await coordinator.waitForQuiescence()

        XCTAssertGreaterThanOrEqual(builder.callCount, 1)
        XCTAssertLessThanOrEqual(builder.callCount, 2)
    }

    func testRequestRebuild_whenBuildResultReportsFailure_signalsFailureWithRebuildIncomplete() async {
        let builder = FakeBuilder(result: {
            BuildResult(
                success: false,
                errors: [
                    BuildErrorDetail(file: "broken.md", stage: .parsing, error: FakeBuildError.boom, recoverable: true)
                ],
                successCount: 4,
                failCount: 1
            )
        })
        let successCount = ThreadSafeBox<Int>(0)
        let failures = ThreadSafeBox<[Error]>([])
        let coordinator = RebuildCoordinator(
            build: { try await builder.build() },
            onSuccess: { successCount.modify { $0 += 1 } },
            onFailure: { error in failures.modify { $0.append(error) } }
        )

        await coordinator.requestRebuild()
        await coordinator.waitForQuiescence()

        XCTAssertEqual(successCount.get(), 0)
        XCTAssertEqual(failures.get().count, 1)
        guard let incomplete = failures.get().first as? RebuildIncomplete else {
            XCTFail("expected onFailure to receive a RebuildIncomplete")
            return
        }
        XCTAssertEqual(incomplete.successCount, 4)
        XCTAssertEqual(incomplete.failCount, 1)
    }

    func testRequestRebuild_whenBuildThrows_passesThrownErrorToOnFailure() async {
        let builder = FakeBuilder(result: { throw FakeBuildError.boom })
        let successCount = ThreadSafeBox<Int>(0)
        let failures = ThreadSafeBox<[Error]>([])
        let coordinator = RebuildCoordinator(
            build: { try await builder.build() },
            onSuccess: { successCount.modify { $0 += 1 } },
            onFailure: { error in failures.modify { $0.append(error) } }
        )

        await coordinator.requestRebuild()
        await coordinator.waitForQuiescence()

        XCTAssertEqual(successCount.get(), 0)
        XCTAssertEqual(failures.get().count, 1)
        XCTAssertEqual(failures.get().first as? FakeBuildError, .boom)
    }

    func testRequestRebuild_afterPriorFailure_succeedsOnNextRequest() async {
        let builder = FakeBuilder(result: {
            BuildResult(success: false, errors: [], successCount: 0, failCount: 1)
        })
        let successCount = ThreadSafeBox<Int>(0)
        let failureCount = ThreadSafeBox<Int>(0)
        let coordinator = RebuildCoordinator(
            build: { try await builder.build() },
            onSuccess: { successCount.modify { $0 += 1 } },
            onFailure: { _ in failureCount.modify { $0 += 1 } }
        )

        await coordinator.requestRebuild()
        await coordinator.waitForQuiescence()
        XCTAssertEqual(failureCount.get(), 1)
        XCTAssertEqual(successCount.get(), 0)

        builder.setResult { BuildResult(success: true, errors: [], successCount: 1, failCount: 0) }
        await coordinator.requestRebuild()
        await coordinator.waitForQuiescence()

        XCTAssertEqual(successCount.get(), 1)
        XCTAssertEqual(failureCount.get(), 1)
    }

    func testWaitForQuiescence_whenNoBuildInFlight_returnsImmediately() async {
        let builder = FakeBuilder()
        let coordinator = RebuildCoordinator(
            build: { try await builder.build() },
            onSuccess: {},
            onFailure: { _ in }
        )

        let returned = self.expectation(description: "waitForQuiescence returns with no build running")
        Task {
            await coordinator.waitForQuiescence()
            returned.fulfill()
        }
        await fulfillment(of: [returned], timeout: 10.0)

        XCTAssertEqual(builder.callCount, 0)
    }

    func testWaitForQuiescence_whenCalledFromTwoTasksConcurrently_bothResume() async {
        let builder = FakeBuilder(delay: 0.3)
        let coordinator = RebuildCoordinator(
            build: { try await builder.build() },
            onSuccess: {},
            onFailure: { _ in }
        )

        await coordinator.requestRebuild()

        let waiterA = self.expectation(description: "first waiter resumes")
        let waiterB = self.expectation(description: "second waiter resumes")
        Task {
            await coordinator.waitForQuiescence()
            waiterA.fulfill()
        }
        Task {
            await coordinator.waitForQuiescence()
            waiterB.fulfill()
        }

        await fulfillment(of: [waiterA, waiterB], timeout: 10.0)
    }
}

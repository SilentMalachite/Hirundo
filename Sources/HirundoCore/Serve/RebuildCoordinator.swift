import Foundation

/// Raised when a build ran to completion but reported failures.
///
/// `RebuildCoordinator` treats `BuildResult.success == false` the same as a thrown error from
/// the build closure: either way, the previous (correctly rendered) page must stay on disk and
/// the browser must not be told to reload into something broken. Wrapping the failure details
/// from a `BuildResult` in a real `Error` lets the single `onFailure` callback handle both cases
/// — a reported failure and an actual `throw` — uniformly.
public struct RebuildIncomplete: Error, LocalizedError {
    public let successCount: Int
    public let failCount: Int
    public let messages: [String]

    public var errorDescription: String? {
        // `failCount` also covers whole-site steps (static assets, sitemap, …), not just files,
        // so the two counts are reported separately rather than summed into a file total.
        "Build finished with \(failCount) failure(s), \(successCount) file(s) succeeded: " +
            messages.joined(separator: "; ")
    }
}

/// Serializes `hirundo serve`'s rebuilds so that a burst of file-system events collapses into
/// at most two actual builds: the one already running, plus a single follow-up that picks up
/// everything that arrived while it ran.
///
/// The state deliberately holds no queue of pending requests — only whether a rebuild is owed
/// (`pending`) and whether one is currently running (`isBuilding`). Which files changed does not
/// matter here; `SiteGenerator.buildWithRecovery` always rebuilds the whole site. Actor
/// reentrancy is what makes the two-flag design correct: `requestRebuild()` never awaits, so it
/// runs to completion synchronously whenever the actor picks it up — including while `runLoop()`
/// is suspended inside `build()` — and is guaranteed to observe an up-to-date `isBuilding` before
/// deciding whether to fold into `pending` or start a fresh loop.
public actor RebuildCoordinator {
    private let build: @Sendable () async throws -> BuildResult
    private let onSuccess: @Sendable () async -> Void
    private let onFailure: @Sendable (Error) async -> Void

    private var isBuilding = false
    private var pending = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(
        build: @escaping @Sendable () async throws -> BuildResult,
        onSuccess: @escaping @Sendable () async -> Void,
        onFailure: @escaping @Sendable (Error) async -> Void
    ) {
        self.build = build
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }

    /// Starts a rebuild if none is currently running; otherwise marks one as owed and returns
    /// immediately. Never waits for a build to finish — callers that need that guarantee (e.g.
    /// the shutdown sequence) use ``waitForQuiescence()`` instead.
    public func requestRebuild() {
        guard !isBuilding else {
            pending = true
            return
        }
        isBuilding = true
        Task { await self.runLoop() }
    }

    /// Suspends until every build owed as of this call — including one already in flight and,
    /// if `pending` is set, the follow-up it triggers — has finished. Returns immediately if no
    /// build is running. Multiple simultaneous callers are all resumed once the run loop drains.
    public func waitForQuiescence() async {
        guard isBuilding else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Runs builds back-to-back until no further rebuild is owed, then wakes anyone waiting on
    /// ``waitForQuiescence()``. `pending` is cleared before each run (not after) so that a
    /// `requestRebuild()` arriving while this loop is inside `runOnce()` is recorded as owing
    /// another pass rather than being lost.
    private func runLoop() async {
        repeat {
            pending = false
            await runOnce()
        } while pending
        isBuilding = false
        let resuming = waiters
        waiters = []
        for waiter in resuming {
            waiter.resume()
        }
    }

    private func runOnce() async {
        do {
            let result = try await build()
            if result.success {
                await onSuccess()
            } else {
                // A reported failure is not a thrown error, but it must be treated as one: the
                // caller (the CLI's serve command) must not tell the browser to reload.
                let messages = result.errors.prefix(10).map { "[\($0.stage)] \($0.file): \($0.error)" }
                let incomplete = RebuildIncomplete(
                    successCount: result.successCount,
                    failCount: result.failCount,
                    messages: messages
                )
                await onFailure(incomplete)
            }
        } catch {
            await onFailure(error)
        }
    }
}

//
//  LiveSessionHarness.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import ValistreamCore

/// Drives a live ``ValidationSession`` deterministically over a ``ManualClock`` and a
/// ``ScriptedStreamFetcher``, with zero wall-clock waiting (research §8/§9).
///
/// The session's `now` and `sleep` are both pinned to the manual clock, so advancing the clock is
/// the only thing that moves time. Tests start the session, then `step` it one cadence interval at
/// a time — each step parks the monitor on the clock, advances it, and waits for the resulting
/// refresh to land before returning.
///
/// Example:
/// ```swift
/// let harness = LiveSessionHarness(input: mediaURL)
/// harness.fetcher.timeline(mediaURL, [.init(at: .zero, reply: .body(window0))])
/// await harness.start()
/// await harness.step(by: 6, refreshing: mediaURL)
/// await harness.abortAndFinish()
/// ```
actor LiveSessionHarness {
    // MARK: - Lets & Vars

    let clock = ManualClock()

    let fetcher: ScriptedStreamFetcher

    let session: ValidationSession

    private var runTask: Task<Void, Never>?

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)



    // MARK: - Lifecycle

    init(input: URL, config: SessionConfig = SessionConfig(nonInteractive: true)) {
        let clock = clock
        let epoch = epoch
        let fetcher = ScriptedStreamFetcher(clock: clock)
        self.fetcher = fetcher
        self.session = ValidationSession(
            inputURL: input,
            config: config,
            fetcher: fetcher,
            id: "test-session",
            now: { epoch.addingTimeInterval(clock.elapsedSeconds) },
            sleep: { try await clock.sleep(for: $0) }
        )
    }



    // MARK: - Internal

    /// Starts the session's `run()` loop in an unstructured task the harness owns.
    func start() {
        runTask = Task { [session] in await session.run() }
    }

    /// Suspends until at least `count` monitor loops are parked on the clock (or a safety cap is hit).
    func waitForSleepers(_ count: Int) async {
        var spins = 0
        while clock.sleeperCount < count, spins < 100_000 {
            await Task.yield()
            spins += 1
        }
    }

    /// Advances one cadence interval: parks, advances the clock by `seconds`, waits for the
    /// monitored `url` to be refetched, then waits for the monitor to re-park on the clock — which
    /// only happens after the refresh has been fully validated and its findings recorded. On return
    /// the session's state reflects the completed refresh.
    func step(by seconds: Int, refreshing url: URL, sleepers: Int = 1) async {
        await waitForSleepers(sleepers)
        let before = fetcher.fetchCount(for: url)
        clock.advance(by: .seconds(seconds))
        var spins = 0
        while fetcher.fetchCount(for: url) <= before, spins < 100_000 {
            await Task.yield()
            spins += 1
        }
        // The monitor re-parks only after recording continuity/staleness for this refresh.
        await waitForSleepers(sleepers)
    }

    /// Advances the clock without waiting for a refresh — for driving a monitor past its time limit,
    /// where the next wake breaks the loop instead of fetching.
    func advance(by seconds: Int, sleepers: Int = 1) async {
        await waitForSleepers(sleepers)
        clock.advance(by: .seconds(seconds))
        await Task.yield()
    }

    /// Requests a graceful abort (Ctrl-C) and waits for the session to unwind.
    func abortAndFinish() async {
        await session.abort()
        runTask?.cancel()
        await runTask?.value
    }

    /// Waits for the session to finish on its own (endlist or time limit).
    func finish() async {
        await runTask?.value
    }
}

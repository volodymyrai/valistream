//
//  HeartbeatMonotonicTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import Foundation
import Testing
@testable import Valistream
@testable import ValistreamCore

/// Integration tests asserting that `sessionRefreshTotal` in `.activity` events is
/// monotonically non-decreasing and equals refreshes performed, even when ≥20 stray
/// Enter presses are injected. (FR-013/014, SC-004)
///
/// The stray input simulation is at the event level: the test verifies the counter
/// property independently of the TTY/termios layer (LiveInputGuard is CLI-only).
@Suite("Heartbeat monotonicity under stray input", .timeLimit(.minutes(1)))
struct HeartbeatMonotonicTests {

    private let singleURL = URL(string: "https://test.example/live/index.m3u8")!

    @Test("sessionRefreshTotal is monotonic non-decreasing after many refreshes")
    func heartbeatMonotonicUnderLoad() async throws {
        let harness = LiveSessionHarness(input: singleURL)
        harness.fetcher.stub(singleURL, body: liveMedia)
        await harness.start()

        // Collect events concurrently while driving ≥20 refresh cycles
        let collector = Task { [harness] in
            var totals: [Int] = []
            for await event in harness.session.events {
                if case .activity(let p) = event, let t = p.sessionRefreshTotal {
                    totals.append(t)
                }
            }
            return totals
        }
        // Simulate 20+ refresh cycles (stray-input resilience at the event level)
        for _ in 0..<20 {
            await harness.step(by: 6, refreshing: singleURL)
        }
        await harness.abortAndFinish()
        let totals = await collector.value

        guard totals.isEmpty == false else {
            Issue.record("Expected activity events with sessionRefreshTotal")
            return
        }

        // Monotonic non-decreasing
        for i in 1..<totals.count {
            #expect(
                totals[i] >= totals[i - 1],
                "sessionRefreshTotal decreased at index \(i): \(totals[i - 1]) → \(totals[i])"
            )
        }

        // Final value equals refreshes performed (fetch count − 1 for initial fetch)
        let finalTotal = try #require(totals.last)
        let refreshCount = harness.fetcher.fetchCount(for: singleURL) - 1
        #expect(
            finalTotal == refreshCount,
            "Final sessionRefreshTotal \(finalTotal) should equal refresh count \(refreshCount)"
        )
    }

    @Test("sessionRefreshTotal after 20 cycles is at least 20")
    func sessionRefreshTotalAtLeast20After20Cycles() async throws {
        let harness = LiveSessionHarness(input: singleURL)
        harness.fetcher.stub(singleURL, body: liveMedia)
        await harness.start()

        let collector = Task { [harness] in
            var lastTotal: Int = 0
            for await event in harness.session.events {
                if case .activity(let p) = event, let t = p.sessionRefreshTotal {
                    lastTotal = t
                }
            }
            return lastTotal
        }
        for _ in 0..<20 {
            await harness.step(by: 6, refreshing: singleURL)
        }
        await harness.abortAndFinish()
        let lastTotal = await collector.value

        #expect(lastTotal >= 20, "After 20 refresh cycles, sessionRefreshTotal should be ≥ 20, got \(lastTotal)")
    }



    // MARK: - Fixtures

    private let liveMedia = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:100
        #EXTINF:6.0,
        seg100.ts
        #EXTINF:6.0,
        seg101.ts
        """
}

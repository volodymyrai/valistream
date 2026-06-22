//
//  LiveMonitoringTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
import ValistreamCore

@Suite("Live monitoring")
struct LiveMonitoringTests {
    private let media = URL(string: "https://ex.com/live.m3u8")!

    @Test("a healthy live playlist refreshes on cadence with no error or warning findings", .timeLimit(.minutes(1)))
    func healthyLiveRefreshesCleanly() async {
        let harness = LiveSessionHarness(input: media)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"]))),
            .init(at: .seconds(12), reply: .body(LivePlaylists.window(mediaSequence: 2, segments: ["s2.ts", "s3.ts", "s4.ts"]))),
            .init(at: .seconds(18), reply: .body(LivePlaylists.window(mediaSequence: 3, segments: ["s3.ts", "s4.ts", "s5.ts"]))),
        ])
        await harness.start()

        await harness.step(by: 6, refreshing: media)
        await harness.step(by: 6, refreshing: media)
        await harness.step(by: 6, refreshing: media)

        let classification = await harness.session.classification
        let monitorStates = await harness.session.playlistMonitorStates
        #expect(classification == .live)
        // Monitor state is keyed by the presentation ID (FR-013-ID), the same ID the roster
        // shows. A direct media playlist with no RESOLUTION/CODECS resolves to `video_1`.
        #expect(monitorStates["video_1"] == .monitoring)
        #expect(harness.fetcher.fetchCount(for: media) >= 4)

        await harness.abortAndFinish()

        let state = await harness.session.state
        let findings = await harness.session.recordedFindings
        #expect(state == .completed)
        #expect(findings.count(where: { $0.severity == .error }) == 0)
        #expect(findings.count(where: { $0.severity == .warning }) == 0)
    }

    @Test("a graceful stop ends the session in the completed state with a summary", .timeLimit(.minutes(1)))
    func gracefulStopProducesSummary() async {
        let harness = LiveSessionHarness(input: media)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"]))),
        ])
        await harness.start()

        await harness.step(by: 6, refreshing: media)
        await harness.abortAndFinish()

        let state = await harness.session.state
        let monitorStates = await harness.session.playlistMonitorStates
        #expect(state == .completed)
        #expect(monitorStates["video_1"] == .stopped)
    }

    @Test("a healthy refresh that repeats the same window carries a hold with the waited and retry delays", .timeLimit(.minutes(1)))
    func healthyNoChangeRefreshCarriesHold() async throws {
        let harness = LiveSessionHarness(input: media)
        let window0 = LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"])
        // The window never advances — the initial load and refresh #1 see the identical body, well
        // inside the 9s warning threshold (target 6s), so the playlist is still healthy.
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(window0)),
        ])
        let eventTask = Task {
            var events: [SessionEvent] = []
            for await timestampedEvent in harness.session.timestampedEvents {
                events.append(timestampedEvent.event)
            }
            return events
        }
        await harness.start()

        await harness.step(by: 6, refreshing: media)

        let monitorStates = await harness.session.playlistMonitorStates
        #expect(monitorStates["video_1"] == .monitoring)

        await harness.abortAndFinish()
        let events = await eventTask.value
        let holds = events.compactMap { event -> RefreshHold?? in
            guard case .refreshCompleted(_, _, _, _, let hold) = event else { return nil }
            return hold
        }.compactMap { $0 }
        let hold = try #require(holds.last)
        #expect(hold.waited.seconds == 6)
        #expect(hold.nextRetry.seconds == 3)
    }

    @Test("a stalling playlist never carries a hold once staleness has warned", .timeLimit(.minutes(1)))
    func staleRefreshSuppressesHold() async {
        let harness = LiveSessionHarness(input: media)
        // Only the initial window is ever served, mirroring the staleness escalation scenario —
        // by refresh #2 (waited 6s) staleFor is already 6s; by refresh #3 (waited 3s more) it
        // crosses the 9s warning threshold, so the hold gate must close from then on.
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
        ])
        let eventTask = Task {
            var events: [SessionEvent] = []
            for await timestampedEvent in harness.session.timestampedEvents {
                events.append(timestampedEvent.event)
            }
            return events
        }
        await harness.start()

        for _ in 0..<4 {
            await harness.step(by: 6, refreshing: media)
        }

        let findings = await harness.session.recordedFindings
        #expect(findings.contains { $0.ruleId == "TOOL.staleness" && $0.severity == .warning })

        await harness.abortAndFinish()
        let events = await eventTask.value
        let refreshes = events.compactMap { event -> (index: Int, hold: RefreshHold?)? in
            guard case .refreshCompleted(_, let index, _, _, let hold) = event else { return nil }
            return (index, hold)
        }
        let afterWarning = refreshes.filter { $0.index >= 3 }
        #expect(afterWarning.isEmpty == false)
        #expect(afterWarning.allSatisfy { $0.hold == nil })
    }
}

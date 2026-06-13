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
        harness.start()

        await harness.step(by: 6, refreshing: media)
        await harness.step(by: 6, refreshing: media)
        await harness.step(by: 6, refreshing: media)

        let classification = await harness.session.classification
        let monitorStates = await harness.session.playlistMonitorStates
        #expect(classification == .live)
        #expect(monitorStates["media"] == .monitoring)
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
        harness.start()

        await harness.step(by: 6, refreshing: media)
        await harness.abortAndFinish()

        let state = await harness.session.state
        let monitorStates = await harness.session.playlistMonitorStates
        #expect(state == .completed)
        #expect(monitorStates["media"] == .stopped)
    }
}

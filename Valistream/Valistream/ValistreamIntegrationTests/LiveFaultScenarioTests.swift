//
//  LiveFaultScenarioTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
import ValistreamCore

@Suite("Live fault scenarios")
struct LiveFaultScenarioTests {
    private let media = URL(string: "https://ex.com/live.m3u8")!

    @Test("a stalling playlist warns then escalates to an error", .timeLimit(.minutes(1)))
    func stallingPlaylistWarnsThenErrors() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appending(path: "LiveFaultScenarioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let harness = LiveSessionHarness(
            input: media,
            config: SessionConfig(
                outputDir: outputDir,
                nonInteractive: true,
                archiveEnabled: true
            )
        )
        // Only the initial window is ever served; the playlist never changes again.
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
        harness.start()

        for _ in 0..<6 {
            await harness.step(by: 6, refreshing: media)
        }

        let findings = await harness.session.recordedFindings
        let monitorStates = await harness.session.playlistMonitorStates
        #expect(findings.contains { $0.ruleId == "TOOL.staleness" && $0.severity == .warning })
        #expect(findings.contains { $0.ruleId == "TOOL.staleness" && $0.severity == .error })
        // Monitor state is keyed by the presentation ID (FR-013-ID); direct media resolves to `video_1`.
        #expect(monitorStates["video_1"] == .staleError)

        await harness.abortAndFinish()
        let events = await eventTask.value
        let warningEvidence = events.compactMap { event -> EvidenceReference? in
            guard case .finding(let finding, let evidence) = event,
                  finding.ruleId == "TOOL.staleness",
                  finding.severity == .warning
            else { return nil }
            return evidence
        }.first
        let expectedEvidence = EvidenceReference.pair(
            older: "playlists/video_1/video_1_0.m3u8",
            newer: "playlists/video_1/video_1_2.m3u8"
        )
        #expect(warningEvidence == expectedEvidence)

        let folder = try #require(await harness.session.sessionFolderURL)
        let report = try String(contentsOf: folder.appending(path: "report.md"), encoding: .utf8)
        for path in expectedEvidence.availablePaths {
            #expect(report.contains("`\(path)`"))
        }
        #expect(report.contains("video_1_1.m3u8") == false)
    }

    @Test("a permanently stalled playlist records at most one staleness finding per crossing", .timeLimit(.minutes(1)))
    func stalenessFindingsAreBoundedPerCrossing() async {
        let harness = LiveSessionHarness(input: media)
        // The window never changes — a stuck stream refreshes on cadence forever.
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
        ])
        harness.start()

        // Far more refreshes than threshold crossings.
        for _ in 0..<10 {
            await harness.step(by: 6, refreshing: media)
        }

        let findings = await harness.session.recordedFindings
        let warnings = findings.count { $0.ruleId == "TOOL.staleness" && $0.severity == .warning }
        let errors = findings.count { $0.ruleId == "TOOL.staleness" && $0.severity == .error }
        // Exactly one warning crossing + one error crossing — not one finding per refresh.
        #expect(warnings == 1)
        #expect(errors == 1)
        #expect(findings.count { $0.ruleId == "TOOL.staleness" } == 2)

        await harness.abortAndFinish()
    }

    @Test("a recovery re-arms staleness so a second stall fires again", .timeLimit(.minutes(1)))
    func recoveryRearmsStaleness() async {
        let harness = LiveSessionHarness(input: media)
        // Stall to error, then the window advances once (resetting staleness), then stalls again.
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(30), reply: .body(LivePlaylists.window(mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"]))),
        ])
        harness.start()

        for _ in 0..<10 {
            await harness.step(by: 6, refreshing: media)
        }

        let findings = await harness.session.recordedFindings
        let warnings = findings.count { $0.ruleId == "TOOL.staleness" && $0.severity == .warning }
        let errors = findings.count { $0.ruleId == "TOOL.staleness" && $0.severity == .error }
        // Two stall episodes, each bounded to one warning + one error crossing.
        #expect(warnings == 2)
        #expect(errors == 2)

        await harness.abortAndFinish()
    }

    @Test("a persistently failing fetch records the delivery violation once, not per refresh", .timeLimit(.minutes(1)))
    func deliveryViolationIsNotRefiredEachRefresh() async {
        let harness = LiveSessionHarness(input: media)
        // Loads once, then every refresh 404s with an identical delivery error.
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(3), reply: .body("Not Found", status: 404)),
        ])
        harness.start()

        for _ in 0..<6 {
            await harness.step(by: 6, refreshing: media)
        }

        let findings = await harness.session.recordedFindings
        // Six failing refreshes, one bounded delivery finding — not one per refresh.
        #expect(findings.count { $0.ruleId == "TOOL.delivery" } == 1)

        await harness.abortAndFinish()
    }

    @Test("a continuity fault repeating an identical message is recorded once", .timeLimit(.minutes(1)))
    func repeatedContinuityFaultIsNotRefired() async {
        let harness = LiveSessionHarness(input: media)
        // The window oscillates seq10 ⇄ seq8, so the same "regressed from 10 to 8" fault recurs on
        // every down-leg — a persistently broken stream re-emitting an identical violation.
        let high = LivePlaylists.window(mediaSequence: 10, segments: ["s10.ts", "s11.ts", "s12.ts"])
        let low = LivePlaylists.window(mediaSequence: 8, segments: ["s8.ts", "s9.ts", "s10.ts"])
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(high)),
            .init(at: .seconds(3), reply: .body(low)),
            .init(at: .seconds(9), reply: .body(high)),
            .init(at: .seconds(15), reply: .body(low)),
            .init(at: .seconds(21), reply: .body(high)),
            .init(at: .seconds(27), reply: .body(low)),
        ])
        harness.start()

        for _ in 0..<6 {
            await harness.step(by: 6, refreshing: media)
        }

        let findings = await harness.session.recordedFindings
        // The media-sequence regression recurs three times but its identical message dedups to one.
        #expect(findings.count { $0.ruleId == "TOOL.continuity.media-sequence" } == 1)

        await harness.abortAndFinish()
    }

    @Test("a media-sequence regression is reported as a continuity error", .timeLimit(.minutes(1)))
    func sequenceRegressionIsContinuityError() async {
        let harness = LiveSessionHarness(input: media)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 10, segments: ["s10.ts", "s11.ts", "s12.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(mediaSequence: 8, segments: ["s8.ts", "s9.ts", "s10.ts"]))),
        ])
        harness.start()

        await harness.step(by: 6, refreshing: media)

        let findings = await harness.session.recordedFindings
        #expect(findings.contains { $0.ruleId == "TOOL.continuity.media-sequence" && $0.severity == .error })

        await harness.abortAndFinish()
    }

    @Test("an inserted discontinuity is info and monitoring continues", .timeLimit(.minutes(1)))
    func discontinuityInsertionIsInfoAndContinues() async {
        let harness = LiveSessionHarness(input: media)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 10, segments: ["s10.ts", "s11.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(mediaSequence: 11, segments: ["s11.ts", "s12.ts"], discontinuityAt: 1))),
            .init(at: .seconds(12), reply: .body(LivePlaylists.window(mediaSequence: 12, segments: ["s12.ts", "s13.ts"]))),
        ])
        harness.start()

        await harness.step(by: 6, refreshing: media)
        await harness.step(by: 6, refreshing: media)

        let findings = await harness.session.recordedFindings
        let monitorStates = await harness.session.playlistMonitorStates
        #expect(findings.contains { $0.ruleId == "TOOL.continuity.discontinuity-inserted" && $0.severity == .info })
        #expect(findings.contains { $0.severity == .error } == false)
        #expect(monitorStates["video_1"] == .monitoring)

        await harness.abortAndFinish()
    }

    @Test("the session completes when its time limit expires", .timeLimit(.minutes(1)))
    func timeLimitExpiryCompletesSession() async {
        let harness = LiveSessionHarness(
            input: media,
            config: SessionConfig(timeLimit: .seconds(20), nonInteractive: true)
        )
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"]))),
        ])
        harness.start()

        await harness.step(by: 6, refreshing: media)
        await harness.advance(by: 30)
        await harness.finish()

        let state = await harness.session.state
        #expect(state == .completed)
    }
}

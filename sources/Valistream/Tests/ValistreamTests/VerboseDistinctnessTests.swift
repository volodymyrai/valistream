//
//  VerboseDistinctnessTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import Foundation
import Testing
@testable import Valistream
@testable import ValistreamCore

/// Asserts FR-015, SC-005: `--verbose` adds ≥5 trace categories absent at normal;
/// all verbose (trace) lines are ID-based (no raw URLs).
@Suite("Verbose distinctness from normal tier", .timeLimit(.minutes(1)))
struct VerboseDistinctnessTests {

    private let masterURL = URL(string: "https://cdn.example.com/live/master.m3u8")!
    private let mediaURL  = URL(string: "https://cdn.example.com/live/v1080/index.m3u8")!

    @Test("verbose tier produces .trace events; normal tier does not")
    func verboseTierHasTraceEventsNormalDoesNot() async throws {
        let verboseEvents = await collectEvents(verbose: true)
        let normalEvents = await collectEvents(verbose: false)

        let verboseTraceCount = verboseEvents.count(where: { if case .trace = $0 { return true }; return false })
        let normalTraceCount = normalEvents.count(where: { if case .trace = $0 { return true }; return false })

        #expect(verboseTraceCount > 0, "Verbose session should produce .trace events")
        #expect(normalTraceCount == 0, "Normal session should produce no .trace events")
    }

    @Test("verbose tier adds at least 5 distinct trace categories absent at normal")
    func verboseAddsAtLeast5Categories() async throws {
        let verboseEvents = await collectEvents(verbose: true)
        var verboseCategories = Set<String>()
        for event in verboseEvents {
            if case .trace(let traceEvent) = event {
                verboseCategories.insert(categoryPrefix(of: traceEvent))
            }
        }
        // SC-005: ≥5 distinct categories (Fetch, Validation, Stored, Refresh, Compare, Lifecycle)
        #expect(
            verboseCategories.count >= 5,
            "Expected ≥5 distinct trace categories, got \(verboseCategories.count): \(verboseCategories)"
        )
    }

    @Test("all trace event lines are ID-based (no raw URLs in formatted output)")
    func traceEventLinesAreIDBasedNoRawURL() async throws {
        let events = await collectEvents(verbose: true)
        for event in events {
            if case .trace(let traceEvent) = event {
                let line = TraceFormatter.format(traceEvent)
                #expect(
                    line.contains("https://") == false,
                    "Trace line contains raw URL: \(line)"
                )
                #expect(
                    line.contains("http://") == false,
                    "Trace line contains raw URL: \(line)"
                )
            }
        }
    }

    @Test("verbose tier produces both .rosterReady and .refreshCompleted events")
    func verboseHasRosterAndRefreshCompleted() async throws {
        let events = await collectEvents(verbose: true)
        let hasRoster = events.contains(where: { if case .rosterReady = $0 { return true }; return false })
        let hasRefresh = events.contains(where: { if case .refreshCompleted = $0 { return true }; return false })
        #expect(hasRoster, "Verbose session should emit .rosterReady")
        #expect(hasRefresh, "Verbose session should emit .refreshCompleted after a refresh cycle")
    }


    @Test("unchanged refresh emits half-target retry trace")
    func unchangedRefreshEmitsRetryTrace() async {
        let harness = LiveSessionHarness(
            input: masterURL,
            config: SessionConfig(nonInteractive: true, verboseEvents: true)
        )
        harness.fetcher.stub(masterURL, body: masterPlaylist)
        harness.fetcher.stub(mediaURL, body: liveMedia)
        harness.start()
        var events: [SessionEvent] = []

        await withDiscardingTaskGroup { group in
            group.addTask {
                for await event in harness.session.events {
                    events.append(event)
                }
            }
            group.addTask {
                await harness.step(by: 6, refreshing: self.mediaURL)
                await harness.abortAndFinish()
            }
        }

        let retryDelays = events.compactMap { event -> Double? in
            guard case .trace(.refreshRetry(_, let delaySeconds)) = event else { return nil }
            return delaySeconds
        }
        #expect(retryDelays == [3])
    }



    // MARK: - Private helpers

    private func collectEvents(verbose: Bool) async -> [SessionEvent] {
        let harness = LiveSessionHarness(
            input: masterURL,
            config: SessionConfig(nonInteractive: true, verboseEvents: verbose)
        )
        harness.fetcher.stub(masterURL, body: masterPlaylist)
        harness.fetcher.stub(mediaURL, body: liveMedia)
        harness.start()

        var events: [SessionEvent] = []
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await event in harness.session.events {
                    events.append(event)
                }
            }
            group.addTask {
                // Drive one refresh cycle so refreshCompleted + cadence traces are emitted.
                await harness.step(by: 6, refreshing: self.mediaURL)
                await harness.abortAndFinish()
            }
        }

        return events
    }

    /// Returns the category prefix of a `TraceEvent` for distinctness counting.
    private func categoryPrefix(of event: TraceEvent) -> String {
        switch event {
        case .fetchStarted, .fetchIntent, .fetchResult: "Fetch"
        case .validationPlaylistOK, .validationPlaylistFail, .validationRuleOK, .validationRuleFail: "Validation"
        case .stored: "Stored"
        case .refreshScheduled, .refreshRetry, .refreshDrift: "Refresh"
        case .continuityCompare: "Compare"
        case .renditionAdded, .renditionDropped: "Lifecycle"
        }
    }



    // MARK: - T043: Category rendering and visual subordination

    @Test("trace lines render cyan lead with dim phrase except white retry")
    func traceUsesTwoToneColorRoles() async throws {
        let recorder = OutputRecorder()
        let mode = TerminalOutputMode(
            isTTY: true,
            noColorEnv: false,
            noColorFlag: false,
            termIsDumb: false,
            environment: ["LANG": "en_US.UTF-8", "TERM": "xterm-256color"],
            verbosity: .verbose
        )
        var renderer = StatusRenderer(
            writer: TerminalWriter(
                mode: mode,
                terminalWidth: 120,
                output: recorder.writeStandardOutput,
                errorOutput: recorder.writeStandardError
            ),
            json: false,
            timeZone: .gmt
        )
        let at = Date(timeIntervalSince1970: 1_750_000_000)

        renderer.render(TimestampedEvent(at: at, event: .trace(.validationPlaylistOK(snapshotID: "video_1"))))
        renderer.render(TimestampedEvent(at: at, event: .trace(.refreshRetry(playlistID: "video", delaySeconds: 2))))

        let output = recorder.standardOutput
        #expect(output.contains("\u{1B}[36mvideo_1 →\u{1B}[0m \u{1B}[90mvalidated OK\u{1B}[0m"))
        #expect(output.contains("\u{1B}[36mvideo →\u{1B}[0m \u{1B}[37mre-try scheduled in 2s\u{1B}[0m"))
    }

    @Test("verbose trace lines merge context lead and suppress fetch intent")
    func traceLinesMergeContextLeadAndSuppressFetchIntent() async throws {
        let recorder = OutputRecorder()
        let mode = TerminalOutputMode(
            isTTY: false,
            noColorEnv: true,
            noColorFlag: false,
            termIsDumb: false,
            environment: ["LANG": "en_US.UTF-8"],
            verbosity: .verbose
        )
        var renderer = StatusRenderer(
            writer: TerminalWriter(
                mode: mode,
                terminalWidth: 120,
                output: recorder.writeStandardOutput,
                errorOutput: recorder.writeStandardError
            ),
            json: false,
            timeZone: .gmt
        )
        let at = Date(timeIntervalSince1970: 1_750_000_000)
        let snapshotID = "video-1080p_1"

        renderer.render(TimestampedEvent(at: at, event: .trace(.fetchIntent(snapshotID: snapshotID))))
        renderer.render(TimestampedEvent(
            at: at,
            event: .trace(.fetchResult(snapshotID: snapshotID, httpStatus: 200, durationMs: 14, bytes: 2_300))
        ))
        renderer.render(TimestampedEvent(at: at, event: .trace(.validationPlaylistOK(snapshotID: snapshotID))))

        let output = recorder.standardOutput
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.contains("\(snapshotID) →") })
        #expect(lines[0].contains("fetched HTTP 200; 14ms; 2.3 kB"))
        #expect(lines[1].contains("validated OK"))
        #expect(output.contains("requesting") == false)
        #expect(output.contains("\n\n") == false)
    }

    @Test("verbose trace and refresh result are adjacent in plain output")
    func verboseTraceAndRefreshResultAreAdjacentInPlainOutput() async throws {
        let recorder = OutputRecorder()
        let plainMode = TerminalOutputMode(
            isTTY: false,
            noColorEnv: true,
            noColorFlag: false,
            termIsDumb: false,
            environment: [:],
            verbosity: .verbose
        )
        var renderer = StatusRenderer(
            writer: TerminalWriter(
                mode: plainMode,
                terminalWidth: 120,
                output: recorder.writeStandardOutput,
                errorOutput: recorder.writeStandardError
            ),
            json: false,
            timeZone: .gmt
        )
        let at = Date(timeIntervalSince1970: 1_750_000_000)

        renderer.render(TimestampedEvent(at: at, event: .trace(.validationPlaylistOK(snapshotID: "video_1"))))
        renderer.render(TimestampedEvent(
            at: at,
            event: .refreshCompleted(playlistID: "video", index: 1, errors: 0, warnings: 0, hold: nil)
        ))

        let output = recorder.standardOutput
        #expect(output.contains("\u{1B}") == false)
        #expect(output.contains("video_1 -> validated OK"))
        #expect(output.contains("[OK] Refreshed video_1: no findings."))
        #expect(output.contains("\n\n") == false)
    }

    @Test("every verbose trace line repeats its context lead")
    func everyVerboseTraceLineRepeatsItsContextLead() async throws {
        let recorder = OutputRecorder()
        let mode = TerminalOutputMode(
            isTTY: false,
            noColorEnv: true,
            noColorFlag: false,
            termIsDumb: false,
            environment: ["LANG": "en_US.UTF-8"],
            verbosity: .verbose
        )
        var renderer = StatusRenderer(
            writer: TerminalWriter(
                mode: mode,
                terminalWidth: 120,
                output: recorder.writeStandardOutput,
                errorOutput: recorder.writeStandardError
            ),
            json: false,
            timeZone: .gmt
        )
        let at = Date(timeIntervalSince1970: 1_750_000_000)
        let snapshotID = "video-1080p_1"

        renderer.render(TimestampedEvent(at: at, event: .trace(.validationPlaylistOK(snapshotID: snapshotID))))
        renderer.render(TimestampedEvent(
            at: at,
            event: .refreshCompleted(playlistID: "video-1080p", index: 1, errors: 0, warnings: 0, hold: nil)
        ))
        renderer.render(TimestampedEvent(
            at: at,
            event: .trace(.stored(snapshotID: snapshotID, archivePath: "playlists/video/video-1080p_1.m3u8"))
        ))

        let output = recorder.standardOutput
        let lead = "\(snapshotID) →"
        #expect(output.components(separatedBy: lead).count - 1 == 2)
        #expect(output.contains("\n\n") == false)
    }

    // MARK: - Fixtures

    private let masterPlaylist = """
        #EXTM3U
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,CODECS="avc1.640028",RESOLUTION=1920x1080
        v1080/index.m3u8
        """

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

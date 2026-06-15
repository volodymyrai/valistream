//
//  NormalSessionReadabilityTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation
import Testing
import ValistreamCore

@Suite("Normal session readability")
struct NormalSessionReadabilityTests {
    @Test("refreshes persist once and warning evidence stays adjacent")
    func refreshResultAndFindingBlock() {
        let recorder = OutputRecorder()
        var renderer = makeRenderer(recorder: recorder)
        let at = Date(timeIntervalSince1970: 1_750_000_000)
        let finding = makeFinding(at: at)

        renderer.render(TimestampedEvent(
            at: at,
            event: .refreshCompleted(playlistID: "video", index: 0, errors: 0, warnings: 0)
        ))
        renderer.render(TimestampedEvent(at: at, event: .finding(
            finding,
            evidence: .single(path: "playlists/video/video_1.m3u8")
        )))
        renderer.render(TimestampedEvent(
            at: at,
            event: .refreshCompleted(playlistID: "video", index: 1, errors: 0, warnings: 1)
        ))

        let output = recorder.standardOutput
        #expect(output.components(separatedBy: "Refreshed video_0").count - 1 == 1)
        #expect(output.components(separatedBy: "Refreshed video_1").count - 1 == 1)
        #expect(output.contains("Refreshed video_1") && output.contains("Warning video_1"))
        #expect(output.contains("video_1.m3u8\n\n") == false)
    }

    @Test("initial findings render immediately without waiting for a refresh result")
    func initialFindingRendersImmediately() {
        let recorder = OutputRecorder()
        var renderer = makeRenderer(recorder: recorder)
        let at = Date(timeIntervalSince1970: 1_750_000_000)
        let finding = Finding(
            id: "initial-finding",
            ruleId: "TOOL.initial",
            source: .tool,
            severity: .warning,
            category: .mediaPlaylist,
            resource: URL(filePath: "/video.m3u8"),
            location: nil,
            refreshIndex: nil,
            observedAt: at,
            message: "Initial playlist warning.",
            context: [:]
        )

        renderer.render(TimestampedEvent(
            at: at,
            event: .finding(finding, evidence: .single(path: "playlists/video/video_0.m3u8"))
        ))

        #expect(recorder.standardOutput.contains("Initial playlist warning."))
        #expect(recorder.standardOutput.contains("video_0.m3u8"))
    }

    @Test("final summary includes outcome counts elapsed time and report paths")
    func finalSummary() {
        let recorder = OutputRecorder()
        var renderer = makeRenderer(recorder: recorder)
        let at = Date(timeIntervalSince1970: 1_750_000_000)

        renderer.renderSummary(
            findings: [makeFinding(at: at)],
            state: .completed,
            sessionFolder: "/tmp/session",
            elapsed: .seconds(12.5),
            playlistCount: 3,
            reportPath: "/tmp/session/report.md",
            at: at
        )

        let output = recorder.standardOutput
        #expect(output.contains("Complete"))
        #expect(output.contains("3 playlists"))
        #expect(output.contains("1 warning"))
        #expect(output.contains("12.5 s"))
        #expect(output.contains("/tmp/session/report.md"))
        #expect(output.contains("/tmp/session"))
    }

    @Test("normal outcome lines use approved vocabulary and avoid internal terms")
    func naturalLanguageVocabulary() {
        let recorder = OutputRecorder()
        var renderer = makeRenderer(recorder: recorder)
        let at = Date(timeIntervalSince1970: 1_750_000_000)

        renderer.render(TimestampedEvent(at: at, event: .stateChanged(.initializing)))
        renderer.render(TimestampedEvent(at: at, event: .streamClassified(.live)))
        renderer.render(TimestampedEvent(at: at, event: .playlistLifecycle(
            PlaylistLifecycleEvent(playlistID: "video", at: at, kind: .added)
        )))
        renderer.render(TimestampedEvent(
            at: at,
            event: .refreshCompleted(playlistID: "video", index: 0, errors: 0, warnings: 0)
        ))

        let bannedTerms = [
            "ValidationSession", "RuleEngine", "TerminalWriter", "tokenize", "comparator", "diff",
            "envelope", "emit", "buffer", "serialize", "encoder", "FindingsLog", "JSONL", "stage", "pipeline",
        ]
        let output = recorder.standardOutput
        for term in bannedTerms {
            #expect(output.localizedCaseInsensitiveContains(term) == false)
        }
    }

    @Test("plain heartbeat stays transient and emits no persistent progress")
    func plainHeartbeatIsSuppressed() {
        var progress = ProgressView(mode: makeMode())

        progress.render(
            ActivityProgress(activity: "monitoring", completed: 1, refreshes: 1),
            at: Date(timeIntervalSince1970: 1_750_000_000)
        )

        #expect(progress.spinnerIndex == 0)
    }

    @Test("scripted session renders occurrence-stamped human output end to end", .timeLimit(.minutes(1)))
    func scriptedSessionRendersTimestampedOutput() async throws {
        let url = try #require(URL(string: "https://example.com/media.m3u8"))
        let at = Date(timeIntervalSince1970: 1_750_000_000)
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(url, body: """
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-TARGETDURATION:6
            #EXT-X-MEDIA-SEQUENCE:0
            #EXT-X-PLAYLIST-TYPE:VOD
            #EXTINF:6.0,
            seg0.ts
            #EXTINF:6.0,
            seg1.ts
            #EXT-X-ENDLIST
            """)
        let session = ValidationSession(
            inputURL: url,
            config: SessionConfig(nonInteractive: true),
            fetcher: fetcher,
            now: { at }
        )
        let recorder = OutputRecorder()
        var renderer = makeRenderer(recorder: recorder)
        let runTask = Task { await session.run() }

        for await event in session.timestampedEvents {
            renderer.render(event)
        }
        await runTask.value
        renderer.renderSummary(
            findings: await session.recordedFindings,
            state: await session.state,
            sessionFolder: nil,
            elapsed: .seconds(1),
            playlistCount: renderer.playlistCount,
            reportPath: nil,
            at: at
        )

        let output = recorder.standardOutput
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        let timestamp = TerminalTimestampFormatter.format(at, timeZone: .gmt)
        #expect(lines.isEmpty == false)
        #expect(lines.allSatisfy { $0.hasPrefix(timestamp) })
        #expect(output.components(separatedBy: "Loaded playlist information for").count - 1 == 1)
        #expect(output.contains("Complete"))
    }

    private func makeRenderer(recorder: OutputRecorder) -> StatusRenderer {
        let mode = makeMode()
        return StatusRenderer(
            writer: TerminalWriter(
                mode: mode,
                terminalWidth: 120,
                output: recorder.writeStandardOutput,
                errorOutput: recorder.writeStandardError
            ),
            json: false,
            timeZone: .gmt
        )
    }

    private func makeMode() -> TerminalOutputMode {
        TerminalOutputMode(
            isTTY: false,
            noColorEnv: false,
            noColorFlag: false,
            termIsDumb: false,
            environment: ["LANG": "en_US.UTF-8"],
            verbosity: .normal
        )
    }

    private func makeFinding(at: Date) -> Finding {
        Finding(
            id: "finding-1",
            ruleId: "TOOL.test",
            source: .tool,
            severity: .warning,
            category: .mediaPlaylist,
            resource: URL(filePath: "/video.m3u8"),
            location: nil,
            refreshIndex: 1,
            observedAt: at,
            message: "Target duration changed.",
            context: [:]
        )
    }
}

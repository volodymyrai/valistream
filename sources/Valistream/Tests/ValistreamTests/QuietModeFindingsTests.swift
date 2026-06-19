//
//  QuietModeFindingsTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation
import Testing
@testable import Valistream
import ValistreamCore

@Suite("Quiet mode findings")
struct QuietModeFindingsTests {
    @Test("quiet retains actionable blocks and omits routine and informational output")
    func filteringAndGrouping() throws {
        let recorder = OutputRecorder()
        var renderer = makeRenderer(recorder: recorder)
        let at = Date(timeIntervalSince1970: 1_750_000_000)
        let resource = try #require(URL(string: "https://example.com/video.m3u8"))

        renderer.render(TimestampedEvent(at: at, event: .stateChanged(.initializing)))
        renderer.render(TimestampedEvent(at: at, event: .streamClassified(.live)))
        renderer.render(TimestampedEvent(at: at, event: .rosterReady([
            RosterEntry(id: "video", url: resource, role: "video"),
        ])))
        renderer.render(TimestampedEvent(
            at: at,
            event: .playlistInformation(makeInformation())
        ))
        renderer.render(TimestampedEvent(
            at: at,
            event: .refreshCompleted(playlistID: "video", index: 0, errors: 0, warnings: 0, hold: nil)
        ))
        renderer.render(TimestampedEvent(
            at: at,
            event: .trace(.fetchStarted(url: resource, playlistID: "video", refreshIndex: 1))
        ))
        renderer.render(TimestampedEvent(
            at: at,
            event: .finding(
                makeFinding(
                    id: "f-info",
                    severity: .info,
                    resource: resource,
                    message: "Routine informational finding."
                ),
                evidence: nil
            )
        ))
        let warning = makeFinding(
            id: "f-warning",
            severity: .warning,
            resource: resource,
            message: "Target duration changed."
        )
        renderer.render(TimestampedEvent(
            at: at,
            event: .finding(
                warning,
                evidence: .single(path: "playlists/video/video_1.m3u8")
            )
        ))
        renderer.render(TimestampedEvent(
            at: at,
            event: .refreshCompleted(playlistID: "video", index: 1, errors: 0, warnings: 1, hold: nil)
        ))
        renderer.render(TimestampedEvent(
            at: at,
            event: .playlistLifecycle(
                PlaylistLifecycleEvent(playlistID: "video", at: at, kind: .recovered)
            )
        ))
        renderer.render(TimestampedEvent(at: at, event: .stateChanged(.aborted)))
        renderer.renderSummary(
            findings: [warning],
            state: .aborted,
            sessionFolder: "/tmp/session",
            elapsed: .seconds(2),
            playlistCount: 1,
            reportPath: "/tmp/session/report.md",
            at: at
        )

        let output = recorder.standardOutput
        #expect(output.contains("Target duration changed."))
        #expect(output.contains("Evidence: playlists/video/video_1.m3u8"))
        #expect(output.contains("Recovered: video"))
        #expect(output.contains("Interrupted: validation session stopped."))
        #expect(output.contains("Interrupted: 1 playlist processed"))
        #expect(output.contains("/tmp/session/report.md"))
        #expect(output.contains("Ready to validate") == false)
        #expect(output.contains("Detected a live stream") == false)
        #expect(output.contains("Discovered") == false)
        #expect(output.contains("Loaded playlist information") == false)
        #expect(output.contains("Refreshed video_0") == false)
        #expect(output.contains("Fetch started") == false)
        #expect(output.contains("Routine informational finding") == false)
        #expect(output.contains("Target duration changed.\n[") == false)
        let warningRange = try #require(output.range(of: "Target duration changed."))
        let evidenceRange = try #require(output.range(of: "Evidence: playlists/video/video_1.m3u8"))
        #expect(warningRange.lowerBound < evidenceRange.lowerBound)
    }

    private func makeRenderer(recorder: OutputRecorder) -> StatusRenderer {
        let mode = TerminalOutputMode(
            isTTY: false,
            noColorEnv: false,
            noColorFlag: false,
            termIsDumb: false,
            environment: ["LANG": "en_US.UTF-8"],
            verbosity: .quiet
        )
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

    private func makeFinding(
        id: String,
        severity: Finding.Severity,
        resource: URL,
        message: String
    ) -> Finding {
        Finding(
            id: id,
            ruleId: "TOOL.quiet",
            source: .tool,
            severity: severity,
            category: .delivery,
            resource: resource,
            location: nil,
            refreshIndex: 1,
            observedAt: Date(timeIntervalSince1970: 1_750_000_000),
            message: message,
            context: [:]
        )
    }

    private func makeInformation() -> PlaylistInformation {
        PlaylistInformation(
            playlistID: "video",
            kind: .media,
            master: nil,
            media: MediaInfo(
                playlistType: "LIVE",
                hlsVersion: 7,
                segmentCount: 1,
                totalListedDuration: 6,
                targetDuration: 6,
                medianSegmentDuration: 6,
                minimumSegmentDuration: 6,
                maximumSegmentDuration: 6,
                mediaSequence: 0,
                discontinuitySequence: 0,
                discontinuityCount: 0,
                endList: false,
                independentSegments: false,
                iFramesOnly: false,
                segmentFormats: ["ts"],
                byteRangeUsed: false,
                programDateTimeAvailable: false,
                protection: .none
            )
        )
    }
}

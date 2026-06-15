//
//  BlankLineGroupingTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation
import Testing
import ValistreamCore

@Suite("Blank-line grouping")
struct BlankLineGroupingTests {
    @Test("blocks have one separator and refresh findings remain contiguous")
    func blocksUseOneBlankLine() {
        let recorder = OutputRecorder()
        var renderer = makeRenderer(recorder: recorder)
        let at = Date(timeIntervalSince1970: 1_750_000_000)
        let finding = makeFinding(at: at)

        renderer.render(TimestampedEvent(at: at, event: .stateChanged(.initializing)))
        renderer.render(TimestampedEvent(at: at, event: .finding(
            finding,
            evidence: .single(path: "playlists/video_1080p/video_1080p_1.m3u8")
        )))
        renderer.render(TimestampedEvent(
            at: at,
            event: .refreshCompleted(playlistID: "video_1080p", index: 1, errors: 0, warnings: 1)
        ))
        renderer.render(TimestampedEvent(at: at, event: .playlistLifecycle(
            PlaylistLifecycleEvent(playlistID: "video_1080p", at: at, kind: .recovered)
        )))

        let output = recorder.standardOutput
        #expect(output.hasPrefix("\n") == false)
        #expect(output.hasSuffix("\n\n") == false)
        #expect(output.contains("\n\n\n") == false)
        #expect(output.contains("1 warning") && output.contains("Warning video_1080p_1"))
        let blocks = output.components(separatedBy: "\n\n")
        #expect(blocks.count == 3)
        #expect(blocks[1].contains("Target duration changed."))
        #expect(blocks[1].contains("video_1080p_1.m3u8"))
    }

    @Test("playlist field groups use one internal blank line")
    func playlistInformationGroups() {
        let recorder = OutputRecorder()
        var renderer = makeRenderer(recorder: recorder)
        let at = Date(timeIntervalSince1970: 1_750_000_000)

        renderer.render(TimestampedEvent(at: at, event: .playlistInformation(makePlaylistInformation())))

        let groups = recorder.standardOutput
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: "\n\n")
        #expect(groups.count == 5)
        #expect(groups.allSatisfy { $0.contains("\n\n") == false })
    }

    private func makeRenderer(recorder: OutputRecorder) -> StatusRenderer {
        StatusRenderer(
            writer: TerminalWriter(
                mode: makeMode(),
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

    private func makePlaylistInformation() -> PlaylistInformation {
        PlaylistInformation(
            playlistID: "video_1080p",
            kind: .media,
            master: nil,
            media: MediaInfo(
                playlistType: "LIVE",
                hlsVersion: 7,
                segmentCount: 3,
                totalListedDuration: 18,
                targetDuration: 6,
                medianSegmentDuration: 6,
                minimumSegmentDuration: 6,
                maximumSegmentDuration: 6,
                mediaSequence: 100,
                discontinuitySequence: 0,
                discontinuityCount: 0,
                endList: false,
                independentSegments: true,
                iFramesOnly: false,
                segmentFormats: ["ts"],
                byteRangeUsed: false,
                programDateTimeAvailable: true,
                protection: .encryptedAES128
            )
        )
    }
}

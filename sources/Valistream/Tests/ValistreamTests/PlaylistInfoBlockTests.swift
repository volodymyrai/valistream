//
//  PlaylistInfoBlockTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation
import Testing
@testable import Valistream
import ValistreamCore

@Suite("Playlist information terminal blocks")
struct PlaylistInfoBlockTests {
    @Test("normal and verbose show each playlist once while quiet omits it", arguments: [
        (Verbosity.normal, 1),
        (.verbose, 1),
        (.quiet, 0),
    ])
    func informationBlockVisibility(verbosity: Verbosity, expectedCount: Int) {
        let recorder = OutputRecorder()
        var renderer = makeRenderer(verbosity: verbosity, recorder: recorder)
        let at = Date(timeIntervalSince1970: 1_750_000_000)
        let information = makeInformation(id: "video", protection: .encryptedAES128)

        renderer.render(TimestampedEvent(at: at, event: .playlistInformation(information)))
        renderer.render(TimestampedEvent(at: at.addingTimeInterval(5), event: .playlistInformation(information)))

        #expect(recorder.standardOutput.components(separatedBy: "Loaded playlist information for video").count - 1 == expectedCount)
        #expect(renderer.playlistCount == 1)
    }

    @Test("mixed renditions keep independent protection values")
    func protectionIsPerPlaylist() {
        let recorder = OutputRecorder()
        var renderer = makeRenderer(verbosity: .normal, recorder: recorder)
        let at = Date(timeIntervalSince1970: 1_750_000_000)

        renderer.render(TimestampedEvent(
            at: at,
            event: .playlistInformation(makeInformation(id: "video", protection: .drm(keyFormat: "com.apple.streamingkeydelivery")))
        ))
        renderer.render(TimestampedEvent(
            at: at,
            event: .playlistInformation(makeInformation(id: "subs_en", protection: .none))
        ))

        let output = recorder.standardOutput
        #expect(output.contains("DRM (com.apple.streamingkeydelivery)"))
        #expect(output.contains("Protection: None"))
    }

    private func makeRenderer(verbosity: Verbosity, recorder: OutputRecorder) -> StatusRenderer {
        let mode = TerminalOutputMode(
            isTTY: false,
            noColorEnv: false,
            noColorFlag: false,
            termIsDumb: false,
            environment: ["LANG": "en_US.UTF-8"],
            verbosity: verbosity
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

    private func makeInformation(id: String, protection: Protection) -> PlaylistInformation {
        PlaylistInformation(
            playlistID: id,
            kind: .media,
            master: nil,
            media: MediaInfo(
                playlistType: "LIVE",
                hlsVersion: 7,
                segmentCount: 2,
                totalListedDuration: 12,
                targetDuration: 6,
                medianSegmentDuration: 6,
                minimumSegmentDuration: 6,
                maximumSegmentDuration: 6,
                mediaSequence: 1,
                discontinuitySequence: 0,
                discontinuityCount: 0,
                endList: false,
                independentSegments: false,
                iFramesOnly: false,
                segmentFormats: ["ts"],
                byteRangeUsed: false,
                programDateTimeAvailable: false,
                protection: protection
            )
        )
    }
}

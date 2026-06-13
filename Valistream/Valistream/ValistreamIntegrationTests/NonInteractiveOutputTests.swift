//
//  NonInteractiveOutputTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

import Foundation
import Testing
import ValistreamCore

/// Verifies SC-004 / FR-007: non-interactive (no-TTY) output contains zero ANSI or cursor-control
/// escape sequences and is composed of discrete, human-readable lines.
@Suite("Non-interactive output")
struct NonInteractiveOutputTests {

    private let base = "https://ex.com/hls/"



    // MARK: - Tests

    @Test("activity lines formatted for non-TTY contain no ANSI escape sequences (SC-004, FR-007)")
    func activityLinesHaveNoANSI() async {
        let master = URL(string: base + "master.m3u8")!
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(master, body: Fixtures.conformantMaster)
        fetcher.stub(URL(string: base + "v720/index.m3u8")!, body: Fixtures.conformantMedia)
        fetcher.stub(URL(string: base + "audio/en.m3u8")!,   body: Fixtures.conformantMedia)
        fetcher.stub(URL(string: base + "iframe/720.m3u8")!, body: Fixtures.conformantMedia)

        let session = ValidationSession(
            inputURL: master,
            config: SessionConfig(nonInteractive: true),
            fetcher: fetcher,
            id: "non-interactive-test",
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let activityLines = await collectActivityLines(from: session)
        #require(!activityLines.isEmpty, "Expected at least one activity line")
        for line in activityLines {
            #expect(!line.contains("\u{1B}["), "ANSI escape found: \(line)")
        }
    }

    @Test("non-TTY TerminalOutputMode disables color (SC-004 gate)")
    func nonTTYModeDisablesColor() {
        let mode = TerminalOutputMode(
            isTTY: false,
            noColorEnv: false,
            noColorFlag: false,
            termIsDumb: false,
            verbosity: .normal
        )
        #expect(mode.colorEnabled == false)
    }



    // MARK: - Helpers

    private func collectActivityLines(from session: ValidationSession) async -> [String] {
        await withTaskGroup(of: [String].self) { group in
            group.addTask { await session.run(); return [] }
            group.addTask {
                var lines: [String] = []
                for await event in session.events {
                    if case .activity(let p) = event {
                        lines.append(ProgressFormatter.format(p))
                    }
                }
                return lines
            }
            var all: [String] = []
            for await result in group { all += result }
            return all
        }
    }



    // MARK: - Fixtures

    private enum Fixtures {
        static let conformantMaster = """
            #EXTM3U
            #EXT-X-INDEPENDENT-SEGMENTS
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",NAME="English",LANGUAGE="en",DEFAULT=YES,AUTOSELECT=YES,URI="audio/en.m3u8"
            #EXT-X-STREAM-INF:BANDWIDTH=1280000,AVERAGE-BANDWIDTH=1100000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720,AUDIO="aud1"
            v720/index.m3u8
            #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=120000,RESOLUTION=1280x720,CODECS="avc1.4d401f",URI="iframe/720.m3u8"
            """

        static let conformantMedia = """
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
            """
    }
}

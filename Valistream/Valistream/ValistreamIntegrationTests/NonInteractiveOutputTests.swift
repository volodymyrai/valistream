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
    func activityLinesHaveNoANSI() async throws {
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
        try #require(!activityLines.isEmpty, "Expected at least one activity line")
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
            environment: ["LANG": "C"],
            verbosity: .normal
        )
        #expect(mode.colorEnabled == false)
    }

    @Test("plain output has ASCII markers no control bytes and wraps without truncation", arguments: [80, 120])
    func plainOutputWrapsWithoutTruncation(width: Int) {
        let recorder = OutputRecorder()
        let mode = TerminalOutputMode(
            isTTY: false,
            noColorEnv: true,
            noColorFlag: true,
            termIsDumb: true,
            environment: ["LANG": "C"],
            verbosity: .normal
        )
        let writer = TerminalWriter(
            mode: mode,
            terminalWidth: width,
            output: recorder.writeStandardOutput,
            errorOutput: recorder.writeStandardError
        )
        let message = "Warning video_1080p_42: " + String(repeating: "segment duration exceeds target ", count: 5)

        writer.writeFinding(
            at: Date(timeIntervalSince1970: 1_750_000_000),
            severity: .warning,
            message: message,
            evidence: "playlists/video_1080p/video_1080p_42.m3u8",
            timeZone: .gmt
        )

        let output = recorder.standardOutput
        #expect(output.contains("[WARN]"))
        #expect(output.contains("\u{1B}") == false)
        #expect(output.contains("\r") == false)
        #expect(output.contains("video_1080p_42"))
        #expect(output.contains("segment duration exceeds target"))
        #expect(output.contains("playlists/video_1080p/video_1080p_42.m3u8"))
        #expect(output.split(separator: "\n").allSatisfy { $0.count <= width })
    }

    @Test(
        "each styling gate removes ANSI and cursor control",
        arguments: [
            GateCase(isTTY: false, noColorEnv: false, noColorFlag: false, termIsDumb: false),
            GateCase(isTTY: true, noColorEnv: true, noColorFlag: false, termIsDumb: false),
            GateCase(isTTY: true, noColorEnv: false, noColorFlag: true, termIsDumb: false),
            GateCase(isTTY: true, noColorEnv: false, noColorFlag: false, termIsDumb: true),
        ]
    )
    func stylingGateRemovesControlBytes(gate: GateCase) {
        let recorder = OutputRecorder()
        let mode = TerminalOutputMode(
            isTTY: gate.isTTY,
            noColorEnv: gate.noColorEnv,
            noColorFlag: gate.noColorFlag,
            termIsDumb: gate.termIsDumb,
            environment: ["LANG": "C"],
            verbosity: .normal
        )
        let writer = TerminalWriter(
            mode: mode,
            output: recorder.writeStandardOutput,
            errorOutput: recorder.writeStandardError
        )

        writer.writeFinding(
            at: Date(timeIntervalSince1970: 1_750_000_000),
            severity: .warning,
            message: "Warning video_1: target duration changed.",
            evidence: nil,
            timeZone: .gmt
        )

        #expect(recorder.standardOutput.contains("\u{1B}") == false)
        #expect(recorder.standardOutput.contains("\r") == false)
        #expect(recorder.standardOutput.contains("[WARN]"))
    }

    @Test("styled finding tints the whole line and keeps a text marker")
    func styledFindingUsesWholeLineTint() {
        let recorder = OutputRecorder()
        let mode = TerminalOutputMode(
            isTTY: true,
            noColorEnv: false,
            noColorFlag: false,
            termIsDumb: false,
            environment: ["LANG": "en_US.UTF-8"],
            verbosity: .normal
        )
        let writer = TerminalWriter(
            mode: mode,
            output: recorder.writeStandardOutput,
            errorOutput: recorder.writeStandardError
        )

        writer.writeFinding(
            at: Date(timeIntervalSince1970: 1_750_000_000),
            severity: .warning,
            message: "Warning video_1: target duration changed.",
            evidence: nil,
            timeZone: .gmt
        )

        #expect(recorder.standardOutput.hasPrefix("\u{1B}[33m["))
        #expect(recorder.standardOutput.contains("⚠ WARN"))
        #expect(recorder.standardOutput.contains("\u{1B}[0m\n"))
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

    struct GateCase: Sendable {
        let isTTY: Bool
        let noColorEnv: Bool
        let noColorFlag: Bool
        let termIsDumb: Bool
    }
}

//
//  CompatibilityFreezeTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import ValistreamCore

import Foundation
import Testing
@testable import Valistream

@Suite("Feature 004 compatibility freeze")
struct CompatibilityFreezeTests {
    @Test("compact machine finding contains no human timestamp, spacing, or styling")
    func compactFindingRemainsMachineOnly() throws {
        let resource = try #require(URL(string: "https://example.com/live.m3u8"))
        let finding = Finding(
            id: "f1",
            ruleId: "TOOL.delivery",
            source: .tool,
            severity: .warning,
            category: .delivery,
            resource: resource,
            location: nil,
            refreshIndex: 0,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            message: "Slow response",
            context: [:]
        )

        let data = try Finding.jsonEncoder.encode(finding)
        let output = try #require(String(data: data, encoding: .utf8))

        #expect(output.contains("\n") == false)
        #expect(output.contains("\u{1B}") == false)
        #expect(output.contains("[22:") == false)
        #expect(output.contains("\"at\"") == false)
        #expect(output.contains("\"specRef\"") == false)
    }


    @Test("JSON renderer includes specRef for cited findings")
    func jsonRendererIncludesSpecRef() throws {
        let resource = try #require(URL(string: "https://example.com/live.m3u8"))
        let finding = Finding(
            id: "f1",
            ruleId: "RFC8216.4.3.4.2-BANDWIDTH",
            source: .rfc8216,
            severity: .error,
            category: .masterPlaylist,
            resource: resource,
            location: nil,
            refreshIndex: 0,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            message: "Missing BANDWIDTH",
            context: [:]
        )
        let recorder = OutputRecorder()
        let renderer = StatusRenderer(
            writer: TerminalWriter(
                mode: TerminalOutputMode(
                    isTTY: false,
                    noColorEnv: false,
                    noColorFlag: false,
                    termIsDumb: false,
                    environment: [:],
                    verbosity: .normal
                ),
                terminalWidth: 120,
                output: recorder.writeStandardOutput,
                errorOutput: recorder.writeStandardError
            ),
            json: true,
            timeZone: .gmt
        )

        renderer.render(SessionEvent.finding(finding, evidence: nil))

        #expect(recorder.standardOutput.contains("\"specRef\":\"RFC 8216 §4.3.4.2\""))
    }

    @Test("raw session event stream remains available for machine consumers")
    func rawEventStreamRemainsAvailable() async throws {
        let url = try #require(URL(string: "https://example.com/media.m3u8"))
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(url, body: """
            #EXTM3U
            #EXT-X-TARGETDURATION:6
            #EXTINF:6,
            segment.ts
            #EXT-X-ENDLIST
            """)
        let session = ValidationSession(
            inputURL: url,
            config: SessionConfig(nonInteractive: true),
            fetcher: fetcher,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let collector = Task {
            var events: [SessionEvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        await session.run()
        let events = await collector.value

        #expect(events.isEmpty == false)
    }
}

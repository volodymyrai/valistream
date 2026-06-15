//
//  SessionReportTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite(.tags(.session))
struct SessionReportTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let end   = Date(timeIntervalSince1970: 1_700_003_600)
    private let inputURL = URL(string: "https://ex.com/master.m3u8")!

    private func makeSnapshot(
        state: SessionState = .completed,
        streamKind: StreamKind? = .vod,
        interruption: String? = nil
    ) -> SessionReportBuilder.SessionSnapshot {
        SessionReportBuilder.SessionSnapshot(
            id: "20260612-120000-abcd",
            inputURL: inputURL,
            startedAt: start,
            endedAt: end,
            state: state,
            config: SessionConfig(archiveEnabled: true),
            streamKind: streamKind,
            lowLatencyDetected: false,
            encryptionDetected: false,
            interruption: interruption
        )
    }

    private func makePlaylists() -> [SessionReportBuilder.PlaylistInfo] {
        [
            SessionReportBuilder.PlaylistInfo(
                id: "master",
                kind: .master,
                role: nil,
                url: inputURL,
                selected: true,
                refreshCount: 1
            ),
            SessionReportBuilder.PlaylistInfo(
                id: "variant-0",
                kind: .media,
                role: .variant,
                url: URL(string: "https://ex.com/v0.m3u8")!,
                selected: true,
                refreshCount: 4
            ),
            SessionReportBuilder.PlaylistInfo(
                id: "audio-0",
                kind: .media,
                role: .audio,
                url: URL(string: "https://ex.com/a0.m3u8")!,
                selected: false,
                excludedByChoice: true,
                refreshCount: 0
            ),
        ]
    }

    private func makeFindings() -> [Finding] {
        [
            Finding(
                id: "f1",
                ruleId: "RFC8216.4.3.4.2-BANDWIDTH",
                source: .rfc8216,
                severity: .error,
                category: .masterPlaylist,
                resource: inputURL,
                location: nil,
                refreshIndex: nil,
                observedAt: start,
                message: "Missing BANDWIDTH",
                context: [:]
            ),
            Finding(
                id: "f2",
                ruleId: "TOOL.delivery",
                source: .tool,
                severity: .warning,
                category: .delivery,
                resource: URL(string: "https://ex.com/v0.m3u8")!,
                location: nil,
                refreshIndex: nil,
                observedAt: start,
                message: "slow delivery",
                context: [:]
            ),
        ]
    }



    // MARK: - JSON structure

    @Test("report.json contains all required top-level fields")
    func jsonContainsRequiredFields() throws {
        let builder = SessionReportBuilder()
        let data = try builder.buildJSON(
            session: makeSnapshot(),
            playlists: makePlaylists(),
            findings: makeFindings(),
            artifactIndex: []
        )
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["schemaVersion"] != nil)
        #expect(obj["session"] != nil)
        #expect(obj["stream"] != nil)
        #expect(obj["playlists"] != nil)
        #expect(obj["findings"] != nil)
        #expect(obj["summary"] != nil)
    }

    @Test("schemaVersion is 1")
    func schemaVersionIs1() throws {
        let builder = SessionReportBuilder()
        let data = try builder.buildJSON(session: makeSnapshot(), playlists: [], findings: [], artifactIndex: [])
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["schemaVersion"] as? Int == 1)
    }

    @Test("session object contains required fields with correct types")
    func sessionObjectFields() throws {
        let builder = SessionReportBuilder()
        let data = try builder.buildJSON(session: makeSnapshot(), playlists: [], findings: [], artifactIndex: [])
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try #require(obj["session"] as? [String: Any])
        #expect(session["id"] as? String == "20260612-120000-abcd")
        #expect(session["inputUrl"] as? String == inputURL.absoluteString)
        #expect(session["startedAt"] is String)
        #expect(session["endedAt"] is String)
        #expect(session["state"] as? String == "completed")
        #expect(session["config"] != nil)
    }

    @Test("stream object has kind and lowLatencyDetected")
    func streamObjectFields() throws {
        let builder = SessionReportBuilder()
        let data = try builder.buildJSON(session: makeSnapshot(streamKind: .live), playlists: [], findings: [], artifactIndex: [])
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let stream = try #require(obj["stream"] as? [String: Any])
        #expect(stream["kind"] as? String == "live")
        #expect(stream["lowLatencyDetected"] as? Bool == false)
    }

    @Test("playlists array records selected and excluded playlists")
    func playlistsArrayRecordsSelection() throws {
        let builder = SessionReportBuilder()
        let data = try builder.buildJSON(session: makeSnapshot(), playlists: makePlaylists(), findings: [], artifactIndex: [])
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let playlists = try #require(obj["playlists"] as? [[String: Any]])
        #expect(playlists.count == 3)

        let excluded = try #require(playlists.first { $0["id"] as? String == "audio-0" })
        #expect(excluded["selected"] as? Bool == false)
        #expect(excluded["excludedByChoice"] as? Bool == true)
    }

    @Test("summary counts findings by severity")
    func summaryCountsBySeverity() throws {
        let builder = SessionReportBuilder()
        let data = try builder.buildJSON(session: makeSnapshot(), playlists: [], findings: makeFindings(), artifactIndex: [])
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let summary = try #require(obj["summary"] as? [String: Any])
        let bySeverity = try #require(summary["countsBySeverity"] as? [String: Any])
        #expect(bySeverity["error"] as? Int == 1)
        #expect(bySeverity["warning"] as? Int == 1)
    }

    @Test("summary counts findings by source")
    func summaryCountsBySource() throws {
        let builder = SessionReportBuilder()
        let data = try builder.buildJSON(session: makeSnapshot(), playlists: [], findings: makeFindings(), artifactIndex: [])
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let summary = try #require(obj["summary"] as? [String: Any])
        let bySource = try #require(summary["countsBySource"] as? [String: Any])
        #expect(bySource["rfc8216"] as? Int == 1)
        #expect(bySource["tool"] as? Int == 1)
    }

    @Test("interruption field is present when session was aborted")
    func interruptionFieldPresent() throws {
        let builder = SessionReportBuilder()
        let data = try builder.buildJSON(
            session: makeSnapshot(state: .aborted, interruption: "aborted"),
            playlists: [],
            findings: [],
            artifactIndex: []
        )
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try #require(obj["session"] as? [String: Any])
        #expect(session["interruption"] as? String == "aborted")
    }

    @Test("artifactIndex entries contain requestId, url, bodyPath, metaPath")
    func artifactIndexEntries() throws {
        let entry = SessionArchive.IndexEntry(
            requestId: "r1",
            url: URL(string: "https://ex.com/p.m3u8")!,
            bodyPath: "playlists/master/000000.m3u8",
            metaPath: "playlists/master/000000.meta.json"
        )
        let builder = SessionReportBuilder()
        let data = try builder.buildJSON(session: makeSnapshot(), playlists: [], findings: [], artifactIndex: [entry])
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let index = try #require(obj["artifactIndex"] as? [[String: Any]])
        #expect(index.count == 1)
        #expect(index[0]["requestId"] as? String == "r1")
        #expect(index[0]["bodyPath"] as? String == "playlists/master/000000.m3u8")
        #expect(index[0]["metaPath"] as? String == "playlists/master/000000.meta.json")
    }



    // MARK: - Markdown

    @Test("report.md contains session ID, stream URL, and state")
    func markdownContainsMetadata() {
        let builder = SessionReportBuilder()
        let md = builder.buildMarkdown(session: makeSnapshot(), playlists: [], findings: [])
        #expect(md.contains("20260612-120000-abcd"))
        #expect(md.contains("https://ex.com/master.m3u8"))
        #expect(md.contains("completed"))
    }

    @Test("report.md renders summary section with finding counts")
    func markdownRendersSummary() {
        let builder = SessionReportBuilder()
        let md = builder.buildMarkdown(session: makeSnapshot(), playlists: [], findings: makeFindings())
        #expect(md.contains("## Summary"))
        #expect(md.contains("Error"))
        #expect(md.contains("Warning"))
    }

    @Test("report.md lists all playlists under Session Details section")
    func markdownListsPlaylists() {
        let builder = SessionReportBuilder()
        let md = builder.buildMarkdown(session: makeSnapshot(), playlists: makePlaylists(), findings: [])
        #expect(md.contains("## Session Details"))
        #expect(md.contains("master"))
        #expect(md.contains("variant-0"))
        #expect(md.contains("audio-0"))
        #expect(md.contains("excluded"))
    }

    @Test("report.md renders findings section when findings exist")
    func markdownRendersFindings() {
        let builder = SessionReportBuilder()
        let md = builder.buildMarkdown(session: makeSnapshot(), playlists: [], findings: makeFindings())
        #expect(md.contains("## Findings"))
        #expect(md.contains("RFC8216.4.3.4.2-BANDWIDTH"))
        #expect(md.contains("TOOL.delivery"))
    }
}

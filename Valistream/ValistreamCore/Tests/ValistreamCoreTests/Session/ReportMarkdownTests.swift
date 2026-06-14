//
//  ReportMarkdownTests.swift
//  ValistreamCoreTests
//

import Testing
@testable import ValistreamCore
import Foundation

@Suite(.tags(.session))
struct ReportMarkdownTests {
    private let start      = Date(timeIntervalSince1970: 1_700_000_000)
    private let end        = Date(timeIntervalSince1970: 1_700_003_600)
    private let masterURL  = URL(string: "https://ex.com/master.m3u8")!
    private let videoURL   = URL(string: "https://ex.com/video.m3u8")!
    private let audioURL   = URL(string: "https://ex.com/audio.m3u8")!

    private func makeSnapshot(interruption: String? = nil) -> SessionReportBuilder.SessionSnapshot {
        SessionReportBuilder.SessionSnapshot(
            id: "test-session-us4",
            inputURL: masterURL,
            startedAt: start,
            endedAt: end,
            state: .completed,
            config: SessionConfig(),
            streamKind: .vod,
            lowLatencyDetected: false,
            encryptionDetected: false,
            interruption: interruption
        )
    }

    private func makePlaylists() -> [SessionReportBuilder.PlaylistInfo] {
        [
            .init(id: "master",  kind: .master, role: nil,      url: masterURL, selected: true,  refreshCount: 1),
            .init(id: "video-0", kind: .media,  role: .variant, url: videoURL,  selected: true,  refreshCount: 3),
            .init(id: "audio-0", kind: .media,  role: .audio,   url: audioURL,  selected: false, excludedByChoice: true, refreshCount: 0),
        ]
    }

    private func makeRegistry() -> AliasRegistry {
        var reg = AliasRegistry()
        reg.alias(for: masterURL, role: .master, attributes: [:])
        reg.alias(
            for: videoURL,
            role: .video,
            attributes: ["RESOLUTION": "1920x1080", "CODECS": "avc1.640028"]
        )
        reg.alias(for: audioURL, role: .audio, attributes: ["LANGUAGE": "en"])
        return reg
    }

    private func makeFindings() -> [Finding] {
        [
            Finding(
                id: "f1", ruleId: "RFC8216.4.3.4.2-BANDWIDTH", source: .rfc8216,
                severity: .error, category: .masterPlaylist, resource: masterURL,
                location: nil, refreshIndex: nil, observedAt: start,
                message: "Missing BANDWIDTH", context: [:]
            ),
            Finding(
                id: "f2", ruleId: "TOOL.delivery", source: .tool,
                severity: .warning, category: .delivery, resource: videoURL,
                location: nil, refreshIndex: nil, observedAt: start,
                message: "Slow delivery", context: [:]
            ),
            Finding(
                id: "f3", ruleId: "RFC8216.4.3.3.1", source: .rfc8216,
                severity: .error, category: .mediaPlaylist, resource: videoURL,
                location: nil, refreshIndex: nil, observedAt: start,
                message: "Bad segment", context: [:]
            ),
        ]
    }

    // MARK: - Required sections

    @Test("markdown has Summary, Legend, Findings, and Per-playlist sections")
    func requiredSections() {
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(), playlists: makePlaylists(),
            findings: makeFindings(), aliasRegistry: makeRegistry()
        )
        #expect(md.contains("## Summary"))
        #expect(md.contains("## Legend"))
        #expect(md.contains("## Findings"))
        #expect(md.contains("## Per-playlist"))
    }

    @Test("header contains session id, stream URL, and state")
    func headerContents() {
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(), playlists: [], findings: [], aliasRegistry: makeRegistry()
        )
        #expect(md.contains("test-session-us4"))
        #expect(md.contains(masterURL.absoluteString))
        #expect(md.contains("completed"))
    }

    @Test("PARTIAL marker present when interruption contains PARTIAL")
    func partialMarker() {
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(interruption: "graceful stop — PARTIAL"),
            playlists: [], findings: [], aliasRegistry: AliasRegistry()
        )
        #expect(md.contains("PARTIAL"))
    }

    // MARK: - Severity grouping

    @Test("Findings section groups by severity (errors before warnings)")
    func findingsGroupedBySeverity() {
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(), playlists: makePlaylists(),
            findings: makeFindings(), aliasRegistry: makeRegistry()
        )
        guard
            let errorRange = md.range(of: "### Error"),
            let warnRange  = md.range(of: "### Warning")
        else {
            Issue.record("Missing ### Error or ### Warning heading in Findings")
            return
        }
        #expect(errorRange.lowerBound < warnRange.lowerBound, "Errors must appear before warnings")
    }

    // MARK: - No raw playlist URLs in body (SC-007)

    @Test("Findings section has zero raw .m3u8 URLs (SC-007)")
    func findingsHasNoRawPlaylistURLs() {
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(), playlists: makePlaylists(),
            findings: makeFindings(), aliasRegistry: makeRegistry()
        )
        guard let findingsRange = md.range(of: "## Findings") else {
            Issue.record("No ## Findings section"); return
        }
        // Extract text from Findings onward (up to Per-playlist)
        let fromFindings = String(md[findingsRange.lowerBound...])
        let findingsBody: String
        if let perPlaylistRange = fromFindings.range(of: "## Per-playlist") {
            findingsBody = String(fromFindings[..<perPlaylistRange.lowerBound])
        } else {
            findingsBody = fromFindings
        }
        // No raw .m3u8 links in Findings body
        let rawURLMatches = findingsBody.ranges(of: ".m3u8")
        #expect(rawURLMatches.isEmpty, "Found raw .m3u8 URL in Findings section")
    }

    @Test("Per-playlist section has zero raw .m3u8 URLs (SC-007)")
    func perPlaylistHasNoRawURLs() {
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(), playlists: makePlaylists(),
            findings: makeFindings(), aliasRegistry: makeRegistry()
        )
        guard let perPlaylistRange = md.range(of: "## Per-playlist") else {
            Issue.record("No ## Per-playlist section"); return
        }
        let perPlaylistBody = String(md[perPlaylistRange.lowerBound...])
        let rawURLMatches = perPlaylistBody.ranges(of: ".m3u8")
        #expect(rawURLMatches.isEmpty, "Found raw .m3u8 URL in Per-playlist section")
    }

    // MARK: - Every alias resolves via Legend (FR-025)

    @Test("every registered alias appears in the Legend section")
    func everyAliasResolvesViaLegend() {
        let reg = makeRegistry()
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(), playlists: makePlaylists(),
            findings: makeFindings(), aliasRegistry: reg
        )
        guard let legendRange = md.range(of: "## Legend") else {
            Issue.record("No ## Legend section"); return
        }
        let legendText = String(md[legendRange.lowerBound...])
        for entry in reg.all {
            #expect(legendText.contains(entry.alias),
                    "Alias '\(entry.alias)' not found in Legend")
        }
    }

    // MARK: - Legend format

    @Test("Legend maps each alias to its full URL")
    func legendMapsAliasToURL() {
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(), playlists: makePlaylists(),
            findings: [], aliasRegistry: makeRegistry()
        )
        guard let legendRange = md.range(of: "## Legend") else {
            Issue.record("No ## Legend section"); return
        }
        let legend = String(md[legendRange.lowerBound...])
        #expect(legend.contains("1080p_avc1"))
        #expect(legend.contains(videoURL.absoluteString))
        #expect(legend.contains("audio_1"))
        #expect(legend.contains(audioURL.absoluteString))
    }
}

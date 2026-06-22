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

    @Test("markdown has Summary and Legend, but no Findings or Session Details sections")
    func requiredSections() {
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(), playlists: makePlaylists(),
            findings: makeFindings(), aliasRegistry: makeRegistry()
        )
        #expect(md.contains("## Summary"))
        #expect(md.contains("## Legend"))
        #expect(md.contains("\n## Findings") == false)
        #expect(md.contains("## Session Details") == false)
        #expect(md.contains("## Playlist Information") == false)
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

    // MARK: - Per-playlist finding routing

    @Test("each playlist's Findings subsection only contains that playlist's own findings")
    func perPlaylistFindingRouting() {
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(), playlists: makePlaylists(),
            findings: makeFindings(), aliasRegistry: makeRegistry()
        )
        // f1 belongs to master, f2 and f3 belong to video-0 (alias 1080p_avc1).
        guard
            let masterRange = md.range(of: "## 🔴 master · Master manifest"),
            let videoRange = md.range(of: "## 🔴 1080p_avc1")
        else {
            Issue.record("Missing expected playlist block headings")
            return
        }
        #expect(masterRange.lowerBound < videoRange.lowerBound, "master block must render before media blocks")

        let masterBlock = String(md[masterRange.lowerBound..<videoRange.lowerBound])
        #expect(masterBlock.contains("#### 🔴 Finding f1"))
        #expect(masterBlock.contains("- Rule: `RFC8216.4.3.4.2-BANDWIDTH` (RFC 8216 §4.3.4.2)"))
        #expect(masterBlock.contains("#### 🔴 Finding f3") == false)
        #expect(masterBlock.contains("#### 🟡 Finding f2") == false)

        let fromVideo = String(md[videoRange.lowerBound...])
        let videoBlock: String
        if let legendRange = fromVideo.range(of: "## Legend") {
            videoBlock = String(fromVideo[..<legendRange.lowerBound])
        }
        else {
            videoBlock = fromVideo
        }
        #expect(videoBlock.contains("#### 🟡 Finding f2"))
        #expect(videoBlock.contains("- Rule: `TOOL.delivery`\n"))
        #expect(videoBlock.contains("#### 🔴 Finding f3"))
        #expect(videoBlock.contains("- Rule: `RFC8216.4.3.3.1` (RFC 8216 §4.3.3.1)"))
        #expect(videoBlock.contains("#### 🔴 Finding f1") == false)
    }

    // MARK: - Verdict glyph mapping

    @Test(
        "verdict glyph reflects the worst severity among a playlist's own findings",
        arguments: [
            (severities: [Finding.Severity](), expectedGlyph: "✅", expectedWord: "Healthy"),
            (severities: [.warning], expectedGlyph: "⚠️", expectedWord: "Needs attention"),
            (severities: [.error], expectedGlyph: "🔴", expectedWord: "Problems"),
            (severities: [.warning, .error], expectedGlyph: "🔴", expectedWord: "Problems"),
        ]
    )
    func verdictGlyphMapping(severities: [Finding.Severity], expectedGlyph: String, expectedWord: String) {
        let findings = severities.enumerated().map { index, severity in
            Finding(
                id: "v\(index)", ruleId: "TOOL.verdict-test", source: .tool,
                severity: severity, category: .delivery, resource: masterURL,
                location: nil, refreshIndex: nil, observedAt: start,
                message: "verdict probe", context: [:]
            )
        }
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(),
            playlists: [.init(id: "master", kind: .master, role: nil, url: masterURL, selected: true, refreshCount: 1)],
            findings: findings,
            aliasRegistry: makeRegistry()
        )
        #expect(md.contains("## \(expectedGlyph) master · Master manifest"))
        #expect(md.contains("*\(expectedWord)"))
    }

    // MARK: - Subtitle format

    @Test("italic subtitle lists verdict, kind/variants, refreshes, then warnings/errors/status")
    func subtitleFormat() {
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(), playlists: makePlaylists(),
            findings: makeFindings(), aliasRegistry: makeRegistry()
        )
        // audio-0 is excluded, has zero findings of its own -> Healthy, 0 refreshes, excluded.
        #expect(md.contains("*Healthy · 0 refreshes · excluded*"))
    }

    @Test("subtitle reports 'not selected' when a playlist is unselected but not excluded by choice")
    func subtitleNotSelected() {
        let notSelected = SessionReportBuilder.PlaylistInfo(
            id: "audio-0", kind: .media, role: .audio, url: audioURL,
            selected: false, excludedByChoice: false, refreshCount: 0
        )
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(), playlists: [notSelected], findings: [], aliasRegistry: makeRegistry()
        )
        #expect(md.contains("*Healthy · 0 refreshes · not selected*"))
    }

    // MARK: - Master vs media block shape

    @Test("master block has flat bullets with no 'Playlist ID' field and no Timing subsection")
    func masterBlockShape() {
        let information = PlaylistInformation(
            playlistID: "master",
            kind: .master,
            master: MasterInfo(
                hlsVersion: 7, independentSegments: true, variantCount: 2,
                uniqueMediaPlaylistCount: 2, renditionCountsByType: [:], iFrameStreamCount: 0,
                distinctResolutions: ["1920x1080"], distinctCodecs: ["avc1.640028"],
                minimumBandwidth: 4_000_000, maximumBandwidth: 4_000_000,
                minimumFrameRate: 25, maximumFrameRate: 25, sessionProtection: .none
            ),
            media: nil
        )
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(),
            playlists: [.init(id: "master", kind: .master, role: nil, url: masterURL, selected: true, refreshCount: 1)],
            findings: [],
            aliasRegistry: makeRegistry(),
            playlistInformation: [information]
        )
        #expect(md.contains("- Type: Master"))
        #expect(md.contains("- Playlist ID:") == false)
        #expect(md.contains("### Timing") == false)
    }

    @Test("media block has flat bullets with no 'Playlist ID' field plus a Timing subsection")
    func mediaBlockShape() {
        let information = PlaylistInformation(
            playlistID: "video-0",
            kind: .media,
            master: nil,
            media: MediaInfo(
                playlistType: "VOD", hlsVersion: 7, segmentCount: 6, totalListedDuration: 24,
                targetDuration: 4, medianSegmentDuration: 4, minimumSegmentDuration: 4,
                maximumSegmentDuration: 4, mediaSequence: 0, discontinuitySequence: 0,
                discontinuityCount: 0, endList: true, independentSegments: false,
                iFramesOnly: false, segmentFormats: ["m4v"], byteRangeUsed: false,
                programDateTimeAvailable: false, protection: .none
            )
        )
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(),
            playlists: [.init(id: "video-0", kind: .media, role: .variant, url: videoURL, selected: true, refreshCount: 1)],
            findings: [],
            aliasRegistry: makeRegistry(),
            playlistInformation: [information]
        )
        #expect(md.contains("- Type: VOD"))
        #expect(md.contains("- Playlist ID:") == false)
        #expect(md.contains("### Timing"))
        #expect(md.contains("- Segments: 6"))
    }

    // MARK: - Encryption-info suppression

    @Test("TOOL.encryption findings are dropped from the body and from Summary counts")
    func encryptionInfoSuppression() {
        let encryptionInfo = Finding(
            id: "f-enc", ruleId: "TOOL.encryption", source: .tool,
            severity: .info, category: .delivery, resource: masterURL,
            location: nil, refreshIndex: nil, observedAt: start,
            message: "DRM detected", context: [:]
        )
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(),
            playlists: [.init(id: "master", kind: .master, role: nil, url: masterURL, selected: true, refreshCount: 1)],
            findings: [encryptionInfo],
            aliasRegistry: makeRegistry()
        )
        #expect(md.contains("#### 🔵 Finding f-enc") == false)
        #expect(md.contains("0 errors, 0 warnings, 0 informational findings"))
        #expect(md.contains("### Findings") == false)
    }

    // MARK: - No raw playlist URLs in body (SC-007)

    @Test("playlist blocks have no raw playlist URLs")
    func playlistBlocksHaveNoRawURLs() {
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(),
            playlists: makePlaylists(),
            findings: makeFindings(),
            aliasRegistry: makeRegistry()
        )
        guard let summaryRange = md.range(of: "## Summary"), let legendRange = md.range(of: "## Legend") else {
            Issue.record("Missing ## Summary or ## Legend section")
            return
        }
        let body = String(md[summaryRange.lowerBound..<legendRange.lowerBound])
        #expect(body.contains("https://") == false)
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
        #expect(legend.contains("audio_en"))
        #expect(legend.contains(audioURL.absoluteString))
    }

    // MARK: - Evidence rendering (single "Evidence:" prefix)

    @Test("evidence line has exactly one 'Evidence:' prefix, never doubled")
    func evidenceHasSinglePrefix() {
        let artifactIndex = [
            SessionArchive.IndexEntry(
                requestId: "r1",
                url: masterURL,
                bodyPath: "playlists/master/master_0.m3u8",
                metaPath: "playlists/master/master_0.meta.json"
            ),
            SessionArchive.IndexEntry(
                requestId: "r2",
                url: videoURL,
                bodyPath: "playlists/1080p_avc1/1080p_avc1_0.m3u8",
                metaPath: "playlists/1080p_avc1/1080p_avc1_0.meta.json"
            ),
        ]
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(),
            playlists: makePlaylists(),
            findings: makeFindings(),
            aliasRegistry: makeRegistry(),
            artifactIndex: artifactIndex
        )

        #expect(md.contains("`playlists/master/master_0.m3u8`"))
        #expect(md.contains("`playlists/1080p_avc1/1080p_avc1_0.m3u8`"))
        #expect(md.contains("](playlists/") == false, "Evidence must be an inline code span, not a link")
        #expect(md.contains("evidence: evidence:") == false, "Evidence prefix must not double-print")
        // Exactly one "- Evidence: " per finding (no leftover "evidence: " inside the value).
        #expect(md.components(separatedBy: "- Evidence: evidence:").count - 1 == 0)
    }

    @Test("continuity findings render two consecutive evidence spans")
    func continuityRendersTwoEvidenceSpans() {
        let continuity = Finding(
            id: "f4", ruleId: "TOOL.continuity.media-sequence", source: .tool,
            severity: .warning, category: .continuity, resource: videoURL,
            location: nil, refreshIndex: 2, observedAt: start,
            message: "Media sequence regressed", context: [:]
        )
        let artifactIndex = [1, 2].map { index in
            SessionArchive.IndexEntry(
                requestId: "r\(index)",
                url: videoURL,
                bodyPath: "playlists/1080p_avc1/1080p_avc1_\(index).m3u8",
                metaPath: "playlists/1080p_avc1/1080p_avc1_\(index).meta.json"
            )
        }
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(),
            playlists: makePlaylists(),
            findings: [continuity],
            aliasRegistry: makeRegistry(),
            artifactIndex: artifactIndex
        )

        #expect(md.contains("`playlists/1080p_avc1/1080p_avc1_1.m3u8`"))
        #expect(md.contains("`playlists/1080p_avc1/1080p_avc1_2.m3u8`"))
    }

    @Test("staleness report preserves baseline and confirming evidence")
    func stalenessReportPreservesBaselineAndConfirmingEvidence() {
        let staleness = Finding(
            id: "f-stale", ruleId: "TOOL.staleness", source: .tool,
            severity: .warning, category: .continuity, resource: videoURL,
            location: nil, refreshIndex: 84, observedAt: start,
            message: "Playlist is stale", context: [:]
        )
        let artifactIndex = [82, 83, 84].map { index in
            SessionArchive.IndexEntry(
                requestId: "r\(index)",
                url: videoURL,
                bodyPath: "playlists/1080p_avc1/1080p_avc1_\(index).m3u8",
                metaPath: "playlists/1080p_avc1/1080p_avc1_\(index).meta.json"
            )
        }
        let evidence = EvidenceReference.pair(
            older: "playlists/1080p_avc1/1080p_avc1_82.m3u8",
            newer: "playlists/1080p_avc1/1080p_avc1_84.m3u8"
        )
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(),
            playlists: makePlaylists(),
            findings: [staleness],
            aliasRegistry: makeRegistry(),
            artifactIndex: artifactIndex,
            evidenceByFindingID: [staleness.id: evidence]
        )

        #expect(md.contains("`playlists/1080p_avc1/1080p_avc1_82.m3u8`"))
        #expect(md.contains("`playlists/1080p_avc1/1080p_avc1_84.m3u8`"))
        #expect(md.contains("1080p_avc1_83.m3u8") == false)
    }

    @Test("missing evidence names the ID without exposing the URL")
    func missingEvidenceNamesID() {
        let finding = Finding(
            id: "f5", ruleId: "TOOL.delivery", source: .tool,
            severity: .warning, category: .delivery, resource: videoURL,
            location: nil, refreshIndex: 0, observedAt: start,
            message: "Fetch failed", context: [:]
        )
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(),
            playlists: makePlaylists(),
            findings: [finding],
            aliasRegistry: makeRegistry(),
            artifactIndex: []
        )
        guard
            let videoRange = md.range(of: "## ⚠️ 1080p_avc1"),
            let legendRange = md.range(of: "## Legend")
        else {
            Issue.record("Missing video playlist block or Legend section")
            return
        }
        let videoBlock = String(md[videoRange.lowerBound..<legendRange.lowerBound])
        #expect(videoBlock.contains("no body captured for 1080p_avc1"))
        #expect(videoBlock.contains(videoURL.absoluteString) == false)
    }

    // MARK: - Timeline anchor resolves

    @Test("timeline link target resolves to the matching finding subsection")
    func timelineAnchorResolves() {
        let finding = makeFindings()[0]
        let timeline = IncidentTimeline(events: [
            (
                sequence: 1,
                event: TimestampedEvent(
                    at: start,
                    event: .finding(finding, evidence: .single(path: "playlists/master/master_0.m3u8"))
                )
            ),
        ])
        let md = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(),
            playlists: makePlaylists(),
            findings: [finding],
            aliasRegistry: makeRegistry(),
            timeline: timeline
        )
        #expect(md.contains("[Finding f1](#finding-f1)"))
        // GitHub's header slugger lowercases, strips emoji/punctuation, and joins words with '-':
        // "#### 🔴 Finding f1" -> "finding-f1", matching the timeline anchor target exactly.
        #expect(md.contains("#### 🔴 Finding f1"))
    }
}

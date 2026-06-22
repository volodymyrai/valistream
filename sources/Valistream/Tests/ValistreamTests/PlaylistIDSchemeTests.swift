//
//  PlaylistIDSchemeTests.swift
//  ValistreamIntegrationTests
//

import Testing
@testable import ValistreamCore
import Foundation

/// Integration tests for the end-to-end playlist ID scheme (US3 / SC-006, SC-007).
/// Uses scripted in-process transport stubs — no local HTTP server.
@Suite("Playlist ID scheme — differentiation, determinism, legend", .timeLimit(.minutes(1)))
struct PlaylistIDSchemeTests {
    // MARK: - Master playlist content

    /// A master playlist containing:
    /// - Two video variants differing in resolution only (1080p vs 720p), same codec
    /// - Two video variants differing in codec only (same 720p height: avc1 vs hvc1)
    /// - An audio track with LANGUAGE=en
    /// - A second audio track same language different name (commentary)
    /// - A subtitles track
    /// - An I-frame playlist at 1080p
    private static let masterPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="en",NAME="Main",DEFAULT=YES,URI="audio-en-main.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="en",NAME="Commentary",DEFAULT=NO,URI="audio-en-commentary.m3u8"
        #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",LANGUAGE="en",NAME="English",DEFAULT=NO,URI="subs-en.m3u8"
        #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=150000,RESOLUTION=1920x1080,CODECS="avc1.640028",URI="iframe-1080p.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028",AUDIO="audio",SUBTITLES="subs"
        video-1080p-avc1.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="avc1.640028",AUDIO="audio",SUBTITLES="subs"
        video-720p-avc1.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="hvc1.1.6.L93.B0",AUDIO="audio",SUBTITLES="subs"
        video-720p-hvc1.m3u8
        """

    private static let mediaPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:6.0,
        seg0.ts
        #EXT-X-ENDLIST
        """

    // MARK: - SC-006: master=`master`; video IDs distinct; role IDs distinct

    @Test("master playlist ID is the reserved word 'master'")
    func masterIDIsReserved() async throws {
        let masterURL = URL(string: "https://example.com/master.m3u8")!
        let config = SessionConfig(nonInteractive: true)
        let harness = LiveSessionHarness(input: masterURL, config: config)
        wireHarness(harness, masterURL: masterURL)
        await harness.start()
        await harness.finish()

        let report = try await buildMarkdown(harness: harness)
        // Master ID should appear as `master` in the legend
        #expect(report.contains("`master`"))
        #expect(report.contains("master.m3u8") == false || legendContainsURL(report, "master.m3u8"))
    }

    @Test("video IDs are distinct for resolution-only differences")
    func videoIDsDistinctForResolutionDifferences() async throws {
        let masterURL = URL(string: "https://example.com/master.m3u8")!
        let config = SessionConfig(nonInteractive: true)
        let harness = LiveSessionHarness(input: masterURL, config: config)
        wireHarness(harness, masterURL: masterURL)
        await harness.start()
        await harness.finish()

        let entries = await harness.session.aliasRegistry.all
        let videoIDs = entries.filter { $0.role == .video }.map(\.alias)

        #expect(videoIDs.contains("1080p_avc1"), "Expected '1080p_avc1' in \(videoIDs)")
        #expect(videoIDs.contains("720p_avc1"), "Expected '720p_avc1' in \(videoIDs)")
        #expect(Set(videoIDs).count == videoIDs.count, "Video IDs must be unique: \(videoIDs)")
    }

    @Test("video IDs are distinct for codec-only differences at same resolution")
    func videoIDsDistinctForCodecDifferences() async throws {
        let masterURL = URL(string: "https://example.com/master.m3u8")!
        let config = SessionConfig(nonInteractive: true)
        let harness = LiveSessionHarness(input: masterURL, config: config)
        wireHarness(harness, masterURL: masterURL)
        await harness.start()
        await harness.finish()

        let entries = await harness.session.aliasRegistry.all
        let videoIDs = entries.filter { $0.role == .video }.map(\.alias)

        // Both 720p variants must differ by codec
        #expect(videoIDs.contains("720p_avc1"), "Expected '720p_avc1' in \(videoIDs)")
        #expect(videoIDs.contains("720p_hvc1"), "Expected '720p_hvc1' in \(videoIDs)")
    }

    @Test("audio role IDs are differentiated and correct")
    func audioRoleIDsAreDifferentiated() async throws {
        let masterURL = URL(string: "https://example.com/master.m3u8")!
        let config = SessionConfig(nonInteractive: true)
        let harness = LiveSessionHarness(input: masterURL, config: config)
        wireHarness(harness, masterURL: masterURL)
        await harness.start()
        await harness.finish()

        let entries = await harness.session.aliasRegistry.all
        let audioIDs = entries.filter { $0.role == .audio }.map(\.alias)

        #expect(audioIDs.contains("audio_en"), "Expected 'audio_en' in \(audioIDs)")
        #expect(audioIDs.contains("audio_en_commentary"), "Expected 'audio_en_commentary' in \(audioIDs)")
        #expect(Set(audioIDs).count == audioIDs.count, "Audio IDs must be unique: \(audioIDs)")
    }

    @Test("subtitles role ID is correct")
    func subtitlesRoleIDIsCorrect() async throws {
        let masterURL = URL(string: "https://example.com/master.m3u8")!
        let config = SessionConfig(nonInteractive: true)
        let harness = LiveSessionHarness(input: masterURL, config: config)
        wireHarness(harness, masterURL: masterURL)
        await harness.start()
        await harness.finish()

        let entries = await harness.session.aliasRegistry.all
        let subsIDs = entries.filter { $0.role == .subtitles }.map(\.alias)

        #expect(subsIDs.contains("subs_en"), "Expected 'subs_en' in \(subsIDs)")
    }

    @Test("iframe role ID uses resolution height")
    func iframeRoleIDUsesResolutionHeight() async throws {
        let masterURL = URL(string: "https://example.com/master.m3u8")!
        let config = SessionConfig(nonInteractive: true)
        let harness = LiveSessionHarness(input: masterURL, config: config)
        wireHarness(harness, masterURL: masterURL)
        await harness.start()
        await harness.finish()

        let entries = await harness.session.aliasRegistry.all
        let iframeIDs = entries.filter { $0.role == .iframe }.map(\.alias)

        #expect(iframeIDs.contains("iframe_1080p"), "Expected 'iframe_1080p' in \(iframeIDs)")
    }

    // MARK: - SC-007: IDs deterministic across runs

    @Test("identical input produces identical IDs across two runs")
    func identicalInputProducesIdenticalIDs() async throws {
        let masterURL = URL(string: "https://example.com/master.m3u8")!

        let harness1 = LiveSessionHarness(input: masterURL, config: SessionConfig(nonInteractive: true))
        wireHarness(harness1, masterURL: masterURL)
        await harness1.start()
        await harness1.finish()

        let harness2 = LiveSessionHarness(input: masterURL, config: SessionConfig(nonInteractive: true))
        wireHarness(harness2, masterURL: masterURL)
        await harness2.start()
        await harness2.finish()

        let ids1 = await harness1.session.aliasRegistry.all.map(\.alias)
        let ids2 = await harness2.session.aliasRegistry.all.map(\.alias)

        #expect(ids1 == ids2, "IDs must be identical across runs: \(ids1) vs \(ids2)")
    }

    @Test("playlist IDs are stable across refreshes")
    func playlistIDsAreStableAcrossRefreshes() async throws {
        let masterURL = URL(string: "https://example.com/live/master.m3u8")!
        let videoURL = URL(string: "https://example.com/live/video-1080p-avc1.m3u8")!
        let config = SessionConfig(nonInteractive: true)
        let harness = LiveSessionHarness(input: masterURL, config: config)

        // Use a simpler live master with one video variant for the refresh test
        let liveMaster = """
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028"
            video-1080p-avc1.m3u8
            """
        harness.fetcher.timeline(masterURL, [
            .init(at: .zero, reply: .body(liveMaster)),
            .init(at: .seconds(6), reply: .body(liveMaster)),
            .init(at: .seconds(12), reply: .body(liveMaster)),
        ])
        let liveMedia = """
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-TARGETDURATION:6
            #EXT-X-MEDIA-SEQUENCE:0
            #EXTINF:6.0,
            seg0.ts
            """
        harness.fetcher.timeline(videoURL, [
            .init(at: .zero, reply: .body(liveMedia)),
            .init(at: .seconds(6), reply: .body(liveMedia)),
        ])

        await harness.start()

        // Wait until the monitor is parked after the initial fetch, so the alias is registered.
        await harness.waitForSleepers(1)
        let idBeforeRefresh = await harness.session.aliasRegistry.alias(for: videoURL)?.alias

        // Advance one cadence to trigger a refresh, then capture ID again.
        await harness.step(by: 6, refreshing: videoURL)
        let idAfterRefresh = await harness.session.aliasRegistry.alias(for: videoURL)?.alias

        await harness.abortAndFinish()

        let before = try #require(idBeforeRefresh)
        let after = try #require(idAfterRefresh)
        #expect(before == after, "ID must be stable across refreshes: \(before) vs \(after)")
        #expect(before == "1080p_avc1")
    }

    // MARK: - Regression: live monitoring lines use the presentation ID, not the candidate ID

    /// Bug `live-status-wrong-id`: monitoring status lines (monitor-state changes, per-refresh
    /// `OK`/finding lines, traces) leaked the internal selection candidate ID (`variant-0`,
    /// `audio-5`) instead of the presentation ID shown by the roster/legend (`1080p_avc1`).
    @Test("live monitoring keys events on the presentation ID, never the candidate ID", .timeLimit(.minutes(1)))
    func monitoringUsesPresentationIDNotCandidateID() async throws {
        let masterURL = URL(string: "https://example.com/live/master.m3u8")!
        let videoURL = URL(string: "https://example.com/live/video-1080p-avc1.m3u8")!
        let config = SessionConfig(nonInteractive: true)
        let harness = LiveSessionHarness(input: masterURL, config: config)

        let liveMaster = """
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028"
            video-1080p-avc1.m3u8
            """
        harness.fetcher.timeline(masterURL, [
            .init(at: .zero, reply: .body(liveMaster)),
        ])
        harness.fetcher.timeline(videoURL, [
            .init(at: .zero, reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"]))),
        ])

        await harness.start()
        await harness.step(by: 6, refreshing: videoURL)

        let monitorStates = await harness.session.playlistMonitorStates
        await harness.abortAndFinish()

        // The monitored variant must be keyed by its presentation ID — the same ID the roster,
        // legend, and report use — not the internal candidate ID `variant-0`.
        #expect(monitorStates["1080p_avc1"] != nil,
                "Monitor state must be keyed by the presentation ID; got \(monitorStates)")
        #expect(monitorStates["variant-0"] == nil,
                "Monitor state must not be keyed by the internal candidate ID")
    }

    // MARK: - T030: Legend present in Markdown report

    @Test("Markdown report legend maps every ID to its full URL")
    func markdownLegendMapsIDsToURLs() async throws {
        let masterURL = URL(string: "https://example.com/master.m3u8")!
        let outputDir = FileManager.default.temporaryDirectory
            .appending(path: "PlaylistIDSchemeTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let config = SessionConfig(outputDir: outputDir, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: masterURL, config: config)
        wireHarness(harness, masterURL: masterURL)
        await harness.start()
        await harness.finish()

        let folder = try #require(await harness.session.sessionFolderURL)
        let reportMD = try String(contentsOf: folder.appending(path: "report.md"), encoding: .utf8)

        // Legend section must be present
        #expect(reportMD.contains("## Legend"), "Markdown report must contain a ## Legend section")

        // Legend must contain all registered aliases
        let entries = await harness.session.aliasRegistry.all
        for entry in entries {
            #expect(reportMD.contains(entry.alias), "Legend must contain alias '\(entry.alias)'")
            #expect(reportMD.contains(entry.url.absoluteString), "Legend must contain URL for '\(entry.alias)'")
        }
    }

    @Test("Markdown body (outside Legend) contains no raw playlist URLs")
    func markdownBodyOutsideLegendHasNoRawURLs() async throws {
        let masterURL = URL(string: "https://example.com/master.m3u8")!
        let outputDir = FileManager.default.temporaryDirectory
            .appending(path: "PlaylistIDSchemeTests-nourl-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let config = SessionConfig(outputDir: outputDir, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: masterURL, config: config)
        wireHarness(harness, masterURL: masterURL)
        await harness.start()
        await harness.finish()

        let folder = try #require(await harness.session.sessionFolderURL)
        let reportMD = try String(contentsOf: folder.appending(path: "report.md"), encoding: .utf8)

        // The header preamble table intentionally names the raw input URL (`| Stream | ... |`),
        // and the Legend table is the one section permitted to contain raw URLs (the mapping
        // from alias to URL); Legend is also the last section in the document. Everything
        // between Summary and Legend — Incident Timeline and the per-playlist blocks — must
        // use aliases only.
        guard
            let summaryRange = reportMD.range(of: "## Summary"),
            let legendRange = reportMD.range(of: "## Legend")
        else {
            Issue.record("No ## Summary or ## Legend section found in report")
            return
        }
        let bodyBetween = String(reportMD[summaryRange.lowerBound..<legendRange.lowerBound])

        #expect(bodyBetween.contains("https://") == false,
                "Body sections between Summary and Legend must not contain raw URLs")
    }

    // MARK: - Private helpers

    /// Wires the scripted fetcher with all URLs in the master playlist.
    private func wireHarness(_ harness: LiveSessionHarness, masterURL: URL) {
        let base = masterURL.deletingLastPathComponent()
        harness.fetcher.timeline(masterURL, [
            .init(at: .zero, reply: .body(Self.masterPlaylist)),
        ])
        for path in [
            "video-1080p-avc1.m3u8",
            "video-720p-avc1.m3u8",
            "video-720p-hvc1.m3u8",
            "audio-en-main.m3u8",
            "audio-en-commentary.m3u8",
            "subs-en.m3u8",
            "iframe-1080p.m3u8",
        ] {
            harness.fetcher.timeline(base.appending(path: path), [
                .init(at: .zero, reply: .body(Self.mediaPlaylist)),
            ])
        }
    }

    /// Returns the Markdown report string from a finished session (no archive required).
    private func buildMarkdown(harness: LiveSessionHarness) async throws -> String {
        let registry = await harness.session.aliasRegistry
        let builder = SessionReportBuilder()
        let snapshot = SessionReportBuilder.SessionSnapshot(
            id: "test-id-scheme",
            inputURL: URL(string: "https://example.com/master.m3u8")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_010),
            state: .completed,
            config: SessionConfig(nonInteractive: true),
            streamKind: .vod,
            lowLatencyDetected: false,
            encryptionDetected: false
        )
        return builder.buildMarkdown(
            session: snapshot,
            playlists: [],
            findings: [],
            aliasRegistry: registry
        )
    }

    /// Returns true if the URL appears only inside the Legend section of the report.
    private func legendContainsURL(_ md: String, _ urlFragment: String) -> Bool {
        guard let legendRange = md.range(of: "## Legend") else { return false }
        let fromLegend = String(md[legendRange.lowerBound...])
        let legendBody: String
        if let nextSection = fromLegend.range(of: "\n## ", range: fromLegend.index(fromLegend.startIndex, offsetBy: 9)..<fromLegend.endIndex) {
            legendBody = String(fromLegend[..<nextSection.lowerBound])
        }
        else {
            legendBody = fromLegend
        }
        return legendBody.contains(urlFragment)
    }
}

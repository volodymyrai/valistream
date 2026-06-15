//
//  SessionReportTimelineInfoTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite(.tags(.session))
struct SessionReportTimelineInfoTests {
    private let at = Date(timeIntervalSince1970: 1_750_000_000.123)
    private let masterURL = URL(string: "https://example.com/master.m3u8")!
    private let videoURL = URL(string: "https://example.com/video.m3u8")!

    @Test("markdown follows the report contract and preserves playlist information parity")
    func markdownContract() throws {
        let findings = makeFindings()
        let information = makePlaylistInformation()
        let timeline = IncidentTimeline(events: [
            (
                sequence: 2,
                event: TimestampedEvent(
                    at: at,
                    event: .finding(
                        findings[1],
                        evidence: .single(path: "playlists/video/video_1.m3u8")
                    )
                )
            ),
            (
                sequence: 1,
                event: TimestampedEvent(
                    at: at,
                    event: .finding(
                        findings[0],
                        evidence: .single(path: "playlists/master/master_0.m3u8")
                    )
                )
            ),
        ])
        let markdown = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(),
            playlists: makePlaylists(),
            findings: findings,
            aliasRegistry: makeRegistry(),
            artifactIndex: makeArtifactIndex(),
            timeline: timeline,
            playlistInformation: information,
            timeZone: .gmt
        )

        let sections = [
            "## Summary",
            "## Incident Timeline",
            "## Findings",
            "## Playlist Information",
            "## Legend",
            "## Session Details",
        ]
        let ranges = try sections.map { heading in
            try #require(markdown.range(of: heading), "Missing \(heading)")
        }
        #expect(zip(ranges, ranges.dropFirst()).allSatisfy { $0.lowerBound < $1.lowerBound })
        #expect(markdown.range(of: "## Summary")?.lowerBound == markdown.range(of: sections[0])?.lowerBound)
        #expect(markdown.contains("2025-06-15T15:06:40.123+00:00"))
        #expect(markdown.contains("> [!CAUTION]"))
        #expect(markdown.contains("> [!WARNING]"))
        #expect(markdown.contains("🔴 Error"))
        #expect(markdown.contains("🟡 Warning"))
        #expect(markdown.contains("🔵 Info"))
        #expect(markdown.contains("![") == false)
        #expect(markdown.contains("<table") == false)

        for playlist in information {
            for group in PlaylistInfoFormatter.groups(for: playlist) {
                #expect(markdown.contains(group.title))
                for field in group.fields {
                    #expect(markdown.contains("\(field.label):"))
                    #expect(markdown.contains(field.value))
                }
            }
        }
    }

    @Test("timeline links to one complete finding without duplicating message or evidence")
    func timelineFindingLink() {
        let finding = makeFindings()[0]
        let timeline = IncidentTimeline(events: [
            (
                sequence: 1,
                event: TimestampedEvent(
                    at: at,
                    event: .finding(
                        finding,
                        evidence: .single(path: "playlists/master/master_0.m3u8")
                    )
                )
            ),
        ])
        let markdown = SessionReportBuilder().buildMarkdown(
            session: makeSnapshot(),
            playlists: makePlaylists(),
            findings: [finding],
            aliasRegistry: makeRegistry(),
            artifactIndex: makeArtifactIndex(),
            timeline: timeline,
            playlistInformation: makePlaylistInformation(),
            timeZone: .gmt
        )

        #expect(markdown.contains("[Finding f-error](#finding-f-error)"))
        #expect(markdown.components(separatedBy: finding.message).count - 1 == 1)
        #expect(markdown.components(separatedBy: "playlists/master/master_0.m3u8").count - 1 == 1)
    }

    @Test("JSON schema v1 has no presentation-only fields")
    func jsonSchemaRemainsFrozen() throws {
        let data = try SessionReportBuilder().buildJSON(
            session: makeSnapshot(),
            playlists: makePlaylists(),
            findings: makeFindings(),
            artifactIndex: makeArtifactIndex()
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["timeline"] == nil)
        #expect(object["playlistInformation"] == nil)
    }

    private func makeSnapshot() -> SessionReportBuilder.SessionSnapshot {
        SessionReportBuilder.SessionSnapshot(
            id: "timeline-info",
            inputURL: masterURL,
            startedAt: at,
            endedAt: at.addingTimeInterval(10),
            state: .completed,
            config: SessionConfig(),
            streamKind: .vod,
            lowLatencyDetected: false,
            encryptionDetected: true
        )
    }

    private func makePlaylists() -> [SessionReportBuilder.PlaylistInfo] {
        [
            .init(
                id: "master",
                kind: .master,
                role: nil,
                url: masterURL,
                selected: true,
                refreshCount: 1
            ),
            .init(
                id: "video",
                kind: .media,
                role: .variant,
                url: videoURL,
                selected: true,
                refreshCount: 2
            ),
        ]
    }

    private func makeFindings() -> [Finding] {
        [
            makeFinding(
                id: "f-error",
                severity: .error,
                resource: masterURL,
                message: "Master declaration is invalid."
            ),
            makeFinding(
                id: "f-warning",
                severity: .warning,
                resource: videoURL,
                message: "Media delivery is delayed."
            ),
            makeFinding(
                id: "f-info",
                severity: .info,
                resource: videoURL,
                message: "Informational observation."
            ),
        ]
    }

    private func makeFinding(
        id: String,
        severity: Finding.Severity,
        resource: URL,
        message: String
    ) -> Finding {
        Finding(
            id: id,
            ruleId: "TOOL.\(id)",
            source: .tool,
            severity: severity,
            category: .delivery,
            resource: resource,
            location: nil,
            refreshIndex: 0,
            observedAt: at,
            message: message,
            context: [:]
        )
    }

    private func makeRegistry() -> AliasRegistry {
        var registry = AliasRegistry()
        registry.alias(for: masterURL, role: .master, attributes: [:])
        registry.alias(for: videoURL, role: .video, attributes: [:])
        return registry
    }

    private func makeArtifactIndex() -> [SessionArchive.IndexEntry] {
        [
            .init(
                requestId: "master-request",
                url: masterURL,
                bodyPath: "playlists/master/master_0.m3u8",
                metaPath: "playlists/master/master_0.meta.json"
            ),
            .init(
                requestId: "video-request",
                url: videoURL,
                bodyPath: "playlists/video/video_1.m3u8",
                metaPath: "playlists/video/video_1.meta.json"
            ),
        ]
    }

    private func makePlaylistInformation() -> [PlaylistInformation] {
        [
            PlaylistInformation(
                playlistID: "master",
                kind: .master,
                master: MasterInfo(
                    hlsVersion: 7,
                    independentSegments: true,
                    variantCount: 1,
                    uniqueMediaPlaylistCount: 1,
                    renditionCountsByType: [:],
                    iFrameStreamCount: 0,
                    distinctResolutions: ["1920x1080"],
                    distinctCodecs: ["avc1.640028"],
                    minimumBandwidth: 4_000_000,
                    maximumBandwidth: 4_000_000,
                    minimumFrameRate: 25,
                    maximumFrameRate: 25,
                    sessionProtection: .encryptedAES128
                ),
                media: nil
            ),
            PlaylistInformation(
                playlistID: "video",
                kind: .media,
                master: nil,
                media: MediaInfo(
                    playlistType: "VOD",
                    hlsVersion: 7,
                    segmentCount: 2,
                    totalListedDuration: 12,
                    targetDuration: 6,
                    medianSegmentDuration: 6,
                    minimumSegmentDuration: 6,
                    maximumSegmentDuration: 6,
                    mediaSequence: 0,
                    discontinuitySequence: 0,
                    discontinuityCount: 0,
                    endList: true,
                    independentSegments: true,
                    iFramesOnly: false,
                    segmentFormats: ["ts"],
                    byteRangeUsed: false,
                    programDateTimeAvailable: false,
                    protection: .encryptedAES128
                )
            ),
        ]
    }
}

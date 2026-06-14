//
//  EvidenceResolverTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

@testable import ValistreamCore
import Foundation
import Testing

import Foundation

@Suite(.tags(.session))
struct EvidenceResolverTests {
    private let playlistURL = URL(string: "https://example.com/video/main.m3u8")!

    private func makeFinding(
        severity: Finding.Severity = .warning,
        category: Finding.Category = .mediaPlaylist,
        resource: URL? = nil,
        refreshIndex: Int? = 2
    ) -> Finding {
        Finding(
            id: "f1",
            ruleId: "TOOL.test",
            source: .tool,
            severity: severity,
            category: category,
            resource: resource ?? playlistURL,
            location: nil,
            refreshIndex: refreshIndex,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            message: "Test finding",
            context: [:]
        )
    }

    private func makeRegistry() -> AliasRegistry {
        var registry = AliasRegistry()
        registry.alias(
            for: playlistURL,
            role: .video,
            attributes: ["RESOLUTION": "1920x1080", "CODECS": "avc1.640028"]
        )

        return registry
    }

    private func entry(url: URL, id: String = "1080p_avc1", index: Int) -> SessionArchive.IndexEntry {
        let label = SnapshotID.label(id: id, index: index)

        return SessionArchive.IndexEntry(
            requestId: "r\(index + 1)",
            url: url,
            bodyPath: "playlists/\(id)/\(label).m3u8",
            metaPath: "playlists/\(id)/\(label).meta.json"
        )
    }

    @Test("non-continuity errors and warnings resolve one snapshot", arguments: [Finding.Severity.error, .warning])
    func nonContinuityResolvesSingleSnapshot(severity: Finding.Severity) {
        let reference = EvidenceResolver().resolve(
            makeFinding(severity: severity),
            aliases: makeRegistry(),
            artifactIndex: [entry(url: playlistURL, index: 2)]
        )

        #expect(reference == .single(path: "playlists/1080p_avc1/1080p_avc1_2.m3u8"))
    }

    @Test("continuity resolves consecutive older and newer snapshots")
    func continuityResolvesPair() {
        let reference = EvidenceResolver().resolve(
            makeFinding(category: .continuity),
            aliases: makeRegistry(),
            artifactIndex: [
                entry(url: playlistURL, index: 1),
                entry(url: playlistURL, index: 2),
            ]
        )

        #expect(reference == .pair(
            older: "playlists/1080p_avc1/1080p_avc1_1.m3u8",
            newer: "playlists/1080p_avc1/1080p_avc1_2.m3u8"
        ))
    }

    @Test("missing body resolves unavailable using the registered ID")
    func missingBodyResolvesUnavailable() {
        var registry = AliasRegistry()
        registry.alias(for: playlistURL, role: .video)
        let reference = EvidenceResolver().resolve(
            makeFinding(refreshIndex: 0),
            aliases: registry,
            artifactIndex: []
        )

        #expect(reference == .unavailable(id: "video_1"))
    }

    @Test("continuity clearly preserves the available snapshot when one is missing")
    func continuityWithOneMissingSnapshot() {
        let reference = EvidenceResolver().resolve(
            makeFinding(category: .continuity),
            aliases: makeRegistry(),
            artifactIndex: [entry(url: playlistURL, index: 2)]
        )

        #expect(reference == .pair(
            older: nil,
            newer: "playlists/1080p_avc1/1080p_avc1_2.m3u8"
        ))
    }

    @Test("resolution joins on finding resource URL rather than unrelated report IDs")
    func joinsOnResourceURL() {
        let otherURL = URL(string: "https://example.com/video/other.m3u8")!
        let reference = EvidenceResolver().resolve(
            makeFinding(),
            aliases: makeRegistry(),
            artifactIndex: [
                entry(url: otherURL, id: "frozen-playlist-id", index: 2),
                entry(url: playlistURL, index: 2),
            ]
        )

        #expect(reference == .single(path: "playlists/1080p_avc1/1080p_avc1_2.m3u8"))
    }

    @Test("initial findings use snapshot zero")
    func nilRefreshIndexUsesSnapshotZero() {
        let reference = EvidenceResolver().resolve(
            makeFinding(refreshIndex: nil),
            aliases: makeRegistry(),
            artifactIndex: [entry(url: playlistURL, index: 0)]
        )

        #expect(reference == .single(path: "playlists/1080p_avc1/1080p_avc1_0.m3u8"))
    }
}

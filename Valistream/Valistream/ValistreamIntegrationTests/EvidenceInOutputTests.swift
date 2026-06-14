//
//  EvidenceInOutputTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import ValistreamCore
import Foundation
import Testing

@Suite("Evidence in terminal and report output")
struct EvidenceInOutputTests {
    @Test("scripted archive evidence is identical in terminal, report, and structured recovery")
    func evidenceSurfacesAndStructuredRecovery() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appending(path: "EvidenceInOutputTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }
        let playlistURL = URL(string: "https://example.com/live/main.m3u8")!
        let config = SessionConfig(outputDir: outputDir, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: playlistURL, config: config)
        harness.fetcher.timeline(playlistURL, [
            .init(at: .zero, reply: .body(Self.initialPlaylist)),
            .init(at: .seconds(6), reply: .body(Self.refreshedPlaylist)),
        ])
        harness.start()
        await harness.step(by: 6, refreshing: playlistURL)
        await harness.abortAndFinish()
        let folder = try #require(await harness.session.sessionFolderURL)
        let reportData = try Data(contentsOf: folder.appending(path: "report.json"))
        let reportObject = try #require(try JSONSerialization.jsonObject(with: reportData) as? [String: Any])
        let rawIndex = try #require(reportObject["artifactIndex"] as? [[String: Any]])
        let artifactIndex = try rawIndex.map { entry in
            let requestID = try #require(entry["requestId"] as? String)
            let urlString = try #require(entry["url"] as? String)
            let url = try #require(URL(string: urlString))
            let bodyPath = try #require(entry["bodyPath"] as? String)
            let metaPath = try #require(entry["metaPath"] as? String)

            return SessionArchive.IndexEntry(
                requestId: requestID,
                url: url,
                bodyPath: bodyPath,
                metaPath: metaPath
            )
        }
        var aliases = AliasRegistry()
        aliases.alias(for: playlistURL, role: .video)
        let findings = [
            makeFinding(id: "f-error", severity: .error, category: .mediaPlaylist, index: 1, url: playlistURL),
            makeFinding(id: "f-warn", severity: .warning, category: .delivery, index: 1, url: playlistURL),
            makeFinding(id: "f-continuity", severity: .warning, category: .continuity, index: 1, url: playlistURL),
        ]
        let resolver = EvidenceResolver()
        let terminalLines = findings.map { finding in
            resolver.resolve(finding, aliases: aliases, artifactIndex: artifactIndex)
                .terminalMessage(for: finding)
        }
        let snapshot = SessionReportBuilder.SessionSnapshot(
            id: "evidence-in-output",
            inputURL: playlistURL,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_006),
            state: .completed,
            config: config,
            streamKind: .live,
            lowLatencyDetected: false,
            encryptionDetected: false
        )
        let markdown = SessionReportBuilder().buildMarkdown(
            session: snapshot,
            playlists: [],
            findings: findings,
            aliasRegistry: aliases,
            artifactIndex: artifactIndex
        )
        for reference in findings.map({ resolver.resolve($0, aliases: aliases, artifactIndex: artifactIndex) }) {
            for path in reference.availablePaths {
                #expect(FileManager.default.fileExists(atPath: folder.appending(path: path).path(percentEncoded: false)))
                #expect(terminalLines.contains(where: { $0.contains(path) }))
                #expect(markdown.contains("`\(path)`"))
            }
        }
        let continuityLine = try #require(terminalLines.last)
        #expect(continuityLine.ranges(of: ".m3u8").count == 2)
        let unavailableURL = URL(string: "https://example.com/live/missing.m3u8")!
        var unavailableAliases = aliases
        unavailableAliases.alias(for: unavailableURL, role: .audio)
        let unavailableFinding = makeFinding(
            id: "f-missing",
            severity: .warning,
            category: .delivery,
            index: 0,
            url: unavailableURL
        )
        let unavailable = resolver.resolve(
            unavailableFinding,
            aliases: unavailableAliases,
            artifactIndex: artifactIndex
        )
        let unavailableLine = unavailable.terminalMessage(for: unavailableFinding)
        #expect(unavailableLine.contains("no body captured for audio_1"))
        #expect(unavailableLine.contains(unavailableURL.absoluteString) == false)
        #expect(unavailableLine.contains("playlists/audio_1") == false)
        let structuredData = try SessionReportBuilder().buildJSON(
            session: snapshot,
            playlists: [],
            findings: findings,
            artifactIndex: artifactIndex
        )
        let structured = try #require(try JSONSerialization.jsonObject(with: structuredData) as? [String: Any])
        let structuredFindings = try #require(structured["findings"] as? [[String: Any]])
        #expect(structuredFindings.allSatisfy { $0["evidence"] == nil })
        #expect(structuredFindings.allSatisfy { $0["resource"] != nil && $0["refreshIndex"] != nil })
    }



    // MARK: - Private

    private func makeFinding(
        id: String,
        severity: Finding.Severity,
        category: Finding.Category,
        index: Int,
        url: URL
    ) -> Finding {
        Finding(
            id: id,
            ruleId: "TOOL.evidence-test",
            source: .tool,
            severity: severity,
            category: category,
            resource: url,
            location: nil,
            refreshIndex: index,
            observedAt: Date(timeIntervalSince1970: 1_700_000_006),
            message: "Evidence output check",
            context: [:]
        )
    }

    private static let initialPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:10
        #EXTINF:6.0,
        seg10.ts
        #EXTINF:6.0,
        seg11.ts
        """

    private static let refreshedPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:11
        #EXTINF:6.0,
        seg11.ts
        #EXTINF:6.0,
        seg12.ts
        """
}

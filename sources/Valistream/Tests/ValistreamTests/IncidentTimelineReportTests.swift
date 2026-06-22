//
//  IncidentTimelineReportTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation
import Testing
import ValistreamCore

@Suite("Incident timeline report")
struct IncidentTimelineReportTests {
    @Test("archived reports contain deterministic linked incidents without duplication", .timeLimit(.minutes(1)))
    func archivedReport() async throws {
        let first = try await runSession(outputName: "first")
        let second = try await runSession(outputName: "second")

        #expect(first == second)
        #expect(first.contains("## Incident Timeline"))
        #expect(first.contains("## Playlist Information") == false)
        #expect(first.contains("\n## Findings") == false)
        #expect(first.contains("## Session Details") == false)
        #expect(first.contains("[Finding f1](#finding-f1)"))
        // The 404'd video never enters `playlists`, so its finding surfaces in the catch-all
        // section rather than a per-playlist block — but stays reachable from the timeline link.
        #expect(first.contains("## ⚠️ Unresolved Findings"))
        #expect(first.components(separatedBy: "HTTP status 404").count - 1 == 1)
        #expect(first.components(separatedBy: "no body captured").count - 1 == 1)
        let timeline = try section("## Incident Timeline", before: "## ", in: first)
        #expect(timeline.contains("Refreshed") == false)
        #expect(timeline.contains("HTTP status 404") == false)
        #expect(timeline.contains("no body captured") == false)
    }

    private func runSession(outputName: String) async throws -> String {
        let base = try #require(URL(string: "https://example.com/hls/"))
        let masterURL = base.appending(path: "master.m3u8")
        let videoURL = base.appending(path: "video.m3u8")
        let outputDirectory = FileManager.default.temporaryDirectory
            .appending(path: "valistream-us2-\(outputName)-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(masterURL, body: """
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-STREAM-INF:BANDWIDTH=1280000,CODECS="avc1.4d401f",RESOLUTION=1280x720
            video.m3u8
            """)
        fetcher.stub(videoURL, body: "", status: 404)
        let occurrence = Date(timeIntervalSince1970: 1_750_000_000.123)
        let session = ValidationSession(
            inputURL: masterURL,
            config: SessionConfig(
                outputDir: outputDirectory,
                nonInteractive: true,
                archiveEnabled: true
            ),
            fetcher: fetcher,
            id: "incident-report",
            now: { occurrence }
        )

        await session.run()

        let folder = try #require(await session.sessionFolderURL)
        return try String(contentsOf: folder.appending(path: "report.md"), encoding: .utf8)
    }

    private func section(_ heading: String, before nextHeading: String, in markdown: String) throws -> String {
        let start = try #require(markdown.range(of: heading))
        let suffix = markdown[start.upperBound...]
        let end = try #require(suffix.range(of: nextHeading))
        return String(suffix[..<end.lowerBound])
    }
}

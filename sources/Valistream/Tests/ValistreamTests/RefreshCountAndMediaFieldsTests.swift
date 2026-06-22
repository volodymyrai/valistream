//
//  RefreshCountAndMediaFieldsTests.swift
//  ValistreamIntegrationTests
//
//  Created by Codex on 16/06/2026.
//

import ValistreamCore
import Foundation
import Testing

@Suite("Refresh count and media report fields", .timeLimit(.minutes(1)))
struct RefreshCountAndMediaFieldsTests {
    @Test("aliased media refreshes join report information")
    func aliasedMediaRefreshesJoinReportInformation() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let masterURL = try #require(URL(string: "https://example.com/live/master.m3u8"))
        let mediaURL = try #require(URL(string: "https://example.com/live/video-1080p-avc1.m3u8"))
        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: masterURL, config: config)

        harness.fetcher.timeline(masterURL, [
            .init(at: .zero, reply: .body(Self.masterPlaylist)),
        ])
        harness.fetcher.timeline(mediaURL, [
            .init(at: .zero, reply: .body(LivePlaylists.window(
                mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(
                mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"]))),
            .init(at: .seconds(12), reply: .body(LivePlaylists.window(
                mediaSequence: 2, segments: ["s2.ts", "s3.ts", "s4.ts"]))),
        ])

        await harness.start()
        await harness.step(by: 6, refreshing: mediaURL)
        await harness.step(by: 6, refreshing: mediaURL)

        let folder = try #require(await harness.session.sessionFolderURL)
        let json = try reportJSON(in: folder)
        let playlists = try #require(json["playlists"] as? [[String: Any]])
        let master = try #require(playlists.first { $0["kind"] as? String == "master" })
        let media = try #require(playlists.first { $0["kind"] as? String == "media" })

        #expect(master["id"] as? String == "master")
        #expect(master["refreshCount"] as? Int == 1)
        #expect(media["id"] as? String == "1080p_avc1")
        #expect(media["id"] as? String != "variant-0")
        #expect(media["refreshCount"] as? Int == 3)

        let markdown = try String(contentsOf: folder.appending(path: "report.md"), encoding: .utf8)
        let masterBlock = try playlistBlock(id: "master", in: markdown)
        let mediaBlock = try playlistBlock(id: "1080p_avc1", in: markdown)

        #expect(markdown.contains("- Refreshes: 3"))
        #expect(masterBlock.contains("*Healthy · 1 variants · 1 refresh*"))
        #expect(masterBlock.contains("### Timing") == false)
        #expect(mediaBlock.contains("*Healthy · LIVE · 3 refreshes*"))
        #expect(mediaBlock.contains("- Type:"))
        #expect(mediaBlock.contains("### Timing"))

        await harness.abortAndFinish()
    }



    // MARK: - Private

    private static let masterPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,AVERAGE-BANDWIDTH=4800000,RESOLUTION=1920x1080,CODECS="avc1.640028"
        video-1080p-avc1.m3u8
        """

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "RefreshCountAndMediaFieldsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

private func playlistBlock(id: String, in markdown: String) throws -> String {
        let heading = "## ✅ \(id)"
        let headingRange = try #require(markdown.range(of: heading))
        let searchRange = headingRange.upperBound..<markdown.endIndex
        let end = markdown.range(of: "\n## ", range: searchRange)?.lowerBound ?? markdown.endIndex
        return String(markdown[headingRange.lowerBound..<end])
    }

    private func reportJSON(in folder: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: folder.appending(path: "report.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

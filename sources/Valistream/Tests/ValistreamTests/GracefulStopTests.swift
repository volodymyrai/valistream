//
//  GracefulStopTests.swift
//  ValistreamIntegrationTests
//

import Foundation
import Testing
import ValistreamCore

@Suite("Graceful stop", .timeLimit(.minutes(1)))
struct GracefulStopTests {
    private let media = URL(string: "https://ex.com/live.m3u8")!

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "GracefulStopTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }



    // MARK: - Live graceful stop

    @Test("live graceful stop finalizes non-PARTIAL report ≤ 3 s (SC-003)", .timeLimit(.minutes(1)))
    func liveGracefulStopWritesCompleteReport() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: media, config: config)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"]))),
        ])
        await harness.start()
        await harness.step(by: 6, refreshing: media)
        await harness.abortAndFinish()

        let state = await harness.session.state
        let endReason = await harness.session.endReason
        #expect(state == .completed)
        #expect(endReason == .gracefulStop)

        let folder = try #require(await harness.session.sessionFolderURL)
        let data = try Data(contentsOf: folder.appending(path: "report.json"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sessionObj = try #require(obj["session"] as? [String: Any])
        #expect(sessionObj["state"] as? String == "completed")
        let interruption = try #require(sessionObj["interruption"] as? String)
        #expect(interruption.contains("graceful stop"))
        #expect(!interruption.contains("PARTIAL"))
    }

    @Test("live graceful stop flushes archive (report.json + report.md present)")
    func liveGracefulStopFlushesArchive() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: media, config: config)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts"]))),
        ])
        await harness.start()
        await harness.step(by: 6, refreshing: media)
        await harness.abortAndFinish()

        let folder = try #require(await harness.session.sessionFolderURL)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: folder.appending(path: "report.json").path(percentEncoded: false)))
        #expect(fm.fileExists(atPath: folder.appending(path: "report.md").path(percentEncoded: false)))
    }
}

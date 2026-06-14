//
//  InterruptedSessionTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
import ValistreamCore

/// Tests that interrupting a live session mid-monitoring preserves all artifacts collected so far
/// and produces a final report marked as aborted (US3 acceptance 3, quickstart scenario 6).
@Suite("Interrupted session archive")
struct InterruptedSessionTests {
    private let media = URL(string: "https://ex.com/live.m3u8")!

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "InterruptedSessionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }



    // MARK: - Archive preserved on interrupt

    @Test("session folder exists with artifacts after abort", .timeLimit(.minutes(1)))
    func sessionFolderExistsAfterAbort() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: media, config: config)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"]))),
        ])
        harness.start()

        // Let at least one refresh cycle complete.
        await harness.step(by: 6, refreshing: media)

        await harness.abortAndFinish()

        let folderURL = await harness.session.sessionFolderURL
        let folder = try #require(folderURL)
        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test("initial playlist body is archived before abort", .timeLimit(.minutes(1)))
    func initialPlaylistArchivedBeforeAbort() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: media, config: config)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts"]))),
        ])
        harness.start()
        await harness.step(by: 6, refreshing: media)
        await harness.abortAndFinish()
        let folder = try #require(await harness.session.sessionFolderURL)
        let body = folder.appending(path: "playlists/video_1/video_1_0.m3u8")
        #expect(FileManager.default.fileExists(atPath: body.path(percentEncoded: false)))
    }

    @Test("findings.jsonl exists and contains at least the pre-abort findings", .timeLimit(.minutes(1)))
    func findingsJSONLPreservedOnAbort() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: media, config: config)
        // Stalling playlist — will produce staleness findings.
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
        ])
        harness.start()

        // Advance enough to trigger staleness (> 1.5 × TD = 9 s for TD=6).
        for _ in 0..<4 {
            await harness.step(by: 6, refreshing: media)
        }
        await harness.abortAndFinish()

        let folder = try #require(await harness.session.sessionFolderURL)
        let jsonlURL = folder.appending(path: "findings.jsonl")
        #expect(FileManager.default.fileExists(atPath: jsonlURL.path(percentEncoded: false)))

        let content = try String(contentsOf: jsonlURL, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.isEmpty == false)
        // Every line must be parseable JSON.
        for line in lines {
            #expect(throws: Never.self) {
                _ = try Finding.jsonDecoder.decode(Finding.self, from: Data(line.utf8))
            }
        }
    }

    @Test("report.json is written and state is aborted", .timeLimit(.minutes(1)))
    func reportWrittenWithAbortedState() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: media, config: config)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts"]))),
        ])
        harness.start()

        await harness.step(by: 6, refreshing: media)
        await harness.abortAndFinish()

        let folder = try #require(await harness.session.sessionFolderURL)
        let reportURL = folder.appending(path: "report.json")
        #expect(FileManager.default.fileExists(atPath: reportURL.path(percentEncoded: false)))

        let data = try Data(contentsOf: reportURL)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try #require(obj["session"] as? [String: Any])
        #expect(session["state"] as? String == "completed")
    }

    @Test("report.md is written after abort", .timeLimit(.minutes(1)))
    func reportMDWrittenAfterAbort() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: media, config: config)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(mediaSequence: 0, segments: ["s0.ts"]))),
        ])
        harness.start()

        await harness.step(by: 6, refreshing: media)
        await harness.abortAndFinish()

        let folder = try #require(await harness.session.sessionFolderURL)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "report.md").path(percentEncoded: false)))
    }
}

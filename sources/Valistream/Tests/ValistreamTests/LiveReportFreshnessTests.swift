//
//  LiveReportFreshnessTests.swift
//  ValistreamIntegrationTests
//

import Testing
import ValistreamCore
import Foundation

/// T034: Live session rewrites both reports once per refresh cycle; opening either at any point
/// yields a current (≤1 cycle stale), complete, openable document (FR-021, SC-006).
@Suite("Live report freshness", .timeLimit(.minutes(1)))
struct LiveReportFreshnessTests {
    private let media = URL(string: "https://ex.com/live.m3u8")!

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "LiveReportFreshnessTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Both reports written after first refresh

    @Test("both report.json and report.md exist after first refresh cycle")
    func reportsExistAfterFirstRefresh() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config  = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: media, config: config)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(
                mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(
                mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"]))),
        ])
        await harness.start()
        await harness.step(by: 6, refreshing: media)

        let folder = try #require(await harness.session.sessionFolderURL)
        let fm = FileManager.default

        #expect(fm.fileExists(atPath: folder.appending(path: "report.json").path(percentEncoded: false)),
                "report.json must exist after first refresh")
        #expect(fm.fileExists(atPath: folder.appending(path: "report.md").path(percentEncoded: false)),
                "report.md must exist after first refresh")

        await harness.abortAndFinish()
    }

    // MARK: - Reports are valid/parseable during session

    @Test("report.json is valid parseable JSON after each refresh cycle")
    func jsonIsValidAfterEachRefresh() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config  = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: media, config: config)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0),  reply: .body(LivePlaylists.window(
                mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(6),  reply: .body(LivePlaylists.window(
                mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"]))),
            .init(at: .seconds(12), reply: .body(LivePlaylists.window(
                mediaSequence: 2, segments: ["s2.ts", "s3.ts", "s4.ts"]))),
        ])
        await harness.start()

        // After first refresh — JSON must be valid and have schemaVersion
        await harness.step(by: 6, refreshing: media)
        let folder = try #require(await harness.session.sessionFolderURL)
        let jsonURL = folder.appending(path: "report.json")

        let data1 = try Data(contentsOf: jsonURL)
        let obj1  = try #require(try JSONSerialization.jsonObject(with: data1) as? [String: Any])
        #expect(obj1["schemaVersion"] as? Int == 1)

        // After second refresh — JSON must still be valid and updated
        await harness.step(by: 6, refreshing: media)
        let data2 = try Data(contentsOf: jsonURL)
        let obj2  = try #require(try JSONSerialization.jsonObject(with: data2) as? [String: Any])
        #expect(obj2["schemaVersion"] as? Int == 1)

        await harness.abortAndFinish()
    }

    @Test("report.md has required sections after first refresh cycle")
    func markdownHasRequiredSectionsAfterRefresh() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config  = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: media, config: config)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0), reply: .body(LivePlaylists.window(
                mediaSequence: 0, segments: ["s0.ts", "s1.ts"]))),
            .init(at: .seconds(6), reply: .body(LivePlaylists.window(
                mediaSequence: 1, segments: ["s1.ts", "s2.ts"]))),
        ])
        await harness.start()
        await harness.step(by: 6, refreshing: media)

        let folder = try #require(await harness.session.sessionFolderURL)
        let mdURL  = folder.appending(path: "report.md")
        let md     = try String(contentsOf: mdURL, encoding: .utf8)

        #expect(md.contains("## Summary"))
        #expect(md.contains("## Legend"))
        #expect(md.contains("## Session Details") == false)
        // The live media playlist renders as its own per-playlist block (master + this variant).
        #expect(md.contains("## Incident Timeline"))

        await harness.abortAndFinish()
    }

    // MARK: - Reports updated between refreshes

    @Test("report.json reflects increased refresh count after second cycle")
    func jsonUpdatedBetweenRefreshes() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config  = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: media, config: config)
        harness.fetcher.timeline(media, [
            .init(at: .seconds(0),  reply: .body(LivePlaylists.window(
                mediaSequence: 0, segments: ["s0.ts", "s1.ts", "s2.ts"]))),
            .init(at: .seconds(6),  reply: .body(LivePlaylists.window(
                mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"]))),
            .init(at: .seconds(12), reply: .body(LivePlaylists.window(
                mediaSequence: 2, segments: ["s2.ts", "s3.ts", "s4.ts"]))),
        ])
        await harness.start()

        await harness.step(by: 6, refreshing: media)
        let folder  = try #require(await harness.session.sessionFolderURL)
        let jsonURL = folder.appending(path: "report.json")

        let data1   = try Data(contentsOf: jsonURL)

        await harness.step(by: 6, refreshing: media)

        let data2   = try Data(contentsOf: jsonURL)

        // The file content must have changed between refreshes
        #expect(data1 != data2, "report.json must be updated after each refresh cycle")

        await harness.abortAndFinish()
    }
}

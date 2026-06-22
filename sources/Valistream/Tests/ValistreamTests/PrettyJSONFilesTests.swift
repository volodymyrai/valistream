//
//  PrettyJSONFilesTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import ValistreamCore
import Foundation
import Testing

/// US5 / T037 — structured report + *.meta.json sidecars on disk are pretty-printed;
/// the --json NDJSON stream remains compact (one object per line).
@Suite("Pretty JSON files on disk (US5)")
struct PrettyJSONFilesTests {

    private let playlistURL = URL(string: "https://example.com/live/main.m3u8")!

    private var mediaPlaylist: String {
        LivePlaylists.window(mediaSequence: 0, segments: ["seg0.ts", "seg1.ts"])
    }

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "PrettyJSONFilesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }


    // MARK: - On-disk report is pretty-printed

    @Test("report.json on disk is multi-line (pretty-printed)", .timeLimit(.minutes(1)))
    func reportIsPrettyPrinted() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: playlistURL, config: config)
        harness.fetcher.timeline(playlistURL, [
            .init(at: .zero, reply: .body(mediaPlaylist)),
        ])
        await harness.start()
        await harness.abortAndFinish()

        let folder = try #require(await harness.session.sessionFolderURL)
        let reportURL = folder.appending(path: "report.json")
        #expect(FileManager.default.fileExists(atPath: reportURL.path(percentEncoded: false)))

        let data = try Data(contentsOf: reportURL)
        let json = try #require(String(data: data, encoding: .utf8))

        // Pretty-printed JSON must contain newlines and indentation spaces
        #expect(json.contains("\n"))
        #expect(json.contains("  "))
    }

    @Test("report.json is schema-valid after pretty-printing", .timeLimit(.minutes(1)))
    func reportIsSchemaValid() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: playlistURL, config: config)
        harness.fetcher.timeline(playlistURL, [
            .init(at: .zero, reply: .body(mediaPlaylist)),
        ])
        await harness.start()
        await harness.abortAndFinish()

        let folder = try #require(await harness.session.sessionFolderURL)
        let reportURL = folder.appending(path: "report.json")
        let data = try Data(contentsOf: reportURL)

        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Required top-level schema keys
        #expect(obj["schemaVersion"] != nil)
        #expect(obj["session"] != nil)
        #expect(obj["playlists"] != nil)
        #expect(obj["findings"] != nil)
        #expect(obj["summary"] != nil)
        #expect(obj["artifactIndex"] != nil)
    }


    // MARK: - Sidecar *.meta.json is pretty-printed

    @Test("*.meta.json sidecar is multi-line (pretty-printed)", .timeLimit(.minutes(1)))
    func sidecarIsPrettyPrinted() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: playlistURL, config: config)
        harness.fetcher.timeline(playlistURL, [
            .init(at: .zero, reply: .body(mediaPlaylist)),
            .init(at: .seconds(6), reply: .body(mediaPlaylist)),
        ])
        await harness.start()
        // Advance one refresh cycle so the playlist body is archived
        await harness.step(by: 6, refreshing: playlistURL)
        await harness.abortAndFinish()

        let folder = try #require(await harness.session.sessionFolderURL)
        let playlistsDir = folder.appending(path: "playlists", directoryHint: .isDirectory)

        // Find all *.meta.json files in playlist subfolders
        let fm = FileManager.default
        let playlistsDirPath = playlistsDir.path(percentEncoded: false)
        #expect(fm.fileExists(atPath: playlistsDirPath), "playlists/ directory must exist when archiveEnabled")

        let subdirs = try fm.contentsOfDirectory(
            at: playlistsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        var foundSidecar = false
        for subdir in subdirs {
            let contents = try fm.contentsOfDirectory(
                at: subdir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            for item in contents where item.pathExtension == "json" {
                let data = try Data(contentsOf: item)
                let json = try #require(String(data: data, encoding: .utf8))
                #expect(json.contains("\n"), "sidecar \(item.lastPathComponent) must be multi-line")
                #expect(json.contains("  "), "sidecar \(item.lastPathComponent) must be indented")
                foundSidecar = true
            }
        }
        #expect(foundSidecar, "At least one *.meta.json sidecar must exist")
    }

    @Test("*.meta.json sidecar contains expected fields", .timeLimit(.minutes(1)))
    func sidecarIsSchemaValid() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: playlistURL, config: config)
        harness.fetcher.timeline(playlistURL, [
            .init(at: .zero, reply: .body(mediaPlaylist)),
            .init(at: .seconds(6), reply: .body(mediaPlaylist)),
        ])
        await harness.start()
        // Advance one refresh cycle so the playlist body is archived
        await harness.step(by: 6, refreshing: playlistURL)
        await harness.abortAndFinish()

        let folder = try #require(await harness.session.sessionFolderURL)
        let playlistsDir = folder.appending(path: "playlists", directoryHint: .isDirectory)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: playlistsDir.path(percentEncoded: false)), "playlists/ directory must exist")

        let subdirs = try fm.contentsOfDirectory(at: playlistsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        var checkedCount = 0
        for subdir in subdirs {
            let contents = try fm.contentsOfDirectory(at: subdir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for item in contents where item.pathExtension == "json" {
                let data = try Data(contentsOf: item)
                let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(obj["requestId"] != nil, "meta.json must have requestId")
                #expect(obj["url"] != nil, "meta.json must have url")
                #expect(obj["responseTimeMs"] != nil, "meta.json must have responseTimeMs")
                if let ts = obj["requestStartedAt"] as? String {
                    #expect(ts.contains("."), "requestStartedAt must include milliseconds")
                    #expect(ts.hasSuffix("+00:00"), "requestStartedAt must use +00:00 offset, not Z")
                }
                checkedCount += 1
            }
        }
        #expect(checkedCount > 0, "At least one *.meta.json sidecar must be schema-valid")
    }


    // MARK: - --json stream stays compact

    @Test("Finding.jsonEncoder (stream) emits a single compact line per finding")
    func streamEncoderIsCompact() throws {
        let resource = URL(string: "https://example.com/hls/main.m3u8")!
        let finding = Finding(
            id: "f-stream",
            ruleId: "TOOL.delivery",
            source: .tool,
            severity: .warning,
            category: .delivery,
            resource: resource,
            location: nil,
            refreshIndex: 0,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            message: "slow response",
            context: [:]
        )
        let data = try Finding.jsonEncoder.encode(finding)
        let json = try #require(String(data: data, encoding: .utf8))

        // Must be a single line — no embedded newline
        #expect(json.contains("\n") == false)
        let lines = json.components(separatedBy: "\n")
        #expect(lines.count == 1)
    }

    @Test("Finding.jsonEncoder is compact; prettyJSONEncoder is not — same logical content")
    func compactAndPrettyDecodeIdentically() throws {
        let resource = URL(string: "https://example.com/hls/main.m3u8")!
        let finding = Finding(
            id: "f-both",
            ruleId: "RFC8216.4.3.4.1",
            source: .rfc8216,
            severity: .error,
            category: .masterPlaylist,
            resource: resource,
            location: nil,
            refreshIndex: 2,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            message: "Missing BANDWIDTH",
            context: [:]
        )
        let compact = try Finding.jsonEncoder.encode(finding)
        let pretty = try Finding.prettyJSONEncoder.encode(finding)

        let compactStr = try #require(String(data: compact, encoding: .utf8))
        let prettyStr = try #require(String(data: pretty, encoding: .utf8))

        // Compact = no newlines; pretty = multi-line
        #expect(compactStr.contains("\n") == false)
        #expect(prettyStr.contains("\n"))

        // Both decode to same logical finding
        let decodedCompact = try Finding.jsonDecoder.decode(Finding.self, from: compact)
        let decodedPretty = try Finding.jsonDecoder.decode(Finding.self, from: pretty)
        #expect(decodedCompact == decodedPretty)
    }
}

//
//  SessionArchiveTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite(.tags(.archive))
struct SessionArchiveTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "SessionArchiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeResult(url: URL, body: String, status: Int = 200) -> FetchResult {
        FetchResult(
            url: url,
            body: Data(body.utf8),
            metadata: ResponseMetadata(
                requestHeaders: [:],
                requestStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
                responseEndedAt: Date(timeIntervalSince1970: 1_700_000_001),
                remoteAddress: nil,
                remotePort: nil,
                httpStatus: status,
                responseHeaders: [:],
                negotiatedProtocol: nil,
                redirectChain: []
            ),
            outcome: .success
        )
    }



    // MARK: - Init

    @Test("creates the session folder on init")
    func createsFolderOnInit() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = try SessionArchive(sessionID: "test-001", outputDir: tmp)
        let folder = archive.sessionFolder
        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
        #expect(folder.lastPathComponent == "test-001")
    }



    // MARK: - Store

    @Test("first store uses the snapshot label for body and metadata names")
    func firstStoreUsesSnapshotLabel() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = try SessionArchive(sessionID: "s1", outputDir: tmp)
        let url = URL(string: "https://ex.com/v.m3u8")!
        let body = "#EXTM3U\n#EXT-X-ENDLIST\n"
        let record = try await archive.store(
            result: makeResult(url: url, body: body),
            playlistID: "1080p_avc1"
        )
        let bodyPath = archive.sessionFolder.appending(path: "playlists/1080p_avc1/1080p_avc1_0.m3u8")
        let metaPath = archive.sessionFolder.appending(path: "playlists/1080p_avc1/1080p_avc1_0.meta.json")
        #expect(FileManager.default.fileExists(atPath: bodyPath.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: metaPath.path(percentEncoded: false)))
        #expect(try Data(contentsOf: bodyPath) == Data(body.utf8))
        #expect(record.bodyPath == "playlists/1080p_avc1/1080p_avc1_0.m3u8")
        #expect(bodyPath.deletingPathExtension().lastPathComponent == "1080p_avc1_0")
    }

    @Test("body is stored byte-exact")
    func bodyByteExact() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = try SessionArchive(sessionID: "s2", outputDir: tmp)
        let bytes = Data([0xFF, 0x00, 0xAB, 0xCD])
        let result = FetchResult(
            url: URL(string: "https://ex.com/seg.ts")!,
            body: bytes,
            metadata: ResponseMetadata(
                requestHeaders: [:],
                requestStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
                responseEndedAt: Date(timeIntervalSince1970: 1_700_000_001),
                remoteAddress: nil,
                remotePort: nil,
                httpStatus: 200,
                responseHeaders: [:],
                negotiatedProtocol: nil,
                redirectChain: []
            ),
            outcome: .success
        )
        try await archive.store(result: result, playlistID: "p1")
        let bodyPath = archive.sessionFolder.appending(path: "playlists/p1/p1_0.m3u8")
        #expect(try Data(contentsOf: bodyPath) == bytes)
    }

    @Test("sidecar contains every ArtifactRecord field")
    func sidecarContainsAllFields() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = try SessionArchive(sessionID: "s3", outputDir: tmp)
        let url = URL(string: "https://ex.com/m.m3u8")!
        let record = try await archive.store(
            result: makeResult(url: url, body: "#EXTM3U\n"),
            playlistID: "master"
        )
        let metaPath = archive.sessionFolder.appending(path: "playlists/master/master_0.meta.json")
        let decoded = try Finding.jsonDecoder.decode(ArtifactRecord.self, from: Data(contentsOf: metaPath))
        #expect(decoded.requestId == record.requestId)
        #expect(decoded.url == url)
        #expect(decoded.bodyPath == "playlists/master/master_0.m3u8")
        #expect(decoded.bodyBytes == Data("#EXTM3U\n".utf8).count)
    }

    @Test("second store increments the snapshot index")
    func secondStoreIncrementsIndex() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = try SessionArchive(sessionID: "s4", outputDir: tmp)
        let url = URL(string: "https://ex.com/live.m3u8")!
        try await archive.store(result: makeResult(url: url, body: "body0"), playlistID: "live")
        let record = try await archive.store(result: makeResult(url: url, body: "body1"), playlistID: "live")
        #expect(record.bodyPath == "playlists/live/live_1.m3u8")
        let bodyPath = archive.sessionFolder.appending(path: "playlists/live/live_1.m3u8")
        #expect(try Data(contentsOf: bodyPath) == Data("body1".utf8))
    }

    @Test("different playlist IDs produce unique folders and names")
    func differentPlaylistsSeparateFolders() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = try SessionArchive(sessionID: "s5", outputDir: tmp)
        let url = URL(string: "https://ex.com/p.m3u8")!
        try await archive.store(result: makeResult(url: url, body: "a"), playlistID: "1080p_avc1")
        try await archive.store(result: makeResult(url: url, body: "b"), playlistID: "audio_1")
        let video = archive.sessionFolder.appending(path: "playlists/1080p_avc1/1080p_avc1_0.m3u8")
        let audio = archive.sessionFolder.appending(path: "playlists/audio_1/audio_1_0.m3u8")
        #expect(FileManager.default.fileExists(atPath: video.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: audio.path(percentEncoded: false)))
        #expect(video != audio)
    }

    @Test("artifact index shape stays unchanged while path values use snapshot labels")
    func artifactIndexUsesSnapshotPaths() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = try SessionArchive(sessionID: "s6", outputDir: tmp)
        let url = URL(string: "https://ex.com/p.m3u8")!
        try await archive.store(result: makeResult(url: url, body: "a"), playlistID: "master")
        let index = await archive.artifactIndex
        let entry = try #require(index.first)
        #expect(entry.requestId == "r1")
        #expect(entry.url == url)
        #expect(entry.bodyPath == "playlists/master/master_0.m3u8")
        #expect(entry.metaPath == "playlists/master/master_0.meta.json")
    }

    @Test("artifact index accumulates entries across stores")
    func artifactIndexAccumulates() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = try SessionArchive(sessionID: "s7", outputDir: tmp)
        let url = URL(string: "https://ex.com/p.m3u8")!
        try await archive.store(result: makeResult(url: url, body: "a"), playlistID: "p1")
        try await archive.store(result: makeResult(url: url, body: "b"), playlistID: "p2")
        try await archive.store(result: makeResult(url: url, body: "c"), playlistID: "p1")
        let index = await archive.artifactIndex
        #expect(index.count == 3)
        #expect(index.map(\.requestId) == ["r1", "r2", "r3"])
        #expect(index.map(\.bodyPath) == [
            "playlists/p1/p1_0.m3u8",
            "playlists/p2/p2_0.m3u8",
            "playlists/p1/p1_1.m3u8",
        ])
    }

    @Test("request IDs remain monotonic across playlists")
    func requestIdMonotonic() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let archive = try SessionArchive(sessionID: "s8", outputDir: tmp)
        let url = URL(string: "https://ex.com/p.m3u8")!
        let first = try await archive.store(result: makeResult(url: url, body: "x"), playlistID: "master")
        let second = try await archive.store(result: makeResult(url: url, body: "y"), playlistID: "video_1")
        #expect(first.requestId == "r1")
        #expect(second.requestId == "r2")
    }
}

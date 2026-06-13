//
//  FinalizationTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite("Finalization", .tags(.session), .timeLimit(.minutes(1)))
struct FinalizationTests {

    // MARK: - Helpers

    private let masterURL = URL(string: "https://test.example/master.m3u8")!
    private let liveURL   = URL(string: "https://test.example/live.m3u8")!
    private let epoch     = Date(timeIntervalSince1970: 1_700_000_000)

    private struct StubFetcher: StreamFetching {
        let responses: [URL: String]
        func fetch(_ url: URL) async -> FetchResult {
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            let outcome: FetchOutcome = responses[url] != nil
                ? .success
                : .transportError(description: "no stub")
            return FetchResult(
                url: url,
                body: Data((responses[url] ?? "").utf8),
                metadata: ResponseMetadata(
                    requestHeaders: [:],
                    requestStartedAt: now,
                    responseEndedAt: now,
                    remoteAddress: nil,
                    remotePort: nil,
                    httpStatus: 200,
                    responseHeaders: [:],
                    negotiatedProtocol: nil,
                    redirectChain: []
                ),
                outcome: outcome
            )
        }
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "FinalizationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeVODSession(outputDir: URL? = nil) -> ValidationSession {
        let mediaURL = URL(string: "https://test.example/v0.m3u8")!
        let fetcher = StubFetcher(responses: [
            masterURL: masterPlaylist,
            mediaURL:  vodMedia,
        ])
        var config = SessionConfig(nonInteractive: true)
        if let outputDir {
            config = SessionConfig(outputDir: outputDir, nonInteractive: true, archiveEnabled: true)
        }
        return ValidationSession(
            inputURL: masterURL,
            config: config,
            fetcher: fetcher,
            id: "fin-vod-test",
            now: { self.epoch }
        )
    }

    private func makeLiveSession(
        timeLimit: Duration? = nil,
        outputDir: URL? = nil
    ) -> ValidationSession {
        let fetcher = StubFetcher(responses: [liveURL: liveMedia])
        let config: SessionConfig
        if let outputDir {
            config = SessionConfig(
                timeLimit: timeLimit,
                outputDir: outputDir,
                nonInteractive: true,
                archiveEnabled: true
            )
        } else {
            config = SessionConfig(
                timeLimit: timeLimit,
                nonInteractive: true
            )
        }
        let epoch = self.epoch
        return ValidationSession(
            inputURL: liveURL,
            config: config,
            fetcher: fetcher,
            id: "fin-live-test",
            now: { epoch },
            sleep: { _ in try Task.checkCancellation() }
        )
    }



    // MARK: - Completed state tests

    @Test("VOD run completes in .completed state")
    func vodRunCompletesAsCompleted() async {
        let session = makeVODSession()
        await session.run()
        let state = await session.state
        #expect(state == .completed)
    }

    @Test("live run with endlist reaches .completed state")
    func liveEndlistReachesCompleted() async {
        let fetcher = StubFetcher(responses: [liveURL: liveMediaEndlist])
        let session = ValidationSession(
            inputURL: liveURL,
            config: SessionConfig(nonInteractive: true),
            fetcher: fetcher,
            id: "fin-endlist-test",
            now: { self.epoch },
            sleep: { _ in }
        )
        await session.run()
        let state = await session.state
        #expect(state == .completed)
    }



    // MARK: - Graceful stop — state

    @Test("abort() before run() still ends in .completed state")
    func abortBeforeRunEndsCompleted() async {
        let session = makeVODSession()
        await session.abort()
        await session.run()
        let state = await session.state
        #expect(state == .completed)
    }

    @Test("abort() during live monitoring ends in .completed state (not .aborted)")
    func abortDuringLiveEndsCompleted() async {
        let fetcher = StubFetcher(responses: [liveURL: liveMedia])
        let session = ValidationSession(
            inputURL: liveURL,
            config: SessionConfig(nonInteractive: true),
            fetcher: fetcher,
            id: "fin-live-abort-test",
            now: { self.epoch },
            sleep: { _ in try Task.checkCancellation() }
        )
        let task = Task { await session.run() }
        await Task.yield()
        await session.abort()
        task.cancel()
        await task.value
        let state = await session.state
        #expect(state == .completed)
    }



    // MARK: - Graceful stop — PARTIAL marker in report

    @Test("abort before run writes 'graceful stop — PARTIAL' interruption to report")
    func abortBeforeRunWritesPartialInterruption() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let session = makeVODSession(outputDir: tmp)
        await session.abort()
        await session.run()

        let folder = try #require(await session.sessionFolderURL)
        let data = try Data(contentsOf: folder.appending(path: "report.json"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sessionObj = try #require(obj["session"] as? [String: Any])
        let interruption = try #require(sessionObj["interruption"] as? String)
        #expect(interruption.contains("PARTIAL"))
    }

    @Test("abort on live session writes 'graceful stop' interruption without PARTIAL")
    func abortOnLiveWritesNonPartialInterruption() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let session = makeLiveSession(outputDir: tmp)
        let task = Task { await session.run() }
        await Task.yield()
        await session.abort()
        task.cancel()
        await task.value

        let folder = try #require(await session.sessionFolderURL)
        let data = try Data(contentsOf: folder.appending(path: "report.json"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sessionObj = try #require(obj["session"] as? [String: Any])
        let interruption = try #require(sessionObj["interruption"] as? String)
        #expect(interruption.contains("graceful stop"))
        #expect(!interruption.contains("PARTIAL"))
    }



    // MARK: - Time limit

    @Test("time-limit expiry ends in .completed state")
    func timeLimitExpiryEndsCompleted() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // .seconds(0) → deadline == now() → triggers immediately on first loop check.
        let session = makeLiveSession(
            timeLimit: .seconds(0),
            outputDir: tmp
        )
        await session.run()
        let state = await session.state
        #expect(state == .completed)
    }

    @Test("time-limit expiry writes 'time limit' interruption to report")
    func timeLimitWritesInterruption() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let session = makeLiveSession(
            timeLimit: .seconds(0),
            outputDir: tmp
        )
        await session.run()

        let folder = try #require(await session.sessionFolderURL)
        let data = try Data(contentsOf: folder.appending(path: "report.json"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sessionObj = try #require(obj["session"] as? [String: Any])
        let interruption = try #require(sessionObj["interruption"] as? String)
        #expect(interruption == "time limit")
    }



    // MARK: - Fixtures

    private let masterPlaylist = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1280000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720
        v0.m3u8
        """

    private let vodMedia = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:6.0,
        seg0.ts
        #EXT-X-ENDLIST
        """

    private let liveMedia = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:6.0,
        seg0.ts
        #EXTINF:6.0,
        seg1.ts
        #EXTINF:6.0,
        seg2.ts
        """

    private let liveMediaEndlist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:6.0,
        seg0.ts
        #EXT-X-ENDLIST
        """
}

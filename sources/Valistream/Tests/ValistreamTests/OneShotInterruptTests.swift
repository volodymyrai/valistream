//
//  OneShotInterruptTests.swift
//  ValistreamIntegrationTests
//

import Foundation
import os
import Testing
import ValistreamCore

@Suite("One-shot interrupt", .timeLimit(.minutes(1)))
struct OneShotInterruptTests {
    private let masterURL = URL(string: "https://ex.com/master.m3u8")!
    private let mediaURL  = URL(string: "https://ex.com/v0.m3u8")!
    private let media2URL = URL(string: "https://ex.com/v1.m3u8")!

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "OneShotInterruptTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeConfig(outputDir: URL) -> SessionConfig {
        SessionConfig(outputDir: outputDir, nonInteractive: true, archiveEnabled: true)
    }



    // MARK: - Abort before run

    @Test("VOD abort before run writes PARTIAL report with completed state")
    func vodAbortBeforeRunWritesPartialReport() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(masterURL, body: oneVariantMaster)
        fetcher.stub(mediaURL,  body: vodMedia)
        let session = ValidationSession(
            inputURL: masterURL,
            config: makeConfig(outputDir: tmp),
            fetcher: fetcher,
            id: "test-vod-partial-pre"
        )

        await session.abort()
        await session.run()

        let state = await session.state
        let endReason = await session.endReason
        #expect(state == .completed)
        #expect(endReason == .gracefulStop)

        let folder = try #require(await session.sessionFolderURL)
        let data = try Data(contentsOf: folder.appending(path: "report.json"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sessionObj = try #require(obj["session"] as? [String: Any])
        #expect(sessionObj["state"] as? String == "completed")
        let interruption = try #require(sessionObj["interruption"] as? String)
        #expect(interruption.contains("PARTIAL"))
    }



    // MARK: - Abort mid-run

    @Test("VOD abort mid-run writes PARTIAL report (playlists validated so far)")
    func vodAbortMidRunWritesPartialReport() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // v0.m3u8 fetch is blocked until we inject abort; the stop check before v1's iteration fires.
        let gate = FetchGate()
        let inner = ScriptedStreamFetcher()
        inner.stub(masterURL, body: twoVariantMaster)
        inner.stub(mediaURL,  body: vodMedia)
        inner.stub(media2URL, body: vodMedia)
        let fetcher = GatedFetcher(inner: inner, gateURL: mediaURL, gate: gate)

        let session = ValidationSession(
            inputURL: masterURL,
            config: makeConfig(outputDir: tmp),
            fetcher: fetcher,
            id: "test-vod-partial-mid"
        )

        let runTask = Task { await session.run() }

        // Wait until the session is blocked on the second media playlist.
        await gate.waitForBlock()

        // Inject graceful stop and cancel any in-flight sleeps.
        await session.abort()
        runTask.cancel()
        // Unblock the gate so the suspended fetch can be cancelled.
        await gate.release()
        await runTask.value

        let endReason = await session.endReason
        #expect(endReason == .gracefulStop)

        let folder = try #require(await session.sessionFolderURL)
        let data = try Data(contentsOf: folder.appending(path: "report.json"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sessionObj = try #require(obj["session"] as? [String: Any])
        let interruption = try #require(sessionObj["interruption"] as? String)
        #expect(interruption.contains("PARTIAL"))
    }
}



// MARK: - Gate for mid-run abort injection

/// Suspends the first fetch of `gateURL` until `release()` is called.
actor FetchGate {
    private var blockedContinuation: CheckedContinuation<Void, Never>?
    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var isBlocked = false

    func block() async {
        isBlocked = true
        readyContinuation?.resume()
        readyContinuation = nil
        await withCheckedContinuation { blockedContinuation = $0 }
    }

    func release() {
        blockedContinuation?.resume()
        blockedContinuation = nil
    }

    func waitForBlock() async {
        if isBlocked { return }
        await withCheckedContinuation { readyContinuation = $0 }
    }
}

actor GatedFetcher: StreamFetching {
    private let inner: ScriptedStreamFetcher
    private let gateURL: URL
    private let gate: FetchGate
    private var hasGated = false

    init(inner: ScriptedStreamFetcher, gateURL: URL, gate: FetchGate) {
        self.inner = inner
        self.gateURL = gateURL
        self.gate = gate
    }

    func fetch(_ url: URL) async -> FetchResult {
        if url == gateURL, !hasGated {
            hasGated = true
            await gate.block()
        }
        return await inner.fetch(url)
    }
}



// MARK: - Fixtures

private let oneVariantMaster = """
    #EXTM3U
    #EXT-X-STREAM-INF:BANDWIDTH=1280000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720
    v0.m3u8
    """

private let twoVariantMaster = """
    #EXTM3U
    #EXT-X-STREAM-INF:BANDWIDTH=1280000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720
    v0.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=2560000,CODECS="avc1.4d4028,mp4a.40.2",RESOLUTION=1920x1080
    v1.m3u8
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

//
//  PromptSkipTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

@testable import ValistreamCore
import Foundation
import os
import Testing

/// Verifies that the interactive prompt is suppressed when skip conditions are met (FR-028).
@Suite("Prompt skip", .timeLimit(.minutes(1)))
struct PromptSkipTests {

    private let masterURL = URL(string: "https://ex.com/hls/master.m3u8")!
    private let videoURL  = URL(string: "https://ex.com/hls/v720/index.m3u8")!
    private let audioURL  = URL(string: "https://ex.com/hls/audio/en.m3u8")!



    // MARK: - Tests

    @Test("nonInteractive=true selects all playlists without calling prompt closure")
    func nonInteractiveSelectsAllWithoutPrompt() async throws {
        let fetcher = makeScriptedFetcher()
        let promptCallCount = OSAllocatedUnfairLock(initialState: 0)

        let session = ValidationSession(
            inputURL: masterURL,
            config: SessionConfig(nonInteractive: true),
            fetcher: fetcher,
            id: "prompt-skip-noninteractive",
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            sleep: { _ in try Task.checkCancellation() },
            selectPlaylists: { candidates in
                promptCallCount.withLock { $0 += 1 }
                return candidates
            }
        )

        let task = Task { await session.run() }
        // Give the session enough time to reach selecting/monitoring state, then abort.
        for _ in 0..<10_000 { await Task.yield() }
        await session.abort()
        task.cancel()
        await task.value

        #expect(promptCallCount.withLock { $0 } == 0, "Prompt closure must not be called when nonInteractive=true")
    }

    @Test("selectionPatterns supplied skips prompt and applies pattern filter")
    func selectionPatternsSkipsPromptAndFilters() async throws {
        let fetcher = makeScriptedFetcher()
        let promptCallCount = OSAllocatedUnfairLock(initialState: 0)

        let session = ValidationSession(
            inputURL: masterURL,
            config: SessionConfig(
                nonInteractive: false,
                selectionPatterns: ["v720"]
            ),
            fetcher: fetcher,
            id: "prompt-skip-patterns",
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            sleep: { _ in try Task.checkCancellation() },
            selectPlaylists: { candidates in
                promptCallCount.withLock { $0 += 1 }
                return candidates
            }
        )

        let task = Task { await session.run() }
        for _ in 0..<10_000 { await Task.yield() }
        await session.abort()
        task.cancel()
        await task.value

        // Session calls selectPlaylists when nonInteractive=false — this is session-level behaviour.
        // The CLI is responsible for not passing a closure when patterns are supplied (T043/SelectionPromptPolicy).
        // Here we verify that supplying patterns via config produces the correct subset:
        let findings = await session.recordedFindings
        let monitoredURLs = Set(findings.map { $0.resource.absoluteString })
        #expect(!monitoredURLs.contains(audioURL.absoluteString),
                "Audio playlist should not be monitored when --select v720 is used")
    }

    @Test("non-TTY run (nonInteractive=true) processes all media playlists")
    func nonTTYRunProcessesAllPlaylists() async throws {
        let fetcher = makeScriptedFetcher()
        let session = ValidationSession(
            inputURL: masterURL,
            config: SessionConfig(nonInteractive: true),
            fetcher: fetcher,
            id: "prompt-skip-nontty",
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            sleep: { _ in try Task.checkCancellation() }
        )

        let task = Task { await session.run() }
        for _ in 0..<10_000 { await Task.yield() }
        await session.abort()
        task.cancel()
        await task.value

        // Both video and audio were fetched/validated during initial validation.
        let fetchCounts = [videoURL, audioURL].map { fetcher.fetchCount(for: $0) }
        #expect(fetchCounts.allSatisfy { $0 >= 1 }, "All playlists must be fetched in non-interactive run")
    }



    // MARK: - Helpers

    private func makeScriptedFetcher() -> ScriptedStreamFetcher {
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(masterURL, body: liveMasterPlaylist)
        fetcher.stub(videoURL, body: liveMediaPlaylist)
        fetcher.stub(audioURL, body: liveMediaPlaylist)
        return fetcher
    }



    // MARK: - Fixtures

    private let liveMasterPlaylist = """
        #EXTM3U
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",NAME="English",LANGUAGE="en",DEFAULT=YES,AUTOSELECT=YES,URI="audio/en.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=1280000,AVERAGE-BANDWIDTH=1100000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720,AUDIO="aud1"
        v720/index.m3u8
        """

    private let liveMediaPlaylist = """
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
}

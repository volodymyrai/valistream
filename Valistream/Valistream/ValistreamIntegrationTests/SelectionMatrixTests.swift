//
//  SelectionMatrixTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

@testable import ValistreamCore
import Foundation
import os
import Testing

/// Verifies the US4 selection matrix end-to-end via the `SelectionPromptPolicy` seam and
/// scripted in-process `ValidationSession` runs (SC-010, FR-021–025).
///
/// Exit-code assertions for unknown-option cases (`--all`) cannot be driven in-process because
/// ArgumentParser rejects them before `run()` is ever called. Those are verified manually /
/// via subprocess in a separate smoke-test step. All other matrix cells are covered here.
@Suite("Selection matrix", .timeLimit(.minutes(1)))
struct SelectionMatrixTests {

    private let masterURL = URL(string: "https://ex.com/hls/master.m3u8")!
    private let videoURL  = URL(string: "https://ex.com/hls/v720/index.m3u8")!
    private let audioURL  = URL(string: "https://ex.com/hls/audio/en.m3u8")!



    // MARK: - Policy-level matrix (unit seam, no subprocess needed)

    @Test("default (no flags, TTY) → policy returns .skip, no prompt (FR-021)")
    func defaultNoFlagsSkipsPrompt() {
        let policy = SelectionPromptPolicy.from(isTTY: true, selectFlag: false, preselectPatterns: nil)
        #expect(policy == .skip)
    }

    @Test("--preselect only → policy returns .skip, no prompt (FR-023)")
    func preselectOnlySkipsPrompt() {
        let policy = SelectionPromptPolicy.from(isTTY: true, selectFlag: false, preselectPatterns: ["video"])
        #expect(policy == .skip)
    }

    @Test("--select + --preselect → policy returns .usageError (FR-025)")
    func selectAndPreselectIsUsageError() {
        let policy = SelectionPromptPolicy.from(isTTY: true, selectFlag: true, preselectPatterns: ["video"])
        #expect(policy == .usageError)
    }

    @Test("--select non-TTY → policy returns .skip (fallback to all, FR-025)")
    func selectNonTTYSkips() {
        let policy = SelectionPromptPolicy.from(isTTY: false, selectFlag: true, preselectPatterns: nil)
        #expect(policy == .skip)
    }

    @Test("--select + TTY → policy returns .prompt (FR-024)")
    func selectOnTTYShowsPrompt() {
        let policy = SelectionPromptPolicy.from(isTTY: true, selectFlag: true, preselectPatterns: nil)
        #expect(policy == .prompt)
    }



    // MARK: - Session-level: prompt closure not called for default (FR-021)

    @Test("default run (nonInteractive=true) does not call the prompt closure")
    func defaultRunDoesNotCallPromptClosure() async throws {
        let fetcher = makeScriptedFetcher()
        let promptCallCount = OSAllocatedUnfairLock(initialState: 0)

        let session = ValidationSession(
            inputURL: masterURL,
            config: SessionConfig(nonInteractive: true),
            fetcher: fetcher,
            id: "sel-matrix-default",
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

        #expect(promptCallCount.withLock { $0 } == 0, "Prompt closure must not be called for default run")
    }



    // MARK: - Session-level: --preselect pattern filter applied (FR-023)

    @Test("--preselect pattern filters to matching renditions only")
    func preselectPatternFiltersSubset() async throws {
        let fetcher = makeScriptedFetcher()

        // --preselect: policy = .skip → no selectPlaylists closure; selectionPatterns applied.
        // Only v720 matches; audio should be excluded from monitoring.
        let session = ValidationSession(
            inputURL: masterURL,
            config: SessionConfig(
                nonInteractive: true,       // policy=.skip means CLI passes nonInteractive or no closure
                selectionPatterns: ["v720"]
            ),
            fetcher: fetcher,
            id: "sel-matrix-preselect",
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            sleep: { _ in try Task.checkCancellation() }
            // No selectPlaylists closure — mirrors CLI behaviour when --preselect is used.
        )

        let task = Task { await session.run() }
        for _ in 0..<10_000 { await Task.yield() }
        await session.abort()
        task.cancel()
        await task.value

        // Audio playlist is fetched once during initial validation (master references it), but
        // must NOT be fetched again during monitoring (pattern excludes it from the monitor loop).
        let audioFetches = fetcher.fetchCount(for: audioURL)
        #expect(audioFetches <= 1, "Audio playlist must not be monitored when --preselect v720 is used (≤1 = initial only)")
    }



    // MARK: - Session-level: --select non-TTY processes all playlists (FR-025)

    @Test("--select non-TTY (policy=.skip, no selectPlaylists closure) fetches all renditions")
    func selectNonTTYFetchesAll() async throws {
        let fetcher = makeScriptedFetcher()

        // Policy .skip → no prompt closure passed; all playlists processed.
        let session = ValidationSession(
            inputURL: masterURL,
            config: SessionConfig(nonInteractive: true),
            fetcher: fetcher,
            id: "sel-matrix-nontty",
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            sleep: { _ in try Task.checkCancellation() }
        )

        let task = Task { await session.run() }
        for _ in 0..<10_000 { await Task.yield() }
        await session.abort()
        task.cancel()
        await task.value

        let videoFetches = fetcher.fetchCount(for: videoURL)
        let audioFetches = fetcher.fetchCount(for: audioURL)
        #expect(videoFetches >= 1, "Video playlist must be fetched in non-TTY --select fallback")
        #expect(audioFetches >= 1, "Audio playlist must be fetched in non-TTY --select fallback")
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

//
//  ProgressEventsTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

import Testing
@testable import ValistreamCore
import Foundation

@Suite(.tags(.session), .timeLimit(.minutes(1)))
struct ProgressEventsTests {

    private let base = "https://test.example/"

    // MARK: - Helpers

    private struct StubFetcher: StreamFetching {
        let responses: [URL: String]

        func fetch(_ url: URL) async -> FetchResult {
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            let body = responses[url] ?? ""
            let outcome: FetchOutcome = responses[url] != nil ? .success : .transportError(description: "no stub")
            return FetchResult(
                url: url,
                body: Data(body.utf8),
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

    private func makeSession() -> ValidationSession {
        let masterURL = URL(string: base + "master.m3u8")!
        let fetcher = StubFetcher(responses: [
            masterURL:                                masterPlaylist,
            URL(string: base + "v720/index.m3u8")!:  vodMedia,
            URL(string: base + "audio/en.m3u8")!:    vodMedia,
            URL(string: base + "iframe/720.m3u8")!:  vodMedia,
        ])
        return ValidationSession(
            inputURL: masterURL,
            config: SessionConfig(nonInteractive: true),
            fetcher: fetcher,
            id: "progress-test",
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private func collectActivityEvents(from session: ValidationSession) async -> [ActivityProgress] {
        await withTaskGroup(of: [ActivityProgress].self) { group in
            group.addTask { await session.run(); return [] }
            group.addTask {
                var events: [ActivityProgress] = []
                for await event in session.events {
                    if case .activity(let p) = event { events.append(p) }
                }
                return events
            }
            var all: [ActivityProgress] = []
            for await result in group { all += result }
            return all
        }
    }



    // MARK: - Tests

    @Test("one-shot VOD session emits at least one activity event")
    func sessionEmitsActivityEvents() async {
        let events = await collectActivityEvents(from: makeSession())
        #expect(!events.isEmpty)
    }

    @Test("activity event completed counts are non-negative")
    func completedCountsNonNegative() async {
        let events = await collectActivityEvents(from: makeSession())
        #expect(events.allSatisfy { $0.completed >= 0 })
    }

    @Test("activity events with known total have completed count advancing to total")
    func completedAdvancesToTotal() async {
        let events = await collectActivityEvents(from: makeSession())
        let withTotal = events.filter { $0.total != nil }
        guard let last = withTotal.last else {
            Issue.record("Expected at least one activity event with known total")
            return
        }
        #expect(last.completed == last.total)
    }



    // MARK: - Fixtures

    private let masterPlaylist = """
        #EXTM3U
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",NAME="English",LANGUAGE="en",DEFAULT=YES,AUTOSELECT=YES,URI="audio/en.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=1280000,AVERAGE-BANDWIDTH=1100000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720,AUDIO="aud1"
        v720/index.m3u8
        #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=120000,RESOLUTION=1280x720,CODECS="avc1.4d401f",URI="iframe/720.m3u8"
        """

    private let vodMedia = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:6.0,
        seg0.ts
        #EXTINF:6.0,
        seg1.ts
        #EXT-X-ENDLIST
        """
}

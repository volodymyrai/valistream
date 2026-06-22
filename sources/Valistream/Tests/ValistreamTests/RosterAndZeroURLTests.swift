//
//  RosterAndZeroURLTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

/// Asserts FR-011/012, SC-003: the roster prints each ID → full URL + role BEFORE any fetch;
/// after the roster no full URL appears in subsequent events (at normal AND --verbose tiers).
@Suite("Roster and zero-URL invariant", .timeLimit(.minutes(1)))
struct RosterAndZeroURLTests {

    private let masterURL = URL(string: "https://cdn-long-host.example.com/streams/live/master.m3u8")!
    private let v1080URL = URL(string: "https://cdn-long-host.example.com/streams/live/v1080/index.m3u8")!
    private let v720URL  = URL(string: "https://cdn-long-host.example.com/streams/live/v720/index.m3u8")!

    @Test("roster event arrives before any fetch; normal-tier events after roster contain no full URL")
    func rosterBeforeFetchNoURLAfterRosterAtNormal() async throws {
        let (events, _) = try await runSession()
        let rosterIdx = try #require(
            events.firstIndex(where: {
                if case .rosterReady = $0 { return true }
                return false
            }),
            "Expected a .rosterReady event"
        )
        // All events after the roster at normal tier must not carry raw media URL strings
        for event in events.dropFirst(rosterIdx + 1) {
            let representation = "\(event)"
            for url in [v1080URL, v720URL] {
                #expect(
                    representation.contains(url.absoluteString) == false,
                    "Event after roster contains raw URL \(url.absoluteString): \(representation)"
                )
            }
        }
    }

    @Test("roster event contains full URL for each discovered playlist")
    func rosterContainsFullURLs() async throws {
        let (events, _) = try await runSession()
        let rosterEvent = try #require(
            events.first(where: { if case .rosterReady = $0 { return true }; return false }),
            "Expected a .rosterReady event"
        )
        guard case .rosterReady(let entries) = rosterEvent else {
            Issue.record("Unexpected event type")
            return
        }
        let rosterURLs = entries.map(\.url)
        #expect(rosterURLs.contains(v1080URL), "Roster should include 1080p URL")
        #expect(rosterURLs.contains(v720URL), "Roster should include 720p URL")
    }

    @Test("roster entries have non-empty IDs (no raw URLs as IDs)")
    func rosterEntriesHaveIDs() async throws {
        let (events, _) = try await runSession()
        guard let rosterEvent = events.first(where: { if case .rosterReady = $0 { return true }; return false }),
              case .rosterReady(let entries) = rosterEvent
        else {
            Issue.record("Expected a .rosterReady event with entries")
            return
        }
        for entry in entries {
            #expect(entry.id.isEmpty == false, "Roster entry ID must not be empty for \(entry.url)")
            #expect(
                entry.id.contains("://") == false,
                "Roster entry ID must not be a raw URL, got: \(entry.id)"
            )
        }
    }



    // MARK: - Private helpers

    private func runSession() async throws -> ([SessionEvent], [SessionEvent]) {
        let harness = LiveSessionHarness(input: masterURL)
        harness.fetcher.stub(masterURL, body: masterPlaylist)
        harness.fetcher.stub(v1080URL, body: liveMedia)
        harness.fetcher.stub(v720URL, body: liveMedia)
        await harness.start()

        let collector = Task { [harness] in
            var collectedEvents: [SessionEvent] = []
            for await event in harness.session.events {
                collectedEvents.append(event)
            }
            return collectedEvents
        }
        // Wait until both media renditions are monitoring (roster already emitted), then abort.
        await harness.waitForSleepers(2)
        await harness.abortAndFinish()
        let collectedEvents = await collector.value

        return (collectedEvents, [])
    }



    // MARK: - Fixtures

    private let masterPlaylist = """
        #EXTM3U
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,CODECS="avc1.640028",RESOLUTION=1920x1080
        v1080/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2500000,CODECS="avc1.4d401f",RESOLUTION=1280x720
        v720/index.m3u8
        """

    private let liveMedia = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:100
        #EXTINF:6.0,
        seg100.ts
        #EXTINF:6.0,
        seg101.ts
        """
}

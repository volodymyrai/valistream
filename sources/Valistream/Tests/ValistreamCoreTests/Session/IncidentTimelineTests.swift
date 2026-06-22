//
//  IncidentTimelineTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite(.tags(.session))
struct IncidentTimelineTests {
    @Test("events order by occurrence and sequence while routine events are excluded")
    func orderingAndEligibility() throws {
        let first = Date(timeIntervalSince1970: 1_750_000_000)
        let second = first.addingTimeInterval(1)
        let warning = makeFinding(
            id: "f-warning",
            severity: .warning,
            at: first,
            message: "Do not repeat this message."
        )
        let info = makeFinding(
            id: "f-info",
            severity: .info,
            at: first,
            message: "Routine diagnostic."
        )
        let lifecycle = PlaylistLifecycleEvent(playlistID: "video", at: first, kind: .removed)
        let timeline = IncidentTimeline(events: [
            (sequence: 5, event: TimestampedEvent(at: second, event: .stateChanged(.failed))),
            (
                sequence: 4,
                event: TimestampedEvent(
                    at: first,
                    event: .finding(
                        warning,
                        evidence: .single(path: "playlists/video/video_1.m3u8")
                    )
                )
            ),
            (
                sequence: 1,
                event: TimestampedEvent(
                    at: first,
                    event: .refreshCompleted(
                        playlistID: "video",
                        index: 1,
                        errors: 0,
                        warnings: 0,
                        hold: nil
                    )
                )
            ),
            (
                sequence: 3,
                event: TimestampedEvent(at: first, event: .finding(info, evidence: nil))
            ),
            (
                sequence: 2,
                event: TimestampedEvent(at: first, event: .playlistLifecycle(lifecycle))
            ),
        ])

        #expect(timeline.entries.map(\.sequence) == [2, 4, 5])
        #expect(timeline.entries.map(\.kind) == [
            .lifecycle(.removed),
            .finding(.warning),
            .operationalFailure,
        ])
        let findingEntry = try #require(timeline.entries.first { $0.findingAnchor != nil })
        #expect(findingEntry.findingAnchor == "finding-f-warning")
        #expect(findingEntry.summary.contains(warning.message) == false)
        #expect(findingEntry.summary.contains("video_1.m3u8") == false)
    }

    @Test("equal timestamp ordering is deterministic across repeated assembly")
    func deterministicRegeneration() {
        let at = Date(timeIntervalSince1970: 1_750_000_000)
        let events = [
            (
                sequence: 2,
                event: TimestampedEvent(
                    at: at,
                    event: .playlistLifecycle(
                        PlaylistLifecycleEvent(
                            playlistID: "audio",
                            at: at,
                            kind: .recovered
                        )
                    )
                )
            ),
            (
                sequence: 1,
                event: TimestampedEvent(
                    at: at,
                    event: .playlistLifecycle(
                        PlaylistLifecycleEvent(
                            playlistID: "video",
                            at: at,
                            kind: .unavailable
                        )
                    )
                )
            ),
        ]

        #expect(IncidentTimeline(events: events) == IncidentTimeline(events: events.reversed()))
        #expect(IncidentTimeline(events: events).entries.map(\.sequence) == [1, 2])
    }

    private func makeFinding(
        id: String,
        severity: Finding.Severity,
        at: Date,
        message: String
    ) -> Finding {
        Finding(
            id: id,
            ruleId: "TOOL.timeline",
            source: .tool,
            severity: severity,
            category: .delivery,
            resource: URL(filePath: "/video.m3u8"),
            location: nil,
            refreshIndex: 1,
            observedAt: at,
            message: message,
            context: [:]
        )
    }
}

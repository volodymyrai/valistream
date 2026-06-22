//
//  TraceFormatterTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

/// Tests phrase-only formatting for terminal trace events.
@Suite(.tags(.output))
struct TraceFormatterTests {

    @Test(
        "trace events render phrase-only text",
        arguments: [
            (TraceEvent.fetchStarted(url: URL(filePath: "/tmp/video.m3u8"), playlistID: "video", refreshIndex: 1),
             "started (file:///tmp/video.m3u8)"),
            (.fetchIntent(snapshotID: "video_1"), "requesting"),
            (.fetchResult(snapshotID: "video_1", httpStatus: 200, durationMs: 42, bytes: 1_320),
             "fetched HTTP 200; 42ms; 1.3 kB"),
            (.validationPlaylistOK(snapshotID: "video_1"), "validated OK"),
            (.validationPlaylistFail(snapshotID: "video_1", errorCount: 2, warnCount: 1),
             "validated 2 ERROR, 1 WARN"),
            (.validationRuleOK(snapshotID: "video_1", ruleID: "RFC8216.4.3.3.1"),
             "rule [RFC8216.4.3.3.1] OK"),
            (.validationRuleFail(snapshotID: "video_1", ruleID: "RFC8216.4.3.3.1"),
             "rule [RFC8216.4.3.3.1] finding"),
            (.stored(snapshotID: "video_1", archivePath: "playlists/video/video_1.m3u8"),
             "stored playlists/video/video_1.m3u8"),
            (.refreshScheduled(playlistID: "video", delaySeconds: 6), "next refresh in 6s"),
            (.refreshRetry(playlistID: "video", delaySeconds: 2), "re-try scheduled in 2s"),
            (.refreshDrift(playlistID: "video", driftSeconds: 1.5), "cadence drift 1.5s"),
            (.continuityCompare(olderSnapshotID: "video_0", newerSnapshotID: "video_1"),
             "compared ↔ video_0"),
            (.renditionAdded(playlistID: "video"), "added"),
            (.renditionDropped(playlistID: "video"), "dropped"),
        ]
    )
    func phrase(event: TraceEvent, expected: String) {
        #expect(TraceFormatter.format(event) == expected)
    }

    @Test(
        "validation finding summary omits zero counts",
        arguments: [
            (0, 0, "validated findings"),
            (1, 0, "validated 1 ERROR"),
            (0, 1, "validated 1 WARN"),
        ]
    )
    func validationFindingSummary(errorCount: Int, warnCount: Int, expected: String) {
        let event = TraceEvent.validationPlaylistFail(
            snapshotID: "video_1",
            errorCount: errorCount,
            warnCount: warnCount
        )

        #expect(TraceFormatter.format(event) == expected)
    }
}

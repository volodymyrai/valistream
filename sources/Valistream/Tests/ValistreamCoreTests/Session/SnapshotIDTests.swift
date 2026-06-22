//
//  SnapshotIDTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite(.tags(.session))
struct SnapshotIDTests {
    @Test("label appends the zero-based refresh index")
    func labelAppendsIndex() {
        #expect(SnapshotID.label(id: "1080p_avc1", index: 7) == "1080p_avc1_7")
    }

    @Test("first fetch uses index zero")
    func firstFetchUsesZero() {
        #expect(SnapshotID.label(id: "master", index: 0) == "master_0")
    }

    @Test("VOD single fetch uses only index zero")
    func VODSingleFetchUsesZero() {
        let labels = [SnapshotID.label(id: "1080p_avc1", index: 0)]

        #expect(labels == ["1080p_avc1_0"])
    }

    @Test("parse round-trips IDs containing underscores")
    func parseRoundTripsLabel() throws {
        let label = SnapshotID.label(id: "1080p_avc1", index: 12)
        let parsed = try #require(SnapshotID.parse(label))

        #expect(parsed.id == "1080p_avc1")
        #expect(parsed.index == 12)
        #expect(SnapshotID.label(id: parsed.id, index: parsed.index) == label)
    }

    @Test(
        "parse rejects malformed labels",
        arguments: ["master", "master_", "_0", "master_-1", "master_one"]
    )
    func parseRejectsMalformedLabels(label: String) {
        #expect(SnapshotID.parse(label) == nil)
    }
}

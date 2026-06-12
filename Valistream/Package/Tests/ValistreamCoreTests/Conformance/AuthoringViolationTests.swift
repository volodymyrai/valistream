//
//  AuthoringViolationTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite("Apple authoring violations", .tags(.validation))
struct AuthoringViolationTests {
    private let rules: [any ValidationRule] = [AppleAuthoringRules()]

    @Test("flags a bare variant missing CODECS, AVERAGE-BANDWIDTH, RESOLUTION, and trick-play assets")
    func sparseVariant() {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1000000
        v720.m3u8
        """
        let ids = Set(violations(in: text, rules: rules, kind: .vod).map(\.ruleId))

        #expect(ids.isSuperset(of: [
            "APPLE.codecs", "APPLE.average-bandwidth", "APPLE.resolution",
            "APPLE.independent-segments", "APPLE.iframe-playlists",
        ]))
    }

    @Test("flags duplicate BANDWIDTH values in the variant ladder")
    func duplicateBandwidth() {
        let text = """
        #EXTM3U
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=1000000,CODECS="avc1.4d401f",RESOLUTION=1280x720,AVERAGE-BANDWIDTH=900000
        a.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=1000000,CODECS="avc1.4d401f",RESOLUTION=1280x720,AVERAGE-BANDWIDTH=900000
        b.m3u8
        #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=120000,URI="i.m3u8"
        """
        let found = violations(in: text, rules: rules, kind: .vod)

        #expect(found.contains { $0.ruleId == "APPLE.variant-ladder" && $0.severity == .warning })
    }

    @Test("emits an info finding when target duration exceeds the recommended 6 seconds")
    func longTargetDuration() {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:10
        #EXTINF:9.0,
        s0.ts
        """
        let found = violations(in: text, rules: rules)

        #expect(found.contains { $0.ruleId == "APPLE.target-duration" && $0.severity == .info })
    }
}

//
//  MasterViolationTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite("RFC 8216 master violations", .tags(.validation))
struct MasterViolationTests {
    private let rules: [any ValidationRule] = [RFC8216MasterRules()]

    @Test("flags a playlist that does not begin with #EXTM3U")
    func missingExtM3U() {
        let text = """
        #EXT-X-STREAM-INF:BANDWIDTH=1280000
        v720.m3u8
        """
        let found = violations(in: text, rules: rules)

        let violation = found.first { $0.ruleId == "RFC8216.4.3.1.1" }
        #expect(violation?.severity == .error)
        #expect(violation?.location?.line == 1)
    }

    @Test("flags EXT-X-STREAM-INF without BANDWIDTH")
    func missingBandwidth() {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:CODECS="avc1.4d401f"
        v720.m3u8
        """
        let found = violations(in: text, rules: rules)

        let violation = found.first { $0.ruleId == "RFC8216.4.3.4.2-BANDWIDTH" }
        #expect(violation?.severity == .error)
        #expect(violation?.location?.line == 2)
    }

    @Test("flags an unresolvable audio group reference")
    func unresolvableGroup() {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1280000,AUDIO="missing"
        v720.m3u8
        """
        let found = violations(in: text, rules: rules)

        #expect(found.contains { $0.ruleId == "RFC8216.4.3.4.2.1" && $0.severity == .error })
    }

    @Test("flags EXT-X-MEDIA missing a required attribute")
    func renditionMissingAttribute() {
        let text = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",URI="a.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=1280000,AUDIO="aud1"
        v720.m3u8
        """
        let found = violations(in: text, rules: rules)

        let violation = found.first { $0.ruleId == "RFC8216.4.3.4.1" }
        #expect(violation?.severity == .error)
        #expect(violation?.message.contains("NAME") == true)
    }
}

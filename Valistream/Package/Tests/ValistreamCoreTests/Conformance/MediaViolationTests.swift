//
//  MediaViolationTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite("RFC 8216 media violations", .tags(.validation))
struct MediaViolationTests {
    private let rules: [any ValidationRule] = [RFC8216MediaRules()]

    @Test("flags a media playlist missing EXT-X-TARGETDURATION")
    func missingTargetDuration() {
        let text = """
        #EXTM3U
        #EXTINF:6.0,
        s0.ts
        """
        let found = violations(in: text, rules: rules)

        #expect(found.contains { $0.ruleId == "RFC8216.4.3.3.1" && $0.severity == .error })
    }

    @Test("flags a segment whose duration exceeds the target duration")
    func segmentExceedsTarget() {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXTINF:10.0,
        s0.ts
        """
        let found = violations(in: text, rules: rules)

        let violation = found.first { $0.ruleId == "RFC8216.4.3.3.1-DURATION" }
        #expect(violation?.severity == .error)
        #expect(violation?.location?.line == 4)
    }

    @Test("flags a segment URI not preceded by EXTINF")
    func missingExtInf() {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        s0.ts
        """
        let found = violations(in: text, rules: rules)

        let violation = found.first { $0.ruleId == "RFC8216.4.3.2.1" }
        #expect(violation?.severity == .error)
        #expect(violation?.location?.line == 3)
    }

    @Test("flags a duplicated EXT-X-MEDIA-SEQUENCE tag")
    func duplicateMediaSequence() {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-MEDIA-SEQUENCE:1
        #EXTINF:6.0,
        s0.ts
        """
        let found = violations(in: text, rules: rules)

        #expect(found.contains { $0.ruleId == "RFC8216.4.3.3-DUPLICATE" && $0.severity == .error })
    }
}

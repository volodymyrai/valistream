//
//  SpecCatalogTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 17/06/2026.
//

@testable import ValistreamCore
import Testing

@Suite("SpecCatalog", .tags(.validation))
struct SpecCatalogTests {
    @Test(
        "derives RFC 8216 references from rule IDs",
        arguments: [
            ("RFC8216.4.3.3.1", "RFC 8216 §4.3.3.1"),
            ("RFC8216.4.3.3.1-DURATION", "RFC 8216 §4.3.3.1"),
            ("RFC8216.4.3.3-DUPLICATE", "RFC 8216 §4.3.3"),
            ("RFC8216.4.3.4.2-BANDWIDTH", "RFC 8216 §4.3.4.2"),
        ]
    )
    func derivesRFC8216References(ruleId: String, expected: String) {
        #expect(SpecCatalog.reference(forRuleId: ruleId) == expected)
    }

    @Test(
        "maps explicit authoring and tool references",
        arguments: [
            ("APPLE.codecs", "HLS Authoring §9.1"),
            ("APPLE.resolution", "HLS Authoring §9.2"),
            ("APPLE.independent-segments", "HLS Authoring §9.11"),
            ("APPLE.average-bandwidth", "HLS Authoring §9.14"),
            ("APPLE.iframe-playlists", "HLS Authoring §6.1"),
            ("TOOL.continuity.media-sequence", "RFC 8216 §6.2.2"),
            ("TOOL.continuity.head-removal", "RFC 8216 §6.2.2"),
            ("TOOL.continuity.segment-stability", "RFC 8216 §6.2.2"),
            ("TOOL.continuity.discontinuity-inserted", "RFC 8216 §4.3.2.3"),
            ("TOOL.continuity.discontinuity-sequence", "RFC 8216 §4.3.3.3"),
            ("TOOL.staleness", "RFC 8216 §6.2.1"),
        ]
    )
    func mapsExplicitReferences(ruleId: String, expected: String) {
        #expect(SpecCatalog.reference(forRuleId: ruleId) == expected)
    }

    @Test(
        "leaves operational and classification rules bare",
        arguments: [
            "APPLE.variant-ladder",
            "APPLE.target-duration",
            "TOOL.low-latency",
            "TOOL.encryption",
            "TOOL.delivery",
            "TOOL.selection-empty",
            "TOOL.future-rule",
        ]
    )
    func leavesBareRulesUnreferenced(ruleId: String) {
        #expect(SpecCatalog.reference(forRuleId: ruleId) == nil)
    }
}

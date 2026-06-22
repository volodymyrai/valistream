//
//  SpecCatalog.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 17/06/2026.
//

/// Rule-to-spec citation catalog for findings grounded in an external specification.
enum SpecCatalog {
    // MARK: - Internal

    static func reference(forRuleId id: String) -> String? {
        if id.hasPrefix("RFC8216.") {
            let remainder = id.dropFirst("RFC8216.".count)
            let section = remainder.prefix { $0 != "-" }
            guard section.isEmpty == false else { return nil }

            return "RFC 8216 §\(section)"
        }

        return explicitReferences[id]
    }



    // MARK: - Private

    private static let explicitReferences = [
        "APPLE.codecs": "HLS Authoring §9.1",
        "APPLE.resolution": "HLS Authoring §9.2",
        "APPLE.independent-segments": "HLS Authoring §9.11",
        "APPLE.average-bandwidth": "HLS Authoring §9.14",
        "APPLE.iframe-playlists": "HLS Authoring §6.1",
        "TOOL.continuity.media-sequence": "RFC 8216 §6.2.2",
        "TOOL.continuity.head-removal": "RFC 8216 §6.2.2",
        "TOOL.continuity.segment-stability": "RFC 8216 §6.2.2",
        "TOOL.continuity.discontinuity-inserted": "RFC 8216 §4.3.2.3",
        "TOOL.continuity.discontinuity-sequence": "RFC 8216 §4.3.3.3",
        "TOOL.staleness": "RFC 8216 §6.2.1"
    ]
}

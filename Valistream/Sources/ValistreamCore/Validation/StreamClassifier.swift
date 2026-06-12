//
//  StreamClassifier.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Classifies a stream as VOD, event, or live (FR-005) and surfaces info findings for low-latency
/// HLS tags (FR-017) and encryption (FR-013), neither of which the tool acts on beyond reporting.
public struct StreamClassifier: Sendable {
    // MARK: - Lets & Vars

    private static let lowLatencyTags: Set<String> = [
        "#EXT-X-PART", "#EXT-X-PART-INF", "#EXT-X-SERVER-CONTROL",
        "#EXT-X-PRELOAD-HINT", "#EXT-X-RENDITION-REPORT", "#EXT-X-SKIP",
    ]



    // MARK: - Lifecycle

    public init() {}



    // MARK: - Public

    /// Classifies a representative media playlist (FR-005).
    public func classify(_ media: MediaPlaylist) -> StreamKind {
        if media.playlistType == "EVENT", !media.hasEndList {
            return .event
        }
        if media.hasEndList || media.playlistType == "VOD" {
            return .vod
        }
        return .live
    }

    /// Whether the token stream carries low-latency HLS tags (FR-017).
    public func lowLatencyDetected(in tokens: [M3U8Token]) -> Bool {
        tokens.contains { token in
            if case .tag(let name, _) = token.kind { return Self.lowLatencyTags.contains(name) }
            return false
        }
    }

    /// Info-level findings for a media playlist: low-latency tags and encryption (FR-013/FR-017).
    public func infoViolations(for media: MediaPlaylist, tokens: [M3U8Token]) -> [RuleViolation] {
        var violations: [RuleViolation] = []
        if lowLatencyDetected(in: tokens) {
            violations.append(RuleViolation(
                ruleId: "TOOL.low-latency",
                source: .tool,
                severity: .info,
                category: .mediaPlaylist,
                message: "Low-latency HLS tags detected; LL-HLS-specific reload behavior is out of scope (FR-017)."
            ))
        }
        if media.hasEncryptionKeys {
            violations.append(RuleViolation(
                ruleId: "TOOL.encryption",
                source: .tool,
                severity: .info,
                category: .mediaPlaylist,
                message: "Stream is encrypted; the tool validates structure only and never decodes or decrypts media (FR-013)."
            ))
        }
        return violations
    }
}

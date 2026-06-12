//
//  RFC8216MediaRules.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// RFC 8216 conformance checks for media playlists (segment lists).
public struct RFC8216MediaRules: ValidationRule {
    // MARK: - Lets & Vars

    public let id = "RFC8216.media"
    public let source: Finding.Source = .rfc8216



    // MARK: - Lifecycle

    public init() {}



    // MARK: - Public

    public func evaluate(_ context: RuleContext) -> [RuleViolation] {
        guard let media = context.playlist.media else { return [] }
        var violations: [RuleViolation] = []
        violations.append(contentsOf: checkTargetDuration(media))
        violations.append(contentsOf: checkSegmentDurations(media))
        violations.append(contentsOf: checkMissingExtInf(context))
        violations.append(contentsOf: checkSingletonTags(context))
        return violations
    }



    // MARK: - Private

    private func checkTargetDuration(_ media: MediaPlaylist) -> [RuleViolation] {
        guard media.targetDuration == nil else { return [] }
        return [RuleViolation(
            ruleId: "RFC8216.4.3.3.1",
            source: source,
            severity: .error,
            category: .mediaPlaylist,
            message: "Media playlist is missing the required EXT-X-TARGETDURATION tag.",
            location: Finding.Location(line: nil, tag: "#EXT-X-TARGETDURATION")
        )]
    }

    private func checkSegmentDurations(_ media: MediaPlaylist) -> [RuleViolation] {
        guard let target = media.targetDuration else { return [] }
        return media.segments.compactMap { segment in
            guard segment.duration.rounded() > target else { return nil }
            return RuleViolation(
                ruleId: "RFC8216.4.3.3.1-DURATION",
                source: source,
                severity: .error,
                category: .mediaPlaylist,
                message: "Segment duration \(segment.duration)s exceeds EXT-X-TARGETDURATION of \(target)s.",
                location: Finding.Location(line: segment.lineNumber, tag: "#EXTINF"),
                context: ["duration": .double(segment.duration), "targetDuration": .double(target)]
            )
        }
    }

    private func checkMissingExtInf(_ context: RuleContext) -> [RuleViolation] {
        var violations: [RuleViolation] = []
        var pendingExtInf = false
        for token in context.tokens {
            switch token.kind {
            case .tag(let name, _) where name == "#EXTINF":
                pendingExtInf = true
            case .uri:
                if !pendingExtInf {
                    violations.append(RuleViolation(
                        ruleId: "RFC8216.4.3.2.1",
                        source: source,
                        severity: .error,
                        category: .mediaPlaylist,
                        message: "Segment URI is not preceded by an EXTINF tag.",
                        location: Finding.Location(line: token.lineNumber, tag: "#EXTINF")
                    ))
                }
                pendingExtInf = false
            default:
                break
            }
        }
        return violations
    }

    private func checkSingletonTags(_ context: RuleContext) -> [RuleViolation] {
        let singletons = ["#EXT-X-TARGETDURATION", "#EXT-X-MEDIA-SEQUENCE", "#EXT-X-DISCONTINUITY-SEQUENCE"]
        return singletons.compactMap { tag in
            let count = context.tokens.count { token in
                if case .tag(let name, _) = token.kind { return name == tag }
                return false
            }
            guard count > 1 else { return nil }
            return RuleViolation(
                ruleId: "RFC8216.4.3.3-DUPLICATE",
                source: source,
                severity: .error,
                category: .mediaPlaylist,
                message: "\(tag) appears \(count) times; it must appear at most once.",
                location: Finding.Location(line: nil, tag: tag),
                context: ["tag": .string(tag), "count": .int(count)]
            )
        }
    }
}

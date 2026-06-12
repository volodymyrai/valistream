//
//  AppleAuthoringRules.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// The playlist-observable subset of Apple's HLS Authoring Specification (research §5).
///
/// Only checks expressible from playlists and segment byte-sizes are implemented — decode-dependent
/// rules are excluded by FR-013. Each violation is tagged `apple-authoring` (FR-008).
public struct AppleAuthoringRules: ValidationRule {
    // MARK: - Lets & Vars

    public let id = "APPLE.authoring"
    public let source: Finding.Source = .appleAuthoring

    private static let videoCodecPrefixes = ["avc1", "avc3", "hvc1", "hev1", "dvh1", "dvhe", "av01", "vp09"]



    // MARK: - Lifecycle

    public init() {}



    // MARK: - Public

    public func evaluate(_ context: RuleContext) -> [RuleViolation] {
        switch context.playlist {
        case .master(let master):
            evaluateMaster(master, streamKind: context.streamKind)
        case .media(let media):
            evaluateMedia(media)
        }
    }



    // MARK: - Private

    private func evaluateMaster(_ master: MasterPlaylist, streamKind: StreamKind?) -> [RuleViolation] {
        var violations: [RuleViolation] = []
        violations.append(contentsOf: checkVariantAttributes(master))
        violations.append(contentsOf: checkDuplicateBandwidth(master))
        if !master.hasIndependentSegments {
            violations.append(RuleViolation(
                ruleId: "APPLE.independent-segments",
                source: source,
                severity: .warning,
                category: .masterPlaylist,
                message: "Master playlist should declare EXT-X-INDEPENDENT-SEGMENTS."
            ))
        }
        if streamKind == .vod, master.iFrameStreams.isEmpty, !master.variants.isEmpty {
            violations.append(RuleViolation(
                ruleId: "APPLE.iframe-playlists",
                source: source,
                severity: .warning,
                category: .masterPlaylist,
                message: "VOD master playlist should provide I-frame playlists (EXT-X-I-FRAME-STREAM-INF) for trick play."
            ))
        }
        return violations
    }

    private func checkVariantAttributes(_ master: MasterPlaylist) -> [RuleViolation] {
        master.variants.flatMap { variant -> [RuleViolation] in
            var violations: [RuleViolation] = []
            let location = Finding.Location(line: variant.lineNumber, tag: "#EXT-X-STREAM-INF")
            if variant.codecs.isEmpty {
                violations.append(RuleViolation(
                    ruleId: "APPLE.codecs",
                    source: source,
                    severity: .warning,
                    category: .masterPlaylist,
                    message: "EXT-X-STREAM-INF should declare a CODECS attribute.",
                    location: location
                ))
            }
            if variant.averageBandwidth == nil {
                violations.append(RuleViolation(
                    ruleId: "APPLE.average-bandwidth",
                    source: source,
                    severity: .warning,
                    category: .masterPlaylist,
                    message: "EXT-X-STREAM-INF should declare AVERAGE-BANDWIDTH.",
                    location: location
                ))
            }
            if expectsResolution(variant), variant.resolution == nil {
                violations.append(RuleViolation(
                    ruleId: "APPLE.resolution",
                    source: source,
                    severity: .warning,
                    category: .masterPlaylist,
                    message: "Video variant should declare a RESOLUTION attribute.",
                    location: location
                ))
            }
            return violations
        }
    }

    private func checkDuplicateBandwidth(_ master: MasterPlaylist) -> [RuleViolation] {
        var seen: Set<Int> = []
        return master.variants.compactMap { variant in
            guard let bandwidth = variant.bandwidth else { return nil }
            guard seen.insert(bandwidth).inserted == false else { return nil }
            return RuleViolation(
                ruleId: "APPLE.variant-ladder",
                source: source,
                severity: .warning,
                category: .masterPlaylist,
                message: "Multiple variants declare the same BANDWIDTH (\(bandwidth)); the ladder should use distinct bitrates.",
                location: Finding.Location(line: variant.lineNumber, tag: "#EXT-X-STREAM-INF"),
                context: ["bandwidth": .int(bandwidth)]
            )
        }
    }

    private func evaluateMedia(_ media: MediaPlaylist) -> [RuleViolation] {
        guard let target = media.targetDuration, target > 6 else { return [] }
        return [RuleViolation(
            ruleId: "APPLE.target-duration",
            source: source,
            severity: .info,
            category: .mediaPlaylist,
            message: "EXT-X-TARGETDURATION is \(target)s; Apple recommends a target duration of 6 seconds.",
            location: Finding.Location(line: nil, tag: "#EXT-X-TARGETDURATION"),
            context: ["targetDuration": .double(target)]
        )]
    }

    private func expectsResolution(_ variant: VariantStream) -> Bool {
        guard !variant.codecs.isEmpty else { return true }
        return variant.codecs.contains { codec in
            Self.videoCodecPrefixes.contains { codec.hasPrefix($0) }
        }
    }
}

//
//  RFC8216MasterRules.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// RFC 8216 conformance checks for master (multivariant) playlists.
///
/// Each violation carries the specific RFC section as its `ruleId` (FR-008). The rule reads the
/// structured ``MasterPlaylist`` for semantics and the token stream for exact line locations.
public struct RFC8216MasterRules: ValidationRule {
    // MARK: - Lets & Vars

    public let id = "RFC8216.master"
    public let source: Finding.Source = .rfc8216



    // MARK: - Lifecycle

    public init() {}



    // MARK: - Public

    public func evaluate(_ context: RuleContext) -> [RuleViolation] {
        guard let master = context.playlist.master else { return [] }
        var violations: [RuleViolation] = []
        violations.append(contentsOf: checkFirstLine(context))
        violations.append(contentsOf: checkStreamInfBandwidth(master))
        violations.append(contentsOf: checkDanglingStreamInf(master, context: context))
        violations.append(contentsOf: checkRenditionRequiredAttributes(master))
        violations.append(contentsOf: checkGroupReferences(master))
        return violations
    }



    // MARK: - Private

    private func checkFirstLine(_ context: RuleContext) -> [RuleViolation] {
        let firstMeaningful = context.tokens.first { $0.kind != .blank }
        guard case .tag(let name, _) = firstMeaningful?.kind, name == "#EXTM3U" else {
            return [RuleViolation(
                ruleId: "RFC8216.4.3.1.1",
                source: source,
                severity: .error,
                category: .masterPlaylist,
                message: "Playlist must begin with #EXTM3U.",
                location: Finding.Location(line: 1, tag: "#EXTM3U")
            )]
        }
        return []
    }

    private func checkStreamInfBandwidth(_ master: MasterPlaylist) -> [RuleViolation] {
        master.variants.compactMap { variant in
            guard variant.bandwidth == nil else { return nil }
            return RuleViolation(
                ruleId: "RFC8216.4.3.4.2-BANDWIDTH",
                source: source,
                severity: .error,
                category: .masterPlaylist,
                message: "EXT-X-STREAM-INF is missing the required BANDWIDTH attribute.",
                location: Finding.Location(line: variant.lineNumber, tag: "#EXT-X-STREAM-INF")
            )
        }
    }

    private func checkDanglingStreamInf(_ master: MasterPlaylist, context: RuleContext) -> [RuleViolation] {
        let streamInfCount = context.tokens.count { token in
            if case .tag(let name, _) = token.kind { return name == "#EXT-X-STREAM-INF" }
            return false
        }
        guard streamInfCount > master.variants.count else { return [] }
        return [RuleViolation(
            ruleId: "RFC8216.4.3.4.2-URI",
            source: source,
            severity: .error,
            category: .masterPlaylist,
            message: "An EXT-X-STREAM-INF tag is not followed by a variant URI line.",
            location: Finding.Location(line: nil, tag: "#EXT-X-STREAM-INF")
        )]
    }

    private func checkRenditionRequiredAttributes(_ master: MasterPlaylist) -> [RuleViolation] {
        master.renditions.flatMap { rendition -> [RuleViolation] in
            var missing: [String] = []
            if rendition.type == nil { missing.append("TYPE") }
            if rendition.groupID == nil { missing.append("GROUP-ID") }
            if rendition.name == nil { missing.append("NAME") }
            guard !missing.isEmpty else { return [] }
            return [RuleViolation(
                ruleId: "RFC8216.4.3.4.1",
                source: source,
                severity: .error,
                category: .masterPlaylist,
                message: "EXT-X-MEDIA is missing required attribute(s): \(missing.joined(separator: ", ")).",
                location: Finding.Location(line: rendition.lineNumber, tag: "#EXT-X-MEDIA"),
                context: ["missing": .string(missing.joined(separator: ","))]
            )]
        }
    }

    private func checkGroupReferences(_ master: MasterPlaylist) -> [RuleViolation] {
        let groups = Dictionary(grouping: master.renditions, by: { $0.type ?? "" })
            .mapValues { Set($0.compactMap(\.groupID)) }

        return master.variants.flatMap { variant -> [RuleViolation] in
            var violations: [RuleViolation] = []
            let references: [(attribute: String, type: String, value: String?)] = [
                ("AUDIO", "AUDIO", variant.audioGroupID),
                ("VIDEO", "VIDEO", variant.videoGroupID),
                ("SUBTITLES", "SUBTITLES", variant.subtitlesGroupID),
            ]
            for reference in references {
                guard let value = reference.value, value != "NONE" else { continue }
                if groups[reference.type]?.contains(value) != true {
                    violations.append(RuleViolation(
                        ruleId: "RFC8216.4.3.4.2.1",
                        source: source,
                        severity: .error,
                        category: .masterPlaylist,
                        message: "Variant references \(reference.attribute) group \"\(value)\" with no matching EXT-X-MEDIA rendition.",
                        location: Finding.Location(line: variant.lineNumber, tag: "#EXT-X-STREAM-INF"),
                        context: ["group": .string(value)]
                    ))
                }
            }
            return violations
        }
    }
}

//
//  ContinuityChecker.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Checks inter-refresh continuity of a live media playlist between observation `n-1` and `n`
/// (FR-007, data-model.md continuity rules).
///
/// The checks are pure functions of two consecutive parses: media sequence must not regress; the
/// window may only advance from the head; segments retained across a refresh must stay byte-stable
/// (same URI and duration); the discontinuity sequence must not regress. Violations are tool
/// findings in the `continuity` category.
public struct ContinuityChecker: Sendable {
    // MARK: - Lifecycle

    public init() {}



    // MARK: - Public

    /// Evaluates continuity between the previous and current refresh of the same media playlist.
    public func check(previous: MediaPlaylist, current: MediaPlaylist) -> [RuleViolation] {
        var violations: [RuleViolation] = []

        // Media sequence must be monotonic non-decreasing. Once it regresses, segment alignment by
        // sequence number is meaningless, so report and stop.
        if current.mediaSequence < previous.mediaSequence {
            violations.append(RuleViolation(
                ruleId: "TOOL.continuity.media-sequence",
                source: .tool,
                severity: .error,
                category: .continuity,
                message: "EXT-X-MEDIA-SEQUENCE regressed from \(previous.mediaSequence) to \(current.mediaSequence); a live media sequence must never decrease.",
                context: [
                    "previousMediaSequence": .int(previous.mediaSequence),
                    "currentMediaSequence": .int(current.mediaSequence),
                ]
            ))
            return violations
        }

        // The window may only advance from the head. Advancing past every previously published
        // segment means content was discarded faster than a player could consume it.
        let advanced = current.mediaSequence - previous.mediaSequence
        if advanced > previous.segments.count {
            violations.append(RuleViolation(
                ruleId: "TOOL.continuity.head-removal",
                source: .tool,
                severity: .error,
                category: .continuity,
                message: "The media window advanced by \(advanced) segments but the previous playlist held only \(previous.segments.count); segments were removed from the head before a player could consume them.",
                context: [
                    "advancedBy": .int(advanced),
                    "previousSegmentCount": .int(previous.segments.count),
                ]
            ))
        }

        // Segments retained across the refresh (overlapping sequence numbers) must be byte-stable.
        let overlapStart = current.mediaSequence
        let overlapEnd = min(
            previous.mediaSequence + previous.segments.count - 1,
            current.mediaSequence + current.segments.count - 1
        )
        if overlapStart <= overlapEnd {
            for sequence in overlapStart...overlapEnd {
                let previousIndex = sequence - previous.mediaSequence
                let currentIndex = sequence - current.mediaSequence
                guard previousIndex >= 0, previousIndex < previous.segments.count else { continue }
                let priorSegment = previous.segments[previousIndex]
                let currentSegment = current.segments[currentIndex]
                if priorSegment.uri != currentSegment.uri || priorSegment.duration != currentSegment.duration {
                    violations.append(RuleViolation(
                        ruleId: "TOOL.continuity.segment-stability",
                        source: .tool,
                        severity: .error,
                        category: .continuity,
                        message: "Segment at media sequence \(sequence) changed between refreshes; already-published segments must not be mutated retroactively.",
                        location: Finding.Location(line: currentSegment.lineNumber, tag: nil),
                        context: [
                            "mediaSequence": .int(sequence),
                            "previousURI": .string(priorSegment.uri.absoluteString),
                            "currentURI": .string(currentSegment.uri.absoluteString),
                        ]
                    ))
                }
            }
        }

        // A discontinuity newly introduced at the tail is legal — note it for the operator and keep
        // tracking (FR-007). Newly published segments are those past the previous window's end.
        let previousLastSequence = previous.mediaSequence + previous.segments.count - 1
        for (index, segment) in current.segments.enumerated() where segment.hasDiscontinuity {
            let sequence = current.mediaSequence + index
            guard sequence > previousLastSequence else { continue }
            violations.append(RuleViolation(
                ruleId: "TOOL.continuity.discontinuity-inserted",
                source: .tool,
                severity: .info,
                category: .continuity,
                message: "A discontinuity was inserted at media sequence \(sequence); continuity tracking continues across it.",
                location: Finding.Location(line: segment.lineNumber, tag: nil),
                context: ["mediaSequence": .int(sequence)]
            ))
        }

        // The discontinuity sequence must not regress.
        if current.discontinuitySequence < previous.discontinuitySequence {
            violations.append(RuleViolation(
                ruleId: "TOOL.continuity.discontinuity-sequence",
                source: .tool,
                severity: .error,
                category: .continuity,
                message: "EXT-X-DISCONTINUITY-SEQUENCE regressed from \(previous.discontinuitySequence) to \(current.discontinuitySequence).",
                context: [
                    "previousDiscontinuitySequence": .int(previous.discontinuitySequence),
                    "currentDiscontinuitySequence": .int(current.discontinuitySequence),
                ]
            ))
        }

        return violations
    }
}

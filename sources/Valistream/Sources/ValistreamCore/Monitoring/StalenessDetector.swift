//
//  StalenessDetector.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Detects a live playlist that has stopped refreshing on cadence (FR-007, research §4).
///
/// A playlist that has not changed for longer than 1.5× its target duration earns a warning;
/// past 3× the target duration the staleness escalates to an error (an effective outage). Both
/// findings carry the observed stale duration in their context. The detector is pure: the session
/// supplies the elapsed stale time from its clock.
public struct StalenessDetector: Sendable {
    // MARK: - Lets & Vars

    /// Stale beyond this multiple of the target duration → warning.
    public static let warningFactor = 1.5

    /// Stale beyond this multiple of the target duration → error.
    public static let errorFactor = 3.0



    // MARK: - Lifecycle

    public init() {}



    // MARK: - Public

    /// A staleness violation when the playlist has gone unrefreshed past the warning or error
    /// threshold, or `nil` while it is still within the liveness window.
    public func violation(staleFor staleDuration: Duration, targetDuration: Duration) -> RuleViolation? {
        let stale = staleDuration.seconds
        let target = targetDuration.seconds
        guard target > 0 else { return nil }

        let severity: Finding.Severity
        if stale > target * Self.errorFactor {
            severity = .error
        }
        else if stale > target * Self.warningFactor {
            severity = .warning
        }
        else {
            return nil
        }

        let staleText = stale.formatted(.number.precision(.fractionLength(1)))
        let targetText = target.formatted(.number.precision(.fractionLength(1)))
        return RuleViolation(
            ruleId: "TOOL.staleness",
            source: .tool,
            severity: severity,
            category: .continuity,
            message: "Playlist has not changed for \(staleText)s (target duration \(targetText)s); a live playlist should refresh at least every target duration.",
            context: [
                "staleSeconds": .double(stale),
                "targetDurationSeconds": .double(target),
            ]
        )
    }
}

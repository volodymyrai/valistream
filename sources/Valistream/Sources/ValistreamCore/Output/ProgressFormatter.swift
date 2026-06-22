//
//  ProgressFormatter.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

/// Converts an ``ActivityProgress`` value to a human-readable progress string.
///
/// Format rules (FR-006):
/// - Refreshes known → `"activity — N refresh(es) done"`
/// - Total known     → `"activity — N of M (xx%)"`
/// - Count only      → `"activity — N"` (N > 0) or just `"activity"` (N == 0)
///
/// Never emits ANSI codes — callers apply styling (FR-009, SC-004).
public enum ProgressFormatter {

    public static func format(_ progress: ActivityProgress) -> String {
        // US2 heartbeat: use session-wide monotonic total + current ID (FR-010/013, D7).
        if let sessionTotal = progress.sessionRefreshTotal, let alias = progress.aliasInScope {
            return "\(alias) · refresh \(sessionTotal) · ongoing"
        }
        if let sessionTotal = progress.sessionRefreshTotal {
            return "refresh \(sessionTotal)"
        }
        if let refreshes = progress.refreshes, let alias = progress.aliasInScope {
            return "\(alias) · \(refreshes == 1 ? "1 refresh" : "\(refreshes) refreshes") done"
        }
        if let refreshes = progress.refreshes {
            let noun = refreshes == 1 ? "refresh" : "refreshes"
            return "\(progress.activity) — \(refreshes) \(noun) done"
        }
        if let total = progress.total {
            let pct = total > 0 ? Int(Double(progress.completed) / Double(total) * 100) : 0
            return "\(progress.activity) — \(progress.completed) of \(total) (\(pct)%)"
        }
        if progress.completed > 0 {
            return "\(progress.activity) — \(progress.completed)"
        }
        return progress.activity
    }
}

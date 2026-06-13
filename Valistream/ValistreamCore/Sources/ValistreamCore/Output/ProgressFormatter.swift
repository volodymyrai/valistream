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

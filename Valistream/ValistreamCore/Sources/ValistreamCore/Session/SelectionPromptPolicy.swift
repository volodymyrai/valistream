//
//  SelectionPromptPolicy.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

/// Encodes whether to show the interactive playlist-selection prompt (FR-028).
public enum SelectionPromptPolicy: Sendable, Equatable {
    /// Show the interactive multi-select checklist (requires `--select` on a TTY).
    case prompt
    /// Skip the prompt; apply default (all playlists) or pattern-filtered subset.
    case skip
    /// `--select` and `--preselect` were both supplied — caller must emit a usage error.
    case usageError

    /// Derives the prompt policy from the parsed CLI flags and environment.
    ///
    /// - Parameters:
    ///   - isTTY: Whether stdout/stdin is a TTY.
    ///   - selectFlag: Whether `--select` was passed (interactive checklist request).
    ///   - preselectPatterns: Patterns from `--preselect`, if any.
    /// - Returns:
    ///   - `.usageError`  when both `--select` and `--preselect` are supplied (FR-025).
    ///   - `.prompt`      when `--select` is set and the session is on a TTY (FR-024).
    ///   - `.skip`        for all other cases: default, `--preselect`-only, or non-TTY (FR-021/023/025).
    public static func from(
        isTTY: Bool,
        selectFlag: Bool,
        preselectPatterns: [String]?
    ) -> Self {
        // Mutual exclusion takes priority over everything else.
        if selectFlag, preselectPatterns != nil { return .usageError }
        // Interactive checklist only when explicitly requested on a TTY.
        if selectFlag, isTTY { return .prompt }
        // Default (no flags), --preselect-only, or --select on a non-TTY all skip the prompt.
        return .skip
    }
}

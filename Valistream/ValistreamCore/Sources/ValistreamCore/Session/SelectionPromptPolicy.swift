//
//  SelectionPromptPolicy.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

/// Encodes whether to show the interactive playlist-selection prompt (FR-028).
public enum SelectionPromptPolicy: Sendable, Equatable {
    /// Show the interactive multi-select prompt.
    case prompt
    /// Skip the prompt and apply the documented default (all playlists, or pattern-filtered subset).
    case skip

    public static func from(
        isTTY: Bool,
        nonInteractive: Bool,
        selectionPatterns: [String]?
    ) -> Self {
        guard isTTY, !nonInteractive, selectionPatterns == nil else { return .skip }
        return .prompt
    }
}

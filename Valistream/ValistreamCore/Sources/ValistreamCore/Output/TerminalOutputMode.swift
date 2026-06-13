//
//  TerminalOutputMode.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

/// Pure output-policy value: whether SGR styling is enabled and the verbosity level.
///
/// Lives in core (zero external dependencies) so the CLI can unit-test styling decisions
/// independently of a live terminal. Construct with explicit injected booleans in tests;
/// the CLI reads the environment and calls this init directly.
public struct TerminalOutputMode: Sendable {

    // MARK: - Lets & Vars

    /// `true` iff stdout is interactive, `NO_COLOR` is unset, `--no-color` was not passed,
    /// and `TERM != "dumb"` (research D2, contracts/terminal-output.md).
    public let colorEnabled: Bool

    public let verbosity: Verbosity



    // MARK: - Lifecycle

    public init(
        isTTY: Bool,
        noColorEnv: Bool,
        noColorFlag: Bool,
        termIsDumb: Bool,
        verbosity: Verbosity
    ) {
        colorEnabled = isTTY && !noColorEnv && !noColorFlag && !termIsDumb
        self.verbosity = verbosity
    }
}

// MARK: - Verbosity

/// Verbosity level controlling on-screen detail (never affects report files or exit codes — FR-011).
public enum Verbosity: Sendable, Equatable, CaseIterable {
    case quiet
    case normal
    case verbose
}

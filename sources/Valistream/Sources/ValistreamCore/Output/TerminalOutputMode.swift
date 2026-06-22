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
import Foundation

public struct TerminalOutputMode: Sendable {

    // MARK: - Lets & Vars

    /// `true` when stdout is interactive.
    public let isTTY: Bool

    /// `true` iff stdout is interactive, `NO_COLOR` is unset, `--no-color` was not passed,
    /// and `TERM != "dumb"`.
    public let colorEnabled: Bool

    /// The marker capability selected independently from color support.
    public let glyphStyle: GlyphStyle

    public let verbosity: Verbosity



    // MARK: - Lifecycle

    public init(
        isTTY: Bool,
        noColorEnv: Bool,
        noColorFlag: Bool,
        termIsDumb: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        verbosity: Verbosity
    ) {
        self.isTTY = isTTY
        colorEnabled = isTTY && !noColorEnv && !noColorFlag && !termIsDumb
        glyphStyle = GlyphStyle.detect(environment: environment, termIsDumb: termIsDumb)
        self.verbosity = verbosity
    }
}


// MARK: - Glyph style

/// The status-marker character set supported by the terminal locale.
public enum GlyphStyle: Sendable, Equatable {
    case unicode
    case ascii

    static func detect(environment: [String: String], termIsDumb: Bool) -> GlyphStyle {
        guard termIsDumb == false else { return .ascii }
        let preferredKeys = ["LC_ALL", "LC_CTYPE", "LANG"]
        let preferredValues = preferredKeys.compactMap { environment[$0] }
        let remainingValues = environment
            .filter { $0.key.hasPrefix("LC_") && preferredKeys.contains($0.key) == false }
            .map(\.value)
        let localeValues = preferredValues + remainingValues
        let supportsUTF8 = localeValues.contains { value in
            let normalized = value.uppercased().replacing("-", with: "")
            return normalized.contains("UTF8")
        }

        return supportsUTF8 ? .unicode : .ascii
    }
}

// MARK: - Verbosity

/// Verbosity level controlling on-screen detail (never affects report files or exit codes — FR-011).
public enum Verbosity: Sendable, Equatable, CaseIterable {
    case quiet
    case normal
    case verbose
}

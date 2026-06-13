//
//  TerminalWriter.swift
//  Valistream
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

import ValistreamCore
import Foundation
import Rainbow

/// Applies TerminalOutputMode to real terminal output.
///
/// Plain text when `mode.colorEnabled == false`; Rainbow-styled otherwise. Severity is always also
/// labeled in text (ERROR/WARN/INFO/OK) so meaning is never carried by color alone (FR-009).
struct TerminalWriter: Sendable {

    // MARK: - Lets & Vars

    let mode: TerminalOutputMode



    // MARK: - Internal

    /// Returns the formatted finding line — styled when colorEnabled, plain otherwise.
    ///
    /// Separated from `writeFinding` so integration tests can verify the output without capturing stdout.
    func formatFinding(severity: Finding.Severity, message: String) -> String {
        let label: String
        switch severity {
        case .error: label = "ERROR"
        case .warning: label = "WARN"
        case .info: label = "INFO"
        }
        let line = "[\(label)] \(message)"
        return mode.colorEnabled ? styledLine(line, severity: severity) : line
    }

    /// Writes a finding line with severity label + optional color.
    func writeFinding(severity: Finding.Severity, message: String) {
        print(formatFinding(severity: severity, message: message))
    }

    /// Writes a plain status/milestone line. Suppressed in quiet mode.
    func writeStatus(_ message: String) {
        guard mode.verbosity != .quiet else { return }
        print(message)
    }

    /// Writes a blank separator between logical message groups (FR-010). Suppressed in quiet mode.
    func writeBlankLine() {
        guard mode.verbosity != .quiet else { return }
        print()
    }

    /// Writes to stderr — used in `--json` mode where stdout carries structured data.
    func writeToStderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }



    // MARK: - Private

    private func styledLine(_ text: String, severity: Finding.Severity) -> String {
        switch severity {
        case .error: text.red
        case .warning: text.yellow
        case .info: text.cyan
        }
    }
}

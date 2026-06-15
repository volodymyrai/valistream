//
//  TerminalWriter.swift
//  Valistream
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

import ValistreamCore
import Foundation
import os

/// Applies TerminalOutputMode to real terminal output.
///
/// Plain text when `mode.colorEnabled == false`; Rainbow-styled otherwise. Severity is always also
/// labeled in text (ERROR/WARN/INFO/OK) so meaning is never carried by color alone (FR-009).
struct TerminalWriter: Sendable {
    // MARK: - Nested types

    struct Line: Sendable {
        let text: String
        let role: PresentationRole
        let wholeLineTint: Bool
        let at: Date?
        /// When `true`, this line is rendered without a leading timestamp bracket.
        /// Used for quiet-mode evidence continuations that must directly follow a finding line.
        let noTimestamp: Bool

        init(
            _ text: String,
            role: PresentationRole = .metadata,
            wholeLineTint: Bool = false,
            at: Date? = nil,
            noTimestamp: Bool = false
        ) {
            self.text = text
            self.role = role
            self.wholeLineTint = wholeLineTint
            self.at = at
            self.noTimestamp = noTimestamp
        }
    }

    private struct State {
        var hasWrittenBlock = false
    }



    // MARK: - Lets & Vars

    let mode: TerminalOutputMode
    let terminalWidth: Int
    private let output: @Sendable (String) -> Void
    private let errorOutput: @Sendable (String) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())



    // MARK: - Lifecycle

    init(
        mode: TerminalOutputMode,
        terminalWidth: Int = 80,
        output: @escaping @Sendable (String) -> Void = { text in
            FileHandle.standardOutput.write(Data(text.utf8))
        },
        errorOutput: @escaping @Sendable (String) -> Void = { text in
            FileHandle.standardError.write(Data(text.utf8))
        }
    ) {
        self.mode = mode
        self.terminalWidth = max(40, terminalWidth)
        self.output = output
        self.errorOutput = errorOutput
    }



    // MARK: - Internal

    func formatFinding(severity: Finding.Severity, message: String) -> String {
        let line = "\(marker(for: severity)) \(message)"
        return mode.colorEnabled ? apply(style: role(for: severity).ansiStyle, to: line) : line
    }

    func writeFinding(
        at: Date,
        severity: Finding.Severity,
        message: String,
        evidence: String?,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        var lines = [Line(
            "\(marker(for: severity)) \(message)",
            role: role(for: severity),
            wholeLineTint: true
        )]
        if let evidence {
            lines.append(Line("Evidence: \(evidence)", role: .evidencePath))
        }
        writeBlock(at: at, groups: [lines], timeZone: timeZone)
    }

    func writeBlock(
        at: Date,
        groups: [[Line]],
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        let nonEmptyGroups = groups.filter { $0.isEmpty == false }
        guard nonEmptyGroups.isEmpty == false else { return }
        let separator = state.withLock { state in
            defer { state.hasWrittenBlock = true }
            return state.hasWrittenBlock ? "\n" : ""
        }
        let block = nonEmptyGroups.map { group in
            group.flatMap { line in
                let timestamp = TerminalTimestampFormatter.format(line.at ?? at, timeZone: timeZone)
                return formattedLines(for: line, timestamp: timestamp)
            }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        output(separator + block + "\n")
    }

    func writeMachineLine(_ line: String) {
        output(line + "\n")
    }

    func writeToStderr(_ message: String) {
        errorOutput(message + "\n")
    }

    func marker(for severity: Finding.Severity) -> String {
        switch (mode.glyphStyle, severity) {
        case (.unicode, .error): "✗ ERROR"
        case (.unicode, .warning): "⚠ WARN"
        case (.unicode, .info): "• INFO"
        case (.ascii, .error): "[ERR]"
        case (.ascii, .warning): "[WARN]"
        case (.ascii, .info): "[INFO]"
        }
    }

    func successMarker() -> String {
        mode.glyphStyle == .unicode ? "✓ OK" : "[OK]"
    }



    // MARK: - Private

    private func formattedLines(for line: Line, timestamp: String) -> [String] {
        guard line.noTimestamp == false else {
            // Quiet-mode evidence continuation: no timestamp prefix, no wrapping.
            guard mode.colorEnabled else { return [line.text] }
            return [apply(style: line.role.ansiStyle, to: line.text)]
        }
        let firstPrefix = timestamp + " "
        let continuation = mode.glyphStyle == .unicode ? "  ↳ " : "  -> "
        let continuationPrefix = timestamp + continuation
        let chunks = wrap(
            line.text,
            firstWidth: terminalWidth - firstPrefix.count,
            continuationWidth: terminalWidth - continuationPrefix.count
        )

        return chunks.enumerated().map { index, chunk in
            let prefix = index == 0 ? firstPrefix : continuationPrefix
            let plain = prefix + chunk
            guard mode.colorEnabled else { return plain }
            if line.wholeLineTint {
                return apply(style: line.role.ansiStyle, to: plain)
            }
            return prefix + apply(style: line.role.ansiStyle, to: chunk)
        }
    }

    private func wrap(_ text: String, firstWidth: Int, continuationWidth: Int) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.isEmpty == false else { return [""] }
        var lines: [String] = []
        var current = ""
        var width = max(1, firstWidth)

        func appendWord(_ word: String) {
            var remainder = word
            while remainder.count > width {
                let splitIndex = remainder.index(remainder.startIndex, offsetBy: width)
                lines.append(String(remainder[..<splitIndex]))
                remainder = String(remainder[splitIndex...])
                width = max(1, continuationWidth)
            }
            current = remainder
        }

        for word in words {
            if current.isEmpty {
                appendWord(word)
            }
            else if current.count + 1 + word.count <= width {
                current += " " + word
            }
            else {
                lines.append(current)
                width = max(1, continuationWidth)
                current = ""
                appendWord(word)
            }
        }
        if current.isEmpty == false {
            lines.append(current)
        }

        return lines
    }

    private func role(for severity: Finding.Severity) -> PresentationRole {
        switch severity {
        case .error: .error
        case .warning: .warning
        case .info: .metadata
        }
    }

    private func apply(style: TerminalANSIStyle, to text: String) -> String {
        let code = switch style {
        case .bold: "1"
        case .red: "31"
        case .yellow: "33"
        case .green: "32"
        case .cyan: "36"
        case .dim: "2"
        }
        return "\u{1B}[\(code)m\(text)\u{1B}[0m"
    }
}

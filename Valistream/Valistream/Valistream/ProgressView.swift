//
//  ProgressView.swift
//  Valistream
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

import Darwin
import Foundation
import ValistreamCore

/// Renders live progress from ``ActivityProgress`` events onto the terminal.
///
/// Styled interactive output gets one timestamped in-place heartbeat.
/// Plain and machine output omit it so it cannot compete with persistent blocks.
struct ProgressView: Sendable {

    // MARK: - Lets & Vars

    let mode: TerminalOutputMode
    private(set) var spinnerIndex: Int = 0
    private static let frames: [String] = ["|", "/", "-", "\\"]



    // MARK: - Internal

    /// Updates the transient progress display without producing a persistent output block.
    mutating func render(_ progress: ActivityProgress, at: Date) {
        guard mode.colorEnabled, mode.verbosity != .quiet else { return }
        let timestamp = TerminalTimestampFormatter.format(at)
        let text = "\(timestamp) \(ProgressFormatter.format(progress))"
        let frame = Self.frames[spinnerIndex % Self.frames.count]
        spinnerIndex += 1
        let width = Self.terminalWidth()
        let truncationMarker = mode.glyphStyle == .unicode ? "…" : "..."
        let maxText = max(0, width - 3 - truncationMarker.count)
        let display = text.count > maxText ? String(text.prefix(maxText)) + truncationMarker : text
        FileHandle.standardOutput.write(Data("\r\u{1B}[K\(frame) \(display)".utf8))
    }

    /// Erases the in-place progress line on styled interactive runs.
    func clearLine() {
        guard mode.colorEnabled else { return }
        FileHandle.standardOutput.write(Data("\r\u{1B}[K".utf8))
    }

    static func terminalWidth() -> Int {
        var ws = winsize()
        return ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 ? Int(ws.ws_col) : 80
    }
}

//
//  ProgressView.swift
//  Valistream
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

import Foundation
import ValistreamCore

/// Renders live progress from ``ActivityProgress`` events onto the terminal.
///
/// On a TTY: overwrites the current line with a spinner + formatted text (SC-001, SC-002).
/// On non-TTY / no-color: prints one discrete plain line per event (FR-007, SC-004).
/// Call `clearLine()` before printing any other output so the progress line doesn't bleed.
struct ProgressView: Sendable {

    // MARK: - Lets & Vars

    let mode: TerminalOutputMode
    private(set) var spinnerIndex: Int = 0
    private static let frames: [String] = ["|", "/", "-", "\\"]



    // MARK: - Internal

    /// Updates the progress display. Mutates `spinnerIndex` on TTY runs.
    mutating func render(_ progress: ActivityProgress) {
        if mode.colorEnabled {
            let text = ProgressFormatter.format(progress)
            let frame = Self.frames[spinnerIndex % Self.frames.count]
            spinnerIndex += 1
            FileHandle.standardOutput.write(Data("\r\u{1B}[K\(frame) \(text)".utf8))
        }
        else {
            guard mode.verbosity != .quiet else { return }
            print(ProgressFormatter.format(progress))
        }
    }

    /// Erases the in-place progress line on TTY. No-op on non-TTY.
    func clearLine() {
        guard mode.colorEnabled else { return }
        FileHandle.standardOutput.write(Data("\r\u{1B}[K".utf8))
    }
}

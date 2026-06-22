//
//  LiveInputGuard.swift
//  Valistream
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import Darwin

/// Suppresses terminal echo and line-buffering during live monitoring so stray
/// keystrokes (Enter, arrows) do not corrupt the in-place heartbeat region.
///
/// Activated only when both stdin and stdout are a TTY. On non-TTY (piped) runs the
/// guard does nothing and emits no control bytes (inherited styling gate, SC-003).
///
/// Usage:
/// ```swift
/// let inputGuard = LiveInputGuard(isTTY: tty)
/// let saved = inputGuard.activate()
/// defer { inputGuard.deactivate(saved) }
/// // … run live monitoring …
/// ```
///
/// `deactivate(_:)` **must** be called on every exit path. Use `defer` to guarantee
/// restoration even on cancellation or forced exit (D8, FR-014).
struct LiveInputGuard: Sendable {

    // MARK: - Lets & Vars

    private let isTTY: Bool



    // MARK: - Lifecycle

    init(isTTY: Bool = false) {
        self.isTTY = isTTY
            && isatty(STDIN_FILENO) == 1
            && isatty(STDOUT_FILENO) == 1
    }



    // MARK: - Internal

    /// Saves the current termios state and disables `ECHO` + `ICANON`.
    ///
    /// Returns the saved state for restoration, or `nil` if the guard is not active
    /// (non-TTY, or `tcgetattr` failed).
    ///
    /// The caller is responsible for passing the returned value to `deactivate(_:)`.
    @discardableResult
    func activate() -> termios? {
        guard isTTY else { return nil }
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return nil }
        var raw = original
        raw.c_lflag &= ~(UInt(ECHO) | UInt(ICANON))
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { return nil }
        return original
    }

    /// Restores the previously saved termios state.
    ///
    /// Safe to call even when `activate()` returned `nil` — a nil original is silently ignored.
    func deactivate(_ original: termios?) {
        guard isTTY, var saved = original else { return }
        tcsetattr(STDIN_FILENO, TCSANOW, &saved)
    }
}

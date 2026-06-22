//
//  PlaylistChecklist.swift
//  Valistream
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import ValistreamCore

/// Interactive checkbox multi-select for choosing which playlists to monitor (FR-018, research §7).
///
/// On a terminal it renders a checkbox list — arrows move, space toggles, `a` toggles all, enter
/// confirms — all pre-selected. When raw-mode input is unavailable it falls back to a numbered-list
/// prompt; with no terminal attached at all it selects every playlist (the unattended default).
struct PlaylistChecklist {
    // MARK: - Lets & Vars

    let candidates: [PlaylistSelection.Candidate]



    // MARK: - Internal

    /// Presents the checklist and returns the chosen candidates.
    func run() -> [PlaylistSelection.Candidate] {
        guard candidates.isEmpty == false else { return [] }
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else { return candidates }
        if let selection = runRawMode() {
            return selection
        }
        return runNumbered()
    }



    // MARK: - Private

    private func label(_ candidate: PlaylistSelection.Candidate) -> String {
        let detail = candidate.name ?? candidate.url.lastPathComponent
        return "\(candidate.id) (\(candidate.role.rawValue)) — \(detail)"
    }

    /// Raw-mode checkbox UI. Returns `nil` if raw mode cannot be entered, so the caller can fall back.
    private func runRawMode() -> [PlaylistSelection.Candidate]? {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return nil }
        var raw = original
        raw.c_lflag &= ~(UInt(ECHO) | UInt(ICANON))
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { return nil }
        defer {
            var restore = original
            tcsetattr(STDIN_FILENO, TCSANOW, &restore)
        }

        var selected = [Bool](repeating: true, count: candidates.count)
        var cursor = 0
        print("Select playlists to monitor (↑/↓ move, space toggle, a toggle all, enter confirm):")
        draw(selected: selected, cursor: cursor, first: true)

        while let key = readKey() {
            switch key {
            case .up:
                cursor = (cursor - 1 + candidates.count) % candidates.count
            case .down:
                cursor = (cursor + 1) % candidates.count
            case .toggle:
                selected[cursor].toggle()
            case .toggleAll:
                let allOn = selected.allSatisfy { $0 }
                selected = [Bool](repeating: !allOn, count: candidates.count)
            case .confirm, .cancel:
                draw(selected: selected, cursor: cursor, first: false)
                return chosen(selected)
            }
            draw(selected: selected, cursor: cursor, first: false)
        }
        return chosen(selected)
    }

    /// Redraws the checkbox list in place, moving the cursor back up over the previous render.
    private func draw(selected: [Bool], cursor: Int, first: Bool) {
        if first == false {
            // Move up over the previously drawn rows to overwrite them.
            print("\u{1B}[\(candidates.count)A", terminator: "")
        }
        for (index, candidate) in candidates.enumerated() {
            let box = selected[index] ? "[x]" : "[ ]"
            let pointer = index == cursor ? ">" : " "
            print("\u{1B}[2K\r\(pointer) \(box) \(label(candidate))")
        }
    }

    /// Numbered-list fallback for terminals without raw-mode support.
    private func runNumbered() -> [PlaylistSelection.Candidate] {
        print("Select playlists to monitor. Enter comma-separated numbers, or blank for all:")
        for (index, candidate) in candidates.enumerated() {
            print("  \(index + 1). \(label(candidate))")
        }
        guard let line = readLine(strippingNewline: true), line.isEmpty == false else {
            return candidates
        }
        let indices = line
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .map { $0 - 1 }
            .filter { candidates.indices.contains($0) }
        guard indices.isEmpty == false else { return candidates }
        return indices.map { candidates[$0] }
    }

    private func chosen(_ selected: [Bool]) -> [PlaylistSelection.Candidate] {
        zip(candidates, selected).compactMap { candidate, isOn in isOn ? candidate : nil }
    }

    private func readKey() -> Key? {
        var byte: UInt8 = 0
        guard read(STDIN_FILENO, &byte, 1) == 1 else { return nil }
        switch byte {
        case 0x0A, 0x0D:
            return .confirm
        case 0x20:
            return .toggle
        case 0x71, 0x51:  // q / Q
            return .cancel
        case 0x61, 0x41:  // a / A
            return .toggleAll
        case 0x1B:        // ESC — possible arrow-key sequence
            var bracket: UInt8 = 0
            var code: UInt8 = 0
            guard read(STDIN_FILENO, &bracket, 1) == 1, bracket == 0x5B,
                  read(STDIN_FILENO, &code, 1) == 1
            else {
                return nil
            }
            switch code {
            case 0x41: return .up
            case 0x42: return .down
            default: return nil
            }
        default:
            return nil
        }
    }
}

// MARK: - Key

private extension PlaylistChecklist {
    enum Key {
        case up
        case down
        case toggle
        case toggleAll
        case confirm
        case cancel
    }
}

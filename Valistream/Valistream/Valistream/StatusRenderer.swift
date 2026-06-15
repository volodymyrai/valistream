//
//  StatusRenderer.swift
//  Valistream
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import ValistreamCore

/// Renders session events to the terminal (FR-009) in either human or `--json` mode.
///
/// Human mode routes findings + status through `TerminalWriter` (color/verbosity gating);
/// `--json` mode prints one JSON object per finding to stdout and routes status chrome to stderr
/// (contracts/cli-interface.md).
struct StatusRenderer: Sendable {

    // MARK: - Lets & Vars

    let writer: TerminalWriter
    let json: Bool



    // MARK: - Internal

    /// Renders a single session event. Skips `.activity` because ``ProgressView`` owns it.
    /// Renders a single session event. Skips `.activity` because ``ProgressView`` owns it.
    ///
    /// Tier supersets (quiet ⊆ normal ⊆ verbose) are enforced here per the Output message catalog.
    func render(_ event: SessionEvent) {
        switch event {
        case .stateChanged(let state):
            renderEventStatus(["type": "status", "state": state.rawValue], human: "• \(state.rawValue)")

        case .streamClassified(let kind):
            renderEventStatus(
                ["type": "status", "classification": kind.rawValue],
                human: "• stream classified as \(kind.rawValue)"
            )

        case .monitorStateChanged(let playlistID, let state):
            renderEventStatus(
                ["type": "status", "playlist": playlistID, "monitorState": state.rawValue],
                human: "• [\(playlistID)] \(state.rawValue)"
            )

        case .finding(let finding, let evidence):
            renderFinding(finding, evidence: evidence)

        case .rosterReady(let entries):
            renderRoster(entries)

        case .refreshCompleted(let playlistID, let index, let errors, let warnings):
            renderRefreshCompleted(playlistID: playlistID, index: index, errors: errors, warnings: warnings)

        case .trace(let traceEvent):
            renderTrace(traceEvent)

        case .activity, .sessionFolderResolved, .playlistInformation, .playlistLifecycle:
            break
        }
    }

    /// Prints the end-of-session summary block.
    func renderSummary(findings: [Finding], state: SessionState, sessionFolder: String?) {
        let errors = findings.count(where: { $0.severity == .error })
        let warnings = findings.count(where: { $0.severity == .warning })
        let infos = findings.count(where: { $0.severity == .info })
        renderStatus("")
        renderStatus("Session \(state.rawValue): \(errors) error(s), \(warnings) warning(s), \(infos) info.")
        if let sessionFolder {
            renderStatus("Artifacts: \(sessionFolder)")
        }
    }

    /// Formats one human-readable finding using a pre-resolved evidence reference.
    func formatFinding(_ finding: Finding, evidence: EvidenceReference) -> String {
        writer.formatFinding(severity: finding.severity, message: evidence.terminalMessage(for: finding))
    }



    // MARK: - Private

    private func renderFinding(_ finding: Finding, evidence: EvidenceReference?) {
        if json {
            if let data = try? Finding.jsonEncoder.encode(finding),
               let line = String(data: data, encoding: .utf8) {
                print(line)
            }
            return
        }
        if let evidence {
            print(formatFinding(finding, evidence: evidence))
        }
        else {
            writer.writeFinding(severity: finding.severity, message: finding.message)
        }
    }

    /// Prints the start-of-session roster: each ID → full URL + role. The roster is the only
    /// place full URLs appear; the body uses IDs only (FR-011/012, SC-003). Normal+ tier.
    private func renderRoster(_ entries: [RosterEntry]) {
        renderStatus("Playlists:")
        for entry in entries {
            var line = "  \(entry.id) → \(entry.url.absoluteString) [\(entry.role)]"
            if let attributes = entry.attributes, attributes.isEmpty == false {
                line += " \(attributes)"
            }
            renderStatus(line)
        }
    }

    /// Prints the per-refresh roll-up status line as `<id>_<n> — OK` or
    /// `<id>_<n> — x WARN, y ERROR` (FR-015a). Normal+ tier.
    private func renderRefreshCompleted(playlistID: String, index: Int, errors: Int, warnings: Int) {
        let snapshot = SnapshotID.label(id: playlistID, index: index)
        guard errors > 0 || warnings > 0 else {
            renderStatus("\(snapshot) — OK")
            return
        }
        var parts: [String] = []
        if warnings > 0 { parts.append("\(warnings) WARN") }
        if errors > 0 { parts.append("\(errors) ERROR") }
        renderStatus("\(snapshot) — \(parts.joined(separator: ", "))")
    }

    /// Prints a verbose-tier action trace line via the shared catalog formatter (FR-015b, D9).
    /// Gated to `--verbose` so quiet/normal tiers never see it (tier supersets, SC-005).
    private func renderTrace(_ event: TraceEvent) {
        guard writer.mode.verbosity == .verbose else { return }
        renderStatus(TraceFormatter.format(event))
    }

    private func renderEventStatus(_ object: [String: String], human: String) {
        guard writer.mode.verbosity != .quiet else { return }
        if json {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                  let line = String(data: data, encoding: .utf8)
            else { return }
            print(line)
        }
        else {
            writer.writeStatus(human)
        }
    }

    private func renderStatus(_ message: String) {
        guard writer.mode.verbosity != .quiet else { return }
        if json {
            writer.writeToStderr(message)
        }
        else {
            writer.writeStatus(message)
        }
    }
}

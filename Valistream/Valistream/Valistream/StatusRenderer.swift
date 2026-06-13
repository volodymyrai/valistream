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

    /// Renders a single session event. Skips `.activity` — those go to ``ProgressView``.
    func render(_ event: SessionEvent) {
        switch event {
        case .stateChanged(let state):
            renderEventStatus(["type": "status", "state": state.rawValue], human: "• \(state.rawValue)")
        case .streamClassified(let kind):
            renderEventStatus(["type": "status", "classification": kind.rawValue], human: "• stream classified as \(kind.rawValue)")
        case .monitorStateChanged(let playlistID, let state):
            renderEventStatus(
                ["type": "status", "playlist": playlistID, "monitorState": state.rawValue],
                human: "• [\(playlistID)] \(state.rawValue)"
            )
        case .finding(let finding):
            renderFinding(finding)
        case .activity:
            break
        }
    }

    /// Prints the end-of-session summary block.
    func renderSummary(findings: [Finding], state: SessionState, sessionFolder: String?) {
        let errors   = findings.count(where: { $0.severity == .error })
        let warnings = findings.count(where: { $0.severity == .warning })
        let infos    = findings.count(where: { $0.severity == .info })
        renderStatus("")
        renderStatus("Session \(state.rawValue): \(errors) error(s), \(warnings) warning(s), \(infos) info.")
        if let sessionFolder {
            renderStatus("Artifacts: \(sessionFolder)")
        }
    }



    // MARK: - Private

    private func renderFinding(_ finding: Finding) {
        if json {
            if let data = try? Finding.jsonEncoder.encode(finding), let line = String(data: data, encoding: .utf8) {
                print(line)
            }
            return
        }
        let location = finding.location?.line.map { " :\($0)" } ?? ""
        let message  = "[\(finding.category.rawValue)/\(finding.ruleId)] \(finding.resource.absoluteString)\(location) — \(finding.message)"
        writer.writeFinding(severity: finding.severity, message: message)
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

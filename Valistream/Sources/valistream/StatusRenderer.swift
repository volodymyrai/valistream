//
//  StatusRenderer.swift
//  valistream
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import ValistreamCore

/// Renders session events to the terminal (FR-009) in either human or `--json` mode.
///
/// Human mode prints findings to stdout and status chrome to stdout; `--json` mode prints one JSON
/// object per finding to stdout and routes status chrome to stderr (contracts/cli-interface.md).
struct StatusRenderer: Sendable {
    // MARK: - Lets & Vars

    let json: Bool
    let quiet: Bool



    // MARK: - Internal

    /// Renders a single session event.
    func render(_ event: SessionEvent) {
        switch event {
        case .stateChanged(let state):
            renderStatus("• \(state.rawValue)")
        case .streamClassified(let kind):
            renderStatus("• stream classified as \(kind.rawValue)")
        case .finding(let finding):
            renderFinding(finding)
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



    // MARK: - Private

    private func renderFinding(_ finding: Finding) {
        if json {
            if let data = try? Finding.jsonEncoder.encode(finding), let line = String(data: data, encoding: .utf8) {
                print(line)
            }
            return
        }
        let level = finding.severity.rawValue.uppercased()
        let location = finding.location?.line.map { " :\($0)" } ?? ""
        print("\(level) [\(finding.category.rawValue)/\(finding.ruleId)] \(finding.resource.absoluteString)\(location) — \(finding.message)")
    }

    private func renderStatus(_ message: String) {
        guard !quiet else { return }
        if json {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        else {
            print(message)
        }
    }
}

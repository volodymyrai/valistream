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
    // MARK: - Nested types

    private struct RefreshKey: Hashable, Sendable {
        let playlistID: String
        let index: Int
    }

    private struct PendingFinding: Sendable {
        let at: Date
        let finding: Finding
        let evidence: EvidenceReference?
    }



    // MARK: - Lets & Vars

    let writer: TerminalWriter
    let json: Bool
    let timeZone: TimeZone
    private var pendingFindings: [RefreshKey: [PendingFinding]] = [:]
    private var loadedPlaylistIDs: Set<String> = []
    private var rosterIDsByURL: [URL: String] = [:]

    var playlistCount: Int {
        loadedPlaylistIDs.count
    }



    // MARK: - Lifecycle

    init(writer: TerminalWriter, json: Bool, timeZone: TimeZone = .autoupdatingCurrent) {
        self.writer = writer
        self.json = json
        self.timeZone = timeZone
    }



    // MARK: - Internal

    mutating func render(_ timestampedEvent: TimestampedEvent) {
        guard json == false else { return }
        let at = timestampedEvent.at
        switch timestampedEvent.event {
        case .stateChanged(let state):
            renderState(state, at: at)
        case .streamClassified(let kind):
            guard writer.mode.verbosity != .quiet else { return }
            writeBlock(at: at, lines: [
                .init("Detected a \(kind.rawValue) stream.", role: .success),
            ])
        case .monitorStateChanged(let playlistID, let state):
            renderMonitorState(state, playlistID: playlistID, at: at)
        case .finding(let finding, let evidence):
            buffer(finding: finding, evidence: evidence, at: at)
        case .sessionFolderResolved(let folder):
            guard writer.mode.verbosity != .quiet else { return }
            writeBlock(at: at, lines: [
                .init("Ready: session output folder is \(folder.path(percentEncoded: false)).", role: .evidencePath),
            ])
        case .playlistInformation(let information):
            renderPlaylistInformation(information, at: at)
        case .playlistLifecycle(let lifecycle):
            renderLifecycle(lifecycle, at: at)
        case .rosterReady(let entries):
            renderRoster(entries, at: at)
        case .refreshCompleted(let playlistID, let index, let errors, let warnings):
            renderRefreshCompleted(
                playlistID: playlistID,
                index: index,
                errors: errors,
                warnings: warnings,
                at: at
            )
        case .trace(let traceEvent):
            renderTrace(traceEvent, at: at)
        case .activity:
            break
        }
    }

    func render(_ event: SessionEvent) {
        guard json else { return }
        switch event {
        case .stateChanged(let state):
            writeJSONObject(["type": "status", "state": state.rawValue])
        case .streamClassified(let kind):
            writeJSONObject(["type": "status", "classification": kind.rawValue])
        case .monitorStateChanged(let playlistID, let state):
            writeJSONObject([
                "type": "status",
                "playlist": playlistID,
                "monitorState": state.rawValue,
            ])
        case .finding(let finding, _):
            if let data = try? Finding.jsonEncoder.encode(finding),
               let line = String(data: data, encoding: .utf8) {
                writer.writeMachineLine(line)
            }
        case .rosterReady(let entries):
            writer.writeToStderr("Playlists: \(entries.count)")
        case .refreshCompleted(let playlistID, let index, let errors, let warnings):
            writer.writeToStderr(
                "\(SnapshotID.label(id: playlistID, index: index)) — \(warnings) WARN, \(errors) ERROR"
            )
        case .trace(let traceEvent):
            if writer.mode.verbosity == .verbose {
                writer.writeToStderr(TraceFormatter.format(traceEvent))
            }
        case .activity, .sessionFolderResolved, .playlistInformation, .playlistLifecycle:
            break
        }
    }

    mutating func renderSummary(
        findings: [Finding],
        state: SessionState,
        sessionFolder: String?,
        elapsed: Duration,
        playlistCount: Int,
        reportPath: String?,
        at: Date
    ) {
        guard json == false else { return }
        flushPendingFindings(defaultAt: at)
        let errors = findings.count(where: { $0.severity == .error })
        let warnings = findings.count(where: { $0.severity == .warning })
        let outcome = summaryOutcome(for: state, errors: errors)
        var lines = [TerminalWriter.Line(
            "\(outcome): \(playlistCount) playlist\(playlistCount == 1 ? "" : "s") processed; "
                + "\(errors) error\(errors == 1 ? "" : "s"), "
                + "\(warnings) warning\(warnings == 1 ? "" : "s"); elapsed \(seconds(elapsed)) s.",
            role: .summary
        )]
        if let reportPath {
            lines.append(.init("Wrote report: \(reportPath)", role: .evidencePath))
        }
        if let sessionFolder {
            lines.append(.init("Saved session: \(sessionFolder)", role: .evidencePath))
        }
        writeBlock(at: at, lines: lines)
    }

    func formatFinding(_ finding: Finding, evidence: EvidenceReference) -> String {
        writer.formatFinding(severity: finding.severity, message: evidence.terminalMessage(for: finding))
    }



    // MARK: - Private

    private mutating func renderState(_ state: SessionState, at: Date) {
        if writer.mode.verbosity == .quiet, state != .aborted, state != .failed {
            return
        }
        let line: TerminalWriter.Line? = switch state {
        case .initializing:
            .init("Ready to validate the stream.", role: .heading)
        case .monitoring:
            .init("Ready to monitor selected playlists.", role: .progress)
        case .completed:
            nil
        case .aborted:
            .init("Interrupted: validation session stopped.", role: .warning, wholeLineTint: true)
        case .failed:
            .init("Failed: validation session could not continue.", role: .error, wholeLineTint: true)
        case .fetchingMaster, .validatingInitial, .selectingPlaylists, .finishing:
            nil
        }
        if let line {
            writeBlock(at: at, lines: [line])
        }
    }

    private mutating func renderMonitorState(_ state: MonitorState, playlistID: String, at: Date) {
        switch state {
        case .staleWarning:
            writeBlock(at: at, lines: [
                .init(
                    "\(writer.marker(for: .warning)) Warning: \(playlistID) is stale.",
                    role: .warning,
                    wholeLineTint: true
                ),
            ])
        case .staleError:
            writeBlock(at: at, lines: [
                .init(
                    "\(writer.marker(for: .error)) Error: \(playlistID) is unavailable.",
                    role: .error,
                    wholeLineTint: true
                ),
            ])
        case .idle, .monitoring, .stopped:
            break
        }
    }

    private mutating func renderRoster(_ entries: [RosterEntry], at: Date) {
        guard writer.mode.verbosity != .quiet else { return }
        rosterIDsByURL = Dictionary(uniqueKeysWithValues: entries.map { ($0.url, $0.id) })
        var lines = [TerminalWriter.Line(
            "Discovered \(entries.count) playlist\(entries.count == 1 ? "" : "s"):",
            role: .heading
        )]
        lines.append(contentsOf: entries.map { entry in
            var text = "Loaded \(entry.id): \(entry.url.absoluteString) [\(entry.role)]"
            if let attributes = entry.attributes, attributes.isEmpty == false {
                text += " \(attributes)"
            }
            return TerminalWriter.Line(text, role: .identifier)
        })
        writeBlock(at: at, lines: lines)
    }

    private mutating func renderPlaylistInformation(_ information: PlaylistInformation, at: Date) {
        guard loadedPlaylistIDs.insert(information.playlistID).inserted else { return }
        guard writer.mode.verbosity != .quiet else { return }
        let fieldGroups = PlaylistInfoFormatter.groups(for: information)
        let groups = fieldGroups.enumerated().map { index, group in
            var lines: [TerminalWriter.Line] = []
            if index == 0 {
                lines.append(.init(
                    "Loaded playlist information for \(information.playlistID).",
                    role: .heading
                ))
            }
            lines.append(.init("\(group.title):", role: .metadata))
            lines.append(contentsOf: group.fields.map { field in
                .init("  \(field.label): \(field.value)", role: .metadata)
            })
            return lines
        }
        writer.writeBlock(at: at, groups: groups, timeZone: timeZone)
    }

    private mutating func renderLifecycle(_ lifecycle: PlaylistLifecycleEvent, at: Date) {
        let text: String
        let role: PresentationRole
        switch lifecycle.kind {
        case .unavailable:
            text = "Unavailable: \(lifecycle.playlistID) cannot be refreshed."
            role = .error
        case .recovered:
            text = "Recovered: \(lifecycle.playlistID) is refreshing again."
            role = .success
        case .added:
            text = "Added: \(lifecycle.playlistID) joined the playlist roster."
            role = .success
        case .removed:
            text = "Removed: \(lifecycle.playlistID) left the playlist roster."
            role = .warning
        case .identityChanged:
            text = "Changed: \(lifecycle.playlistID) has a new identity."
            role = .warning
        }
        writeBlock(at: at, lines: [.init(text, role: role, wholeLineTint: role == .warning || role == .error)])
    }

    private mutating func buffer(finding: Finding, evidence: EvidenceReference?, at: Date) {
        // Quiet mode: suppress informational findings entirely.
        if writer.mode.verbosity == .quiet, finding.severity == .info { return }
        guard finding.refreshIndex != nil, let key = refreshKey(for: finding, evidence: evidence) else {
            let snapshot = SnapshotID.label(
                id: rosterIDsByURL[finding.resource] ?? "playlist",
                index: finding.refreshIndex ?? 0
            )
            writeBlock(at: at, lines: findingLines(
                PendingFinding(at: at, finding: finding, evidence: evidence),
                snapshot: snapshot
            ))
            return
        }
        pendingFindings[key, default: []].append(PendingFinding(at: at, finding: finding, evidence: evidence))
    }

    private mutating func renderRefreshCompleted(
        playlistID: String,
        index: Int,
        errors: Int,
        warnings: Int,
        at: Date
    ) {
        guard writer.mode.verbosity != .quiet || errors > 0 || warnings > 0 else { return }
        let snapshot = SnapshotID.label(id: playlistID, index: index)
        let severity: Finding.Severity = errors > 0 ? .error : (warnings > 0 ? .warning : .info)
        let result: String
        if errors == 0 && warnings == 0 {
            result = "\(writer.successMarker()) Refreshed \(snapshot): no findings."
        }
        else {
            result = "\(writer.marker(for: severity)) Refreshed \(snapshot): "
                + "\(warnings) warning\(warnings == 1 ? "" : "s"), "
                + "\(errors) error\(errors == 1 ? "" : "s")."
        }
        let role: PresentationRole = errors > 0 ? .error : (warnings > 0 ? .warning : .success)
        var lines = [TerminalWriter.Line(result, role: role, wholeLineTint: true)]
        let findings = pendingFindings.removeValue(forKey: RefreshKey(playlistID: playlistID, index: index)) ?? []
        lines.append(contentsOf: findings.flatMap { findingLines($0, snapshot: snapshot) })
        writeBlock(at: at, lines: lines)
    }

    private mutating func renderTrace(_ event: TraceEvent, at: Date) {
        guard writer.mode.verbosity == .verbose else { return }
        writeBlock(at: at, lines: [.init(TraceFormatter.format(event), role: .metadata)])
    }

    private func findingLines(_ pending: PendingFinding, snapshot: String) -> [TerminalWriter.Line] {
        let severity = pending.finding.severity
        var lines = [TerminalWriter.Line(
            "\(writer.marker(for: severity)) \(findingOutcome(severity)) \(snapshot): \(pending.finding.message)",
            role: severity == .error ? .error : (severity == .warning ? .warning : .metadata),
            wholeLineTint: severity != .info,
            at: pending.at
        )]
        // In quiet mode, evidence lines must directly follow the finding line without a timestamp
        // bracket so the human can read `message\nEvidence: path` as one unit (R10, US2 T041).
        let quietEvidence = writer.mode.verbosity == .quiet
        lines.append(contentsOf: evidenceLines(pending.evidence).map { evidence in
            .init(evidence, role: .evidencePath, at: pending.at, noTimestamp: quietEvidence)
        })
        return lines
    }

    private func evidenceLines(_ evidence: EvidenceReference?) -> [String] {
        guard let evidence else { return ["Evidence unavailable."] }
        return switch evidence {
        case .single(let path):
            ["Evidence: \(path)"]
        case .pair(let older, let newer):
            [older, newer].compactMap { $0 }.map { "Evidence: \($0)" }
                + (older == nil ? ["Evidence: older snapshot unavailable."] : [])
                + (newer == nil ? ["Evidence: newer snapshot unavailable."] : [])
        case .unavailable(let id):
            ["Evidence unavailable for \(id)."]
        }
    }

    private func refreshKey(for finding: Finding, evidence: EvidenceReference?) -> RefreshKey? {
        let index = max(finding.refreshIndex ?? 0, 0)
        switch evidence {
        case .single(let path):
            if let parsed = SnapshotID.parse(URL(filePath: path).deletingPathExtension().lastPathComponent) {
                return RefreshKey(playlistID: parsed.id, index: parsed.index)
            }
        case .pair(let older, let newer):
            if let path = older ?? newer,
               let parsed = SnapshotID.parse(URL(filePath: path).deletingPathExtension().lastPathComponent) {
                return RefreshKey(playlistID: parsed.id, index: index)
            }
        case .unavailable(let id):
            return RefreshKey(playlistID: id, index: index)
        case nil:
            break
        }
        if let id = rosterIDsByURL[finding.resource] {
            return RefreshKey(playlistID: id, index: index)
        }

        return nil
    }

    private mutating func flushPendingFindings(defaultAt: Date) {
        let pending = pendingFindings.sorted { lhs, rhs in
            if lhs.key.playlistID == rhs.key.playlistID { return lhs.key.index < rhs.key.index }
            return lhs.key.playlistID < rhs.key.playlistID
        }
        pendingFindings.removeAll()
        for (key, findings) in pending {
            let snapshot = SnapshotID.label(id: key.playlistID, index: key.index)
            let lines = findings.flatMap { findingLines($0, snapshot: snapshot) }
            writer.writeBlock(at: findings.first?.at ?? defaultAt, groups: [lines], timeZone: timeZone)
        }
    }

    private func writeBlock(at: Date, lines: [TerminalWriter.Line]) {
        writer.writeBlock(at: at, groups: [lines], timeZone: timeZone)
    }

    private func writeJSONObject(_ object: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else { return }
        writer.writeMachineLine(line)
    }

    private func findingOutcome(_ severity: Finding.Severity) -> String {
        switch severity {
        case .error: "Error"
        case .warning: "Warning"
        case .info: "Found"
        }
    }

    private func summaryOutcome(for state: SessionState, errors: Int) -> String {
        if state == .failed { return "Failed" }
        if state == .aborted { return "Interrupted" }
        return errors > 0 ? "Invalid" : "Complete"
    }

    private func seconds(_ duration: Duration) -> String {
        let components = duration.components
        let value = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return value.formatted(
            .number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0...3))
        )
    }
}

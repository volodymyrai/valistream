//
//  SessionReportBuilder.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Builds the final session report as `report.json` and `report.md` from a snapshot of session
/// state (data-model.md SessionReport, contracts/session-report.schema.json).
public struct SessionReportBuilder: Sendable {
    // MARK: - Nested types

    /// A summary of one playlist's participation in the session.
    public struct PlaylistInfo: Sendable {
        public let id: String
        public let kind: PlaylistKind
        public let role: PlaylistRole?
        public let url: URL
        public let selected: Bool
        public let excludedByChoice: Bool
        public let refreshCount: Int
        public let cadenceAdherence: Double?
        public let stalenessEpisodes: Int

        public init(
            id: String,
            kind: PlaylistKind,
            role: PlaylistRole?,
            url: URL,
            selected: Bool,
            excludedByChoice: Bool = false,
            refreshCount: Int,
            cadenceAdherence: Double? = nil,
            stalenessEpisodes: Int = 0
        ) {
            self.id = id
            self.kind = kind
            self.role = role
            self.url = url
            self.selected = selected
            self.excludedByChoice = excludedByChoice
            self.refreshCount = refreshCount
            self.cadenceAdherence = cadenceAdherence
            self.stalenessEpisodes = stalenessEpisodes
        }
    }

    /// A snapshot of session state needed to build the report.
    public struct SessionSnapshot: Sendable {
        public let id: String
        public let inputURL: URL
        public let startedAt: Date
        public let endedAt: Date
        public let state: SessionState
        public let config: SessionConfig
        public let streamKind: StreamKind?
        public let lowLatencyDetected: Bool
        public let encryptionDetected: Bool
        public let interruption: String?

        public init(
            id: String,
            inputURL: URL,
            startedAt: Date,
            endedAt: Date,
            state: SessionState,
            config: SessionConfig,
            streamKind: StreamKind?,
            lowLatencyDetected: Bool,
            encryptionDetected: Bool,
            interruption: String? = nil
        ) {
            self.id = id
            self.inputURL = inputURL
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.state = state
            self.config = config
            self.streamKind = streamKind
            self.lowLatencyDetected = lowLatencyDetected
            self.encryptionDetected = encryptionDetected
            self.interruption = interruption
        }
    }

    // Private Codable types matching contracts/session-report.schema.json

    private struct Report: Encodable {
        let schemaVersion: Int
        let session: SessionPayload
        let stream: StreamPayload
        let playlists: [PlaylistPayload]
        let findings: [Finding]
        let segmentAudit: SegmentAuditPayload?
        let summary: SummaryPayload
        let artifactIndex: [ArtifactIndexEntry]
    }

    private struct SessionPayload: Encodable {
        let id: String
        let inputUrl: String
        let startedAt: Date
        let endedAt: Date
        let state: String
        let interruption: String?
        let config: ConfigPayload
    }

    private struct ConfigPayload: Encodable {
        let segmentMode: Bool
        let bandwidthTolerance: Double
        let timeLimitSeconds: Double?
        let nonInteractive: Bool
        let outputDir: String
    }

    private struct StreamPayload: Encodable {
        let kind: String
        let lowLatencyDetected: Bool
        let encryptionDetected: Bool
    }

    private struct PlaylistPayload: Encodable {
        let id: String
        let kind: String
        let role: String?
        let url: String
        let selected: Bool
        let excludedByChoice: Bool?
        let refreshCount: Int
        let cadenceAdherence: Double?
        let stalenessEpisodes: Int?
    }

    private struct SummaryPayload: Encodable {
        let countsBySeverity: [String: Int]
        let countsByCategory: [String: Int]
        let countsBySource: [String: Int]
    }

    private struct ArtifactIndexEntry: Encodable {
        let requestId: String
        let url: String
        let bodyPath: String
        let metaPath: String
    }

    private struct SegmentAuditPayload: Encodable {
        let segmentsChecked: Int
        let segmentsExceedingTolerance: Int
        let downloadFailures: Int
        let bytesDownloaded: Int
    }



    // MARK: - Lifecycle

    public init() {}



    // MARK: - Public

    /// Encodes the report as JSON matching `session-report.schema.json` (schemaVersion 1).
    public func buildJSON(
        session: SessionSnapshot,
        playlists: [PlaylistInfo],
        findings: [Finding],
        artifactIndex: [SessionArchive.IndexEntry]
    ) throws -> Data {
        let report = buildReport(session: session, playlists: playlists, findings: findings, artifactIndex: artifactIndex)
        return try Finding.prettyJSONEncoder.encode(report)
    }

    /// Renders a human-readable Markdown report.
    /// Renders a prettified Markdown report with aliases, legend, and severity-grouped findings.
    ///
    /// Pass an `AliasRegistry` populated at session startup so the body uses stable aliases instead
    /// of raw URLs (FR-023–026). Calling without a registry falls back to playlist IDs as labels.
    /// Renders a human-readable Markdown report with presentation IDs and archived evidence.
    ///
    /// - Parameters:
    ///   - session: The session metadata to render.
    ///   - playlists: The frozen report playlist summaries.
    ///   - findings: The findings to group by severity and category.
    ///   - aliasRegistry: The presentation ID registry populated during discovery.
    ///   - artifactIndex: The archive entries used to resolve captured bodies by URL and refresh index.
    /// - Returns: A Markdown report whose evidence paths are inline code spans.
    ///   - evidenceByFindingID: Evidence captured when each finding was emitted, used when provenance is not inferable from the finding alone.

    public func buildMarkdown(
        session: SessionSnapshot,
        playlists: [PlaylistInfo],
        findings: [Finding],
        aliasRegistry: AliasRegistry = AliasRegistry(),
        artifactIndex: [SessionArchive.IndexEntry] = [],
        evidenceByFindingID: [String: EvidenceReference] = [:],
        timeline: IncidentTimeline = IncidentTimeline(events: []),
        playlistInformation: [PlaylistInformation] = [],
        timeZone: TimeZone = .current
    ) -> String {
        var md = "# valistream — Session Report\n\n"
        if let interruption = session.interruption, interruption.contains("PARTIAL") {
            md += "> **PARTIAL REPORT** — session was stopped before completion.\n\n"
        }

        // ── Preamble: session identity table (before sections) ───────────────────────
        md += "| Field | Value |\n|-------|-------|\n"
        md += "| Session ID | `\(session.id)` |\n"
        md += "| Stream | `\(session.inputURL.absoluteString)` |\n"
        md += "| Started | `\(ReportTimestampFormatter.format(session.startedAt, timeZone: timeZone))` |\n"
        md += "| Ended | `\(ReportTimestampFormatter.format(session.endedAt, timeZone: timeZone))` |\n"
        md += "| State | `\(session.state.rawValue)` |\n"
        if let interruption = session.interruption {
            md += "| Interruption | \(interruption) |\n"
        }
        md += "| Stream kind | `\(session.streamKind?.rawValue ?? "unknown")` |\n"
        md += "| Low-Latency HLS | \(session.lowLatencyDetected ? "detected" : "not detected") |\n"
        md += "| Encryption | \(session.encryptionDetected ? "detected" : "not detected") |\n\n"

        // Encryption-info findings are diagnostic noise for a human reader — they are dropped
        // from the markdown body and Summary counts, but remain in report.json (TOOL.encryption).
        let shown = findings.filter { $0.ruleId != "TOOL.encryption" }

        // ── Summary ─────────────────────────────────────────────────────────────────
        let errors = shown.count { $0.severity == .error }
        let warnings = shown.count { $0.severity == .warning }
        let infos = shown.count { $0.severity == .info }
        let refreshes = playlists.map(\.refreshCount).max() ?? 0
        let outcomeText: String
        switch session.state {
        case .completed where errors > 0: outcomeText = "Completed with errors"
        case .completed where warnings > 0: outcomeText = "Completed with warnings"
        case .completed: outcomeText = "Completed successfully"
        case .aborted: outcomeText = "Session interrupted"
        case .failed: outcomeText = "Session failed"
        default: outcomeText = session.state.rawValue.capitalized
        }
        md += "## Summary\n\n"
        md += "**\(outcomeText).** \(errors) error\(errors == 1 ? "" : "s"), "
            + "\(warnings) warning\(warnings == 1 ? "" : "s"), "
            + "\(infos) informational finding\(infos == 1 ? "" : "s").\n\n"
        md += "- Playlists: \(playlists.count)\n"
        md += "- Refreshes: \(refreshes)\n\n"

        // ── Incident Timeline ────────────────────────────────────────────────────────
        let findingsByID = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { existing, _ in existing })
        md += "## Incident Timeline\n\n"
        if timeline.entries.isEmpty {
            md += "_No incidents recorded._\n\n"
        } else {
            for entry in timeline.entries {
                let prefix: String
                switch entry.kind {
                case .lifecycle: prefix = "📋"
                case .finding(.error): prefix = "🔴"
                case .finding(.warning): prefix = "🟡"
                case .finding: prefix = "🔵"
                case .operationalFailure: prefix = "🔴"
                }
                if let anchor = entry.findingAnchor {
                    let findingID = anchor.hasPrefix("finding-")
                        ? String(anchor.dropFirst("finding-".count))
                        : anchor
                    let who = findingsByID[findingID].flatMap { aliasRegistry.alias(for: $0.resource)?.alias }
                        ?? entry.summary
                    md += "- \(prefix) \(who) — [Finding \(findingID)](#\(anchor))\n"
                } else {
                    md += "- \(prefix) \(entry.summary)\n"
                }
            }
            md += "\n"
        }

        // ── Per-playlist blocks ─────────────────────────────────────────────────────
        let resolver = EvidenceResolver()
        let infoByID = Dictionary(playlistInformation.map { ($0.playlistID, $0) }, uniquingKeysWith: { existing, _ in existing })
        let findingsByURL = Dictionary(grouping: shown, by: \.resource)
        let ordered = playlists.enumerated().sorted {
            (roleRank(for: $0.element), $0.offset) < (roleRank(for: $1.element), $1.offset)
        }.map(\.element)
        for playlist in ordered {
            let blockFindings = (findingsByURL[playlist.url] ?? []).sorted { $0.id < $1.id }
            md += playlistBlock(
                for: playlist,
                information: infoByID[playlist.id],
                findings: blockFindings,
                aliasRegistry: aliasRegistry,
                evidenceByFindingID: evidenceByFindingID,
                artifactIndex: artifactIndex,
                resolver: resolver,
                timeZone: timeZone
            )
        }

        // Findings can reference a resource that never finished loading (e.g. HTTP 404 on the very
        // first fetch), so it never enters `playlists` and gets no per-playlist block. Surface them
        // in a dedicated section so no shown finding silently vanishes from report.md.
        let trackedURLs = Set(playlists.map(\.url))
        let orphanedFindings = shown
            .filter { trackedURLs.contains($0.resource) == false }
            .sorted { $0.id < $1.id }
        if orphanedFindings.isEmpty == false {
            md += "## ⚠️ Unresolved Findings\n\n"
            md += "_Findings against resources that never loaded._\n\n"
            for finding in orphanedFindings {
                let fallbackID = aliasRegistry.alias(for: finding.resource)?.alias ?? "unreachable"
                md += findingSubsection(
                    finding,
                    fallbackID: fallbackID,
                    aliasRegistry: aliasRegistry,
                    evidenceByFindingID: evidenceByFindingID,
                    artifactIndex: artifactIndex,
                    resolver: resolver,
                    timeZone: timeZone
                )
            }
        }

        // ── Legend ────────────────────────────────────────────────────────────────────
        md += "## Legend\n\n"
        if aliasRegistry.all.isEmpty {
            md += "_No aliases registered._\n\n"
        } else {
            md += "| ID | URL | Role | Attributes |\n|----|-----|------|------------|\n"
            for entry in aliasRegistry.all {
                let attrs = entry.attributes.isEmpty
                    ? "—"
                    : entry.attributes.keys.sorted().map { "\($0)=\(entry.attributes[$0]!)" }.joined(separator: ", ")
                md += "| `\(entry.alias)` | `\(entry.url.absoluteString)` | \(entry.role.rawValue) | \(attrs) |\n"
            }
            md += "\n"
        }

        return md
    }



    // MARK: - Private

    private func markdownEvidence(_ reference: EvidenceReference) -> String {
        switch reference {
        case .single(let path):
            return "`\(path)`"
        case .pair(let older, let newer):
            var parts = [older, newer].compactMap { $0 }.map { "`\($0)`" }
            if older == nil {
                parts.append("older snapshot unavailable")
            }
            if newer == nil {
                parts.append("newer snapshot unavailable")
            }

            return parts.joined(separator: ", ")
        case .unavailable(let id):
            return "no body captured for \(id)"
        }
    }

    /// Per-playlist health verdict derived from that playlist's own (non-encryption) findings.
    private enum Verdict {
        case healthy
        case needsAttention
        case problems

        var glyph: String {
            switch self {
            case .healthy: "✅"
            case .needsAttention: "⚠️"
            case .problems: "🔴"
            }
        }

        var word: String {
            switch self {
            case .healthy: "Healthy"
            case .needsAttention: "Needs attention"
            case .problems: "Problems"
            }
        }
    }

    /// Sort key for playlist ordering: master first, then variant, audio, subtitles, iframe.
    private func roleRank(for playlist: PlaylistInfo) -> Int {
        guard playlist.kind != .master else { return 0 }
        switch playlist.role {
        case .variant: return 1
        case .audio: return 2
        case .subtitles: return 3
        case .iframe: return 4
        case nil: return 5
        }
    }

    /// Renders one self-contained "## <glyph> <id>" block for a playlist: heading, italic
    /// subtitle, flat property bullets, an optional Timing subsection, and a per-playlist
    /// Findings subsection when that playlist has at least one (non-encryption) finding.
    private func playlistBlock(
        for playlist: PlaylistInfo,
        information: PlaylistInformation?,
        findings: [Finding],
        aliasRegistry: AliasRegistry,
        evidenceByFindingID: [String: EvidenceReference],
        artifactIndex: [SessionArchive.IndexEntry],
        resolver: EvidenceResolver,
        timeZone: TimeZone
    ) -> String {
        let isMaster = playlist.kind == .master
        let displayID = aliasRegistry.alias(for: playlist.url)?.alias ?? playlist.id
        let errors = findings.count { $0.severity == .error }
        let warnings = findings.count { $0.severity == .warning }
        let verdict: Verdict
        if errors > 0 {
            verdict = .problems
        } else if warnings > 0 {
            verdict = .needsAttention
        } else {
            verdict = .healthy
        }

        var md = "## \(verdict.glyph) \(displayID)" + (isMaster ? " · Master manifest" : "") + "\n"

        var subtitleParts = [verdict.word]
        if isMaster {
            subtitleParts.append("\(information?.master?.variantCount ?? 0) variants")
        } else if let playlistType = information?.media?.playlistType {
            subtitleParts.append(playlistType)
        }
        subtitleParts.append("\(playlist.refreshCount) refresh\(playlist.refreshCount == 1 ? "" : "es")")
        if warnings > 0 {
            subtitleParts.append("\(warnings) warning\(warnings == 1 ? "" : "s")")
        }
        if errors > 0 {
            subtitleParts.append("\(errors) error\(errors == 1 ? "" : "s")")
        }
        if playlist.selected == false {
            subtitleParts.append(playlist.excludedByChoice ? "excluded" : "not selected")
        }
        md += "*\(subtitleParts.joined(separator: " · "))*\n"

        for field in PlaylistInfoFormatter.reportHeaderFields(for: information) {
            md += "- \(field.label): \(field.value)\n"
        }

        if let timingFields = PlaylistInfoFormatter.reportTimingFields(for: information) {
            md += "### Timing\n"
            for field in timingFields {
                md += "- \(field.label): \(field.value)\n"
            }
        }

        if findings.isEmpty == false {
            md += "### Findings\n\n"
            for finding in findings {
                md += findingSubsection(
                    finding,
                    fallbackID: displayID,
                    aliasRegistry: aliasRegistry,
                    evidenceByFindingID: evidenceByFindingID,
                    artifactIndex: artifactIndex,
                    resolver: resolver,
                    timeZone: timeZone
                )
            }
        }

        md += "\n"
        return md
    }

    /// Renders one `#### <glyph> Finding <id>` subsection. Shared by per-playlist `### Findings`
    /// blocks and the `## Unresolved Findings` catch-all so the header slug stays `finding-<id>`
    /// and Incident Timeline links resolve regardless of where the finding is homed.
    private func findingSubsection(
        _ finding: Finding,
        fallbackID: String,
        aliasRegistry: AliasRegistry,
        evidenceByFindingID: [String: EvidenceReference],
        artifactIndex: [SessionArchive.IndexEntry],
        resolver: EvidenceResolver,
        timeZone: TimeZone
    ) -> String {
        let sevGlyph: String
        switch finding.severity {
        case .error: sevGlyph = "🔴"
        case .warning: sevGlyph = "🟡"
        case .info: sevGlyph = "🔵"
        }
        let specRef = finding.specRef.map { " (\($0))" } ?? ""
        var md = "#### \(sevGlyph) Finding \(finding.id)\n\n"
        md += "- Severity: \(finding.severity.rawValue.capitalized)\n"
        md += "- Rule: `\(finding.ruleId)`\(specRef)\n"
        md += "- Message: \(finding.message)\n"
        md += "- Observed: \(ReportTimestampFormatter.format(finding.observedAt, timeZone: timeZone))\n"
        let reference = evidenceByFindingID[finding.id] ?? resolver.resolve(
            finding,
            aliases: aliasRegistry,
            artifactIndex: artifactIndex,
            fallbackID: fallbackID
        )
        md += "- Evidence: \(markdownEvidence(reference))\n\n"
        return md
    }

    private func buildReport(
        session: SessionSnapshot,
        playlists: [PlaylistInfo],
        findings: [Finding],
        artifactIndex: [SessionArchive.IndexEntry]
    ) -> Report {
        let configPayload = ConfigPayload(
            segmentMode: session.config.segmentMode,
            bandwidthTolerance: session.config.bandwidthTolerance,
            timeLimitSeconds: session.config.timeLimit.map { $0.seconds },
            nonInteractive: session.config.nonInteractive,
            outputDir: (session.config.outputDir ?? OutputLocation.defaultBase()).path(percentEncoded: false)
        )

        let sessionPayload = SessionPayload(
            id: session.id,
            inputUrl: session.inputURL.absoluteString,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            state: session.state.rawValue,
            interruption: session.interruption,
            config: configPayload
        )

        let streamPayload = StreamPayload(
            kind: session.streamKind?.rawValue ?? "vod",
            lowLatencyDetected: session.lowLatencyDetected,
            encryptionDetected: session.encryptionDetected
        )

        let playlistPayloads = playlists.map { info in
            PlaylistPayload(
                id: info.id,
                kind: info.kind.rawValue,
                role: info.role?.rawValue,
                url: info.url.absoluteString,
                selected: info.selected,
                excludedByChoice: info.excludedByChoice ? true : nil,
                refreshCount: info.refreshCount,
                cadenceAdherence: info.cadenceAdherence,
                stalenessEpisodes: info.stalenessEpisodes > 0 ? info.stalenessEpisodes : nil
            )
        }

        let countsBySeverity = Dictionary(grouping: findings, by: { $0.severity.rawValue })
            .mapValues { $0.count }
        let countsByCategory = Dictionary(grouping: findings, by: { $0.category.rawValue })
            .mapValues { $0.count }
        let countsBySource = Dictionary(grouping: findings, by: { $0.source.rawValue })
            .mapValues { $0.count }

        let artifactPayloads = artifactIndex.map { entry in
            ArtifactIndexEntry(
                requestId: entry.requestId,
                url: entry.url.absoluteString,
                bodyPath: entry.bodyPath,
                metaPath: entry.metaPath
            )
        }

        return Report(
            schemaVersion: 1,
            session: sessionPayload,
            stream: streamPayload,
            playlists: playlistPayloads,
            findings: findings,
            segmentAudit: nil,
            summary: SummaryPayload(
                countsBySeverity: countsBySeverity,
                countsByCategory: countsByCategory,
                countsBySource: countsBySource
            ),
            artifactIndex: artifactPayloads
        )
    }
}

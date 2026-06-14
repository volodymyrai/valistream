//
//  ValidationSession+Reporting.swift
//  ValistreamCore
//

import Foundation

extension ValidationSession {

    // MARK: - Archive

    func archiveFetch(_ result: FetchResult, playlistID: String) async {
        guard let archive, archiveStopped == false else { return }
        if let watcher = diskWatcher {
            switch try? watcher.check() {
            case .critical(let bytes):
                if archiveStopped == false {
                    archiveStopped = true
                    record(RuleViolation(
                        ruleId: "TOOL.delivery",
                        source: .tool,
                        severity: .error,
                        category: .delivery,
                        message: "Archive stopped: only \(bytes / 1_048_576) MB available on session volume.",
                        context: ["availableBytes": .int(bytes)]
                    ), resource: inputURL)
                }
                return
            case .low(let bytes):
                record(RuleViolation(
                    ruleId: "TOOL.delivery",
                    source: .tool,
                    severity: .warning,
                    category: .delivery,
                    message: "Low disk space: \(bytes / 1_073_741_824) GB available on session volume.",
                    context: ["availableBytes": .int(bytes)]
                ), resource: inputURL)
            default:
                break
            }
        }
        guard result.outcome == .success, result.body.isEmpty == false else { return }
        let presentationID: String
        if let registered = aliasRegistry.alias(for: result.url)?.alias {
            presentationID = registered
        }
        else if playlistID == "master" {
            let isMaster = result.bodyText?.contains("#EXT-X-STREAM-INF") == true
                || result.bodyText?.contains("#EXT-X-MEDIA:") == true
            let role: AliasRole = isMaster ? .master : .video
            presentationID = aliasRegistry.alias(for: result.url, role: role).alias
        }
        else {
            presentationID = playlistID
        }
        guard let record = try? await archive.store(result: result, playlistID: presentationID) else { return }
        let snapshot = URL(filePath: record.bodyPath).deletingPathExtension().lastPathComponent
        let metaPath = "playlists/\(presentationID)/\(snapshot).meta.json"
        evidenceEntries.append(SessionArchive.IndexEntry(
            requestId: record.requestId,
            url: result.url,
            bodyPath: record.bodyPath,
            metaPath: metaPath
        ))
    }

    // MARK: - Report writing

    /// Builds and atomically writes both `report.json` and `report.md` to the session folder.
    ///
    /// Called at the end of each monitor refresh cycle (FR-021) and at session completion/stop.
    /// Uses `SessionArchive.writeAtomically` so concurrent readers always see a complete document.
    /// Builds and atomically writes both `report.json` and `report.md` to the session folder.
    ///
    /// Called at the end of each monitor refresh cycle (FR-021) and at session completion/stop.
    /// Uses `SessionArchive.writeAtomically` so concurrent readers always see a complete document.
    func writeReport(interruption: String?) async {
        guard let archive else { return }
        let artifactIndex = await archive.artifactIndex
        let folder = archive.sessionFolder
        let snapshot = SessionReportBuilder.SessionSnapshot(
            id: id,
            inputURL: inputURL,
            startedAt: startedAt ?? now(),
            endedAt: now(),
            state: state,
            config: config,
            streamKind: classification,
            lowLatencyDetected: recordedFindings.contains { $0.ruleId == "TOOL.low-latency" },
            encryptionDetected: recordedFindings.contains { $0.ruleId == "TOOL.encryption" },
            interruption: interruption
        )
        let playlistInfos = playlistTracks.map { id, track in
            let stalenessEpisodes = recordedFindings.count {
                $0.ruleId == "TOOL.staleness" && $0.severity == .error && $0.resource == track.url
            }
            return SessionReportBuilder.PlaylistInfo(
                id: id,
                kind: track.kind,
                role: track.role,
                url: track.url,
                selected: track.selected,
                excludedByChoice: !track.selected,
                refreshCount: track.refreshCount,
                stalenessEpisodes: stalenessEpisodes
            )
        }
        let builder = SessionReportBuilder()
        if let jsonData = try? builder.buildJSON(
            session: snapshot,
            playlists: playlistInfos,
            findings: recordedFindings,
            artifactIndex: artifactIndex
        ) {
            try? archive.writeAtomically(jsonData, to: folder.appending(path: "report.json"))
        }
        if let mdData = builder.buildMarkdown(
            session: snapshot,
            playlists: playlistInfos,
            findings: recordedFindings,
            aliasRegistry: aliasRegistry,
            artifactIndex: artifactIndex
        ).data(using: .utf8) {
            try? archive.writeAtomically(mdData, to: folder.appending(path: "report.md"))
        }
    }
}

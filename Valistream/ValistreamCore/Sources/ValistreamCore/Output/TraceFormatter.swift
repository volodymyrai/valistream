//
//  TraceFormatter.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

/// Renders each `TraceEvent` to a category-prefixed, ID-based line per the Output message catalog.
///
/// All output is ID-based — no raw URLs are ever emitted (SC-003).
/// Consumers gate emission by verbosity (`--verbose` only, per the catalog).
///
/// Example output:
/// ```
/// Fetch: requesting 1080p_avc1_5
/// Fetch: 1080p_avc1_5 HTTP 200; 42ms; 1.3 kB
/// Validation: 1080p_avc1_5 — OK
/// Stored: 1080p_avc1_5 → playlists/1080p_avc1/1080p_avc1_5.m3u8
/// Refresh: 1080p_avc1 next in 6.0s
/// Compare: 1080p_avc1_4 ↔ 1080p_avc1_5
/// Lifecycle: 1080p_avc1 added
/// ```
public enum TraceFormatter {

    // MARK: - Public

    /// Formats a `TraceEvent` to a single, category-prefixed, ID-based line.
    public static func format(_ event: TraceEvent) -> String {
        switch event {
        case .fetchStarted(let url, let playlistID, let refreshIndex):
            return "Fetch started: \(playlistID) #\(refreshIndex) (\(url.absoluteString))"

        case .fetchIntent(let snapshotID):
            return "Fetch: requesting \(snapshotID)"

        case .fetchResult(let snapshotID, let httpStatus, let durationMs, let bytes):
            let kb = Double(bytes) / 1_000.0
            return "Fetch: \(snapshotID) HTTP \(httpStatus); \(durationMs)ms; \(formatted(kb: kb))"

        case .validationPlaylistOK(let snapshotID):
            return "Validation: \(snapshotID) — OK"

        case .validationPlaylistFail(let snapshotID, let errorCount, let warnCount):
            var parts: [String] = []
            if errorCount > 0 { parts.append("\(errorCount) ERROR") }
            if warnCount > 0 { parts.append("\(warnCount) WARN") }
            let summary = parts.isEmpty ? "findings" : parts.joined(separator: ", ")
            return "Validation: \(snapshotID) — \(summary)"

        case .validationRuleOK(let snapshotID, let ruleID):
            return "Validation: \(snapshotID) [\(ruleID)] — OK"

        case .validationRuleFail(let snapshotID, let ruleID):
            return "Validation: \(snapshotID) [\(ruleID)] — finding"

        case .stored(let snapshotID, let archivePath):
            return "Stored: \(snapshotID) → \(archivePath)"

        case .refreshScheduled(let playlistID, let delaySeconds):
            return "Refresh: \(playlistID) next in \(formatted(seconds: delaySeconds))"

        case .refreshDrift(let playlistID, let driftSeconds):
            return "Refresh: \(playlistID) cadence drift \(formatted(seconds: driftSeconds))"

        case .continuityCompare(let olderSnapshotID, let newerSnapshotID):
            return "Compare: \(olderSnapshotID) ↔ \(newerSnapshotID)"

        case .renditionAdded(let playlistID):
            return "Lifecycle: \(playlistID) added"

        case .renditionDropped(let playlistID):
            return "Lifecycle: \(playlistID) dropped"
        }
    }



    // MARK: - Private

    private static func formatted(kb: Double) -> String {
        if kb >= 1_000 {
            return "\(String(format: "%.1f", kb / 1_000)) MB"
        }
        return "\(String(format: "%.1f", kb)) kB"
    }

    private static func formatted(seconds: Double) -> String {
        if seconds == seconds.rounded() {
            return "\(Int(seconds))s"
        }
        return "\(String(format: "%.1f", seconds))s"
    }
}

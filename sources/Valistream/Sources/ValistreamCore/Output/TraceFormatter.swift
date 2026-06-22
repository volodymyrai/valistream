//
//  TraceFormatter.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

/// Renders each `TraceEvent` as a phrase for a context-led terminal trace line.
///
/// Example output: `fetched HTTP 200; 42ms; 1.3 kB`.
public enum TraceFormatter {

    // MARK: - Public

    /// Formats a `TraceEvent` to a single phrase for terminal presentation.
    public static func format(_ event: TraceEvent) -> String {
        switch event {
        case .fetchStarted(let url, _, _):
            return "started (\(url.absoluteString))"

        case .fetchIntent:
            return "requesting"

        case .fetchResult(_, let httpStatus, let durationMs, let bytes):
            let kb = Double(bytes) / 1_000.0
            return "fetched HTTP \(httpStatus); \(durationMs)ms; \(formatted(kb: kb))"

        case .validationPlaylistOK:
            return "validated OK"

        case .validationPlaylistFail(_, let errorCount, let warnCount):
            var parts: [String] = []
            if errorCount > 0 { parts.append("\(errorCount) ERROR") }
            if warnCount > 0 { parts.append("\(warnCount) WARN") }
            let summary = parts.isEmpty ? "findings" : parts.joined(separator: ", ")
            return "validated \(summary)"

        case .validationRuleOK(_, let ruleID):
            return "rule [\(ruleID)] OK"

        case .validationRuleFail(_, let ruleID):
            return "rule [\(ruleID)] finding"

        case .stored(_, let archivePath):
            return "stored \(archivePath)"

        case .refreshScheduled(_, let delaySeconds):
            return "next refresh in \(formatted(seconds: delaySeconds))"

        case .refreshRetry(_, let delaySeconds):
            return "re-try scheduled in \(formatted(seconds: delaySeconds))"

        case .refreshDrift(_, let driftSeconds):
            return "cadence drift \(formatted(seconds: driftSeconds))"

        case .continuityCompare(let olderSnapshotID, _):
            return "compared ↔ \(olderSnapshotID)"

        case .renditionAdded:
            return "added"

        case .renditionDropped:
            return "dropped"
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

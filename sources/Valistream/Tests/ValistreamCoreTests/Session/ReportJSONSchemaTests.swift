//
//  ReportJSONSchemaTests.swift
//  ValistreamCoreTests
//

import Testing
@testable import ValistreamCore
import Foundation

/// Regression guard: buildJSON output must remain schema-identical to the feature-001 frozen
/// schema (FR-003, SC-010). No fields added, removed, or renamed.
@Suite(.tags(.session))
struct ReportJSONSchemaTests {
    private let start    = Date(timeIntervalSince1970: 1_700_000_000)
    private let end      = Date(timeIntervalSince1970: 1_700_003_600)
    private let inputURL = URL(string: "https://ex.com/master.m3u8")!

    private func makeSnapshot() -> SessionReportBuilder.SessionSnapshot {
        // Use non-nil optional fields so they appear in JSON output (nil fields are omitted).
        SessionReportBuilder.SessionSnapshot(
            id: "schema-test-session",
            inputURL: inputURL,
            startedAt: start,
            endedAt: end,
            state: .aborted,
            config: SessionConfig(timeLimit: .seconds(3600), archiveEnabled: true),
            streamKind: .live,
            lowLatencyDetected: false,
            encryptionDetected: false,
            interruption: "graceful stop"
        )
    }

    private func buildJSON(findings: [Finding] = [], artifactIndex: [SessionArchive.IndexEntry] = []) throws -> [String: Any] {
        let data = try SessionReportBuilder().buildJSON(
            session: makeSnapshot(),
            playlists: [],
            findings: findings,
            artifactIndex: artifactIndex
        )
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Top-level schema fields

    @Test("top-level fields match frozen schema exactly")
    func topLevelFields() throws {
        let obj = try buildJSON()
        // segmentAudit is nil in these tests → omitted by encoder (nil-omission is correct behavior).
        let expectedKeys: Set<String> = ["schemaVersion", "session", "stream", "playlists",
                                         "findings", "summary", "artifactIndex"]
        let actualKeys = Set(obj.keys)
        #expect(actualKeys == expectedKeys,
                "Top-level keys changed: got \(actualKeys), want \(expectedKeys)")
    }

    @Test("schemaVersion is 1 (frozen)")
    func schemaVersionFrozen() throws {
        #expect(try buildJSON()["schemaVersion"] as? Int == 1)
    }

    // MARK: - Session object fields

    @Test("session object has exactly the frozen fields")
    func sessionObjectFields() throws {
        let session = try #require(try buildJSON()["session"] as? [String: Any])
        let expected: Set<String> = ["id", "inputUrl", "startedAt", "endedAt", "state",
                                     "interruption", "config"]
        #expect(Set(session.keys) == expected)
    }

    @Test("session.config has exactly the frozen fields")
    func sessionConfigFields() throws {
        let session  = try #require(try buildJSON()["session"] as? [String: Any])
        let config   = try #require(session["config"] as? [String: Any])
        let expected: Set<String> = ["segmentMode", "bandwidthTolerance", "timeLimitSeconds",
                                     "nonInteractive", "outputDir"]
        #expect(Set(config.keys) == expected)
    }

    // MARK: - Stream object fields

    @Test("stream object has exactly the frozen fields")
    func streamObjectFields() throws {
        let stream   = try #require(try buildJSON()["stream"] as? [String: Any])
        let expected: Set<String> = ["kind", "lowLatencyDetected", "encryptionDetected"]
        #expect(Set(stream.keys) == expected)
    }

    // MARK: - Summary object fields

    @Test("summary object has exactly the frozen fields")
    func summaryObjectFields() throws {
        let summary  = try #require(try buildJSON()["summary"] as? [String: Any])
        let expected: Set<String> = ["countsBySeverity", "countsByCategory", "countsBySource"]
        #expect(Set(summary.keys) == expected)
    }

    // MARK: - Findings array

    @Test("findings array entries have the frozen per-finding fields")
    func findingFields() throws {
        let finding = Finding(
            id: "f1", ruleId: "RFC8216.4.3.4.2-BANDWIDTH", source: .rfc8216,
            severity: .error, category: .masterPlaylist, resource: inputURL,
            location: nil, refreshIndex: nil, observedAt: start,
            message: "Missing BANDWIDTH", context: [:]
        )
        let bareFinding = Finding(
            id: "f2", ruleId: "TOOL.delivery", source: .tool,
            severity: .warning, category: .delivery, resource: inputURL,
            location: nil, refreshIndex: nil, observedAt: start,
            message: "Slow delivery", context: [:]
        )
        let obj    = try buildJSON(findings: [finding, bareFinding])
        let arr    = try #require(obj["findings"] as? [[String: Any]])
        #expect(arr.count == 2)
        let f = arr[0]
        // Core fields that must exist
        #expect(f["id"]       != nil)
        #expect(f["ruleId"]   != nil)
        #expect(f["specRef"]  as? String == "RFC 8216 §4.3.4.2")
        #expect(f["severity"] != nil)
        #expect(f["category"] != nil)
        #expect(f["resource"] != nil)
        #expect(f["message"]  != nil)
        // Aliases must NOT appear in JSON (schema frozen, SC-010)
        #expect(f["alias"]    == nil)
        let bare = arr[1]
        #expect(bare["specRef"] == nil)
    }

    // MARK: - No aliases in JSON (SC-010)

    @Test("aliases do not appear anywhere in the JSON output (SC-010)")
    func noAliasesInJSON() throws {
        let data = try SessionReportBuilder().buildJSON(
            session: makeSnapshot(), playlists: [], findings: [], artifactIndex: []
        )
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        #expect(!jsonString.contains("\"alias\""),
                "Found unexpected 'alias' key in JSON — schema must remain frozen")
        #expect(!jsonString.contains("\"aliasRegistry\""),
                "Found unexpected 'aliasRegistry' key in JSON")
    }
}

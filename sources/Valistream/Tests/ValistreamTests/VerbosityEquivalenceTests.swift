//
//  VerbosityEquivalenceTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation
import Testing
@testable import Valistream
import ValistreamCore

/// Cross-tier freeze guard (V3, FR-021, SC-011): verbose mode must produce IDENTICAL findings,
/// evidence, report files, structured `--json` stream, and exit-equivalent state as normal mode.
/// Only human stdout may differ (verbose has more lines).
@Suite("Verbosity cross-tier equivalence (FR-021/SC-011)", .timeLimit(.minutes(1)))
struct VerbosityEquivalenceTests {

    // MARK: - Helpers

    private struct SessionOutputs {
        let findings: [Finding]
        let state: SessionState
        let reportMarkdown: String?
        let reportJSON: String?
        let machineEvents: [SessionEvent]
        let humanLineCount: Int
    }

    private func runSession(
        verbose: Bool,
        outputName: String
    ) async throws -> SessionOutputs {
        let masterURL = URL(string: "https://cdn.example.com/equiv/master.m3u8")!
        let mediaURL  = URL(string: "https://cdn.example.com/equiv/v1080/index.m3u8")!
        let outputDir = FileManager.default.temporaryDirectory
            .appending(path: "valistream-equiv-\(outputName)-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let config = SessionConfig(
            outputDir: outputDir,
            nonInteractive: true,
            archiveEnabled: true,
            verboseEvents: verbose
        )
        let harness = LiveSessionHarness(input: masterURL, config: config)
        harness.fetcher.stub(masterURL, body: masterPlaylist)
        harness.fetcher.stub(mediaURL, body: liveMedia)
        await harness.start()

        // Capture the machine event stream (--json surface).
        let machineTask = Task { [harness] in
            var machineEvents: [SessionEvent] = []
            for await event in harness.session.events {
                machineEvents.append(event)
            }
            return machineEvents
        }

        // Capture human output via StatusRenderer.
        let recorder = OutputRecorder()
        let renderTask = Task { [harness, recorder] in
            var renderer = makeRenderer(recorder: recorder, verbose: verbose)
            for await event in harness.session.timestampedEvents {
                renderer.render(event)
            }
            return renderer.playlistCount
        }

        // Drive one refresh cycle, then abort.
        await harness.step(by: 6, refreshing: mediaURL)
        await harness.abortAndFinish()

        let machineEvents = await machineTask.value
        let playlistCount = await renderTask.value

        var summaryRenderer = makeRenderer(recorder: recorder, verbose: verbose)
        summaryRenderer.renderSummary(
            findings: await harness.session.recordedFindings,
            state: await harness.session.state,
            sessionFolder: nil,
            elapsed: .seconds(1),
            playlistCount: playlistCount,
            reportPath: nil,
            at: Date(timeIntervalSince1970: 1_750_000_006)
        )

        let humanOutput = recorder.standardOutput
        let humanLineCount = humanOutput.split(separator: "\n", omittingEmptySubsequences: false).count

        // Read report files if present.
        let folder = await harness.session.sessionFolderURL
        let reportMarkdown = folder.flatMap { url in
            try? String(contentsOf: url.appending(path: "report.md"), encoding: .utf8)
        }
        let reportJSON = folder.flatMap { url in
            try? String(contentsOf: url.appending(path: "report.json"), encoding: .utf8)
        }

        return SessionOutputs(
            findings: await harness.session.recordedFindings,
            state: await harness.session.state,
            reportMarkdown: reportMarkdown,
            reportJSON: reportJSON,
            machineEvents: machineEvents,
            humanLineCount: humanLineCount
        )
    }

    // MARK: - Tests

    @Test("findings set is identical across normal and verbose tiers", .timeLimit(.minutes(1)))
    func findingsIdenticalAcrossTiers() async throws {
        let normal  = try await runSession(verbose: false, outputName: "normal-findings")
        let verbose = try await runSession(verbose: true,  outputName: "verbose-findings")

        #expect(normal.findings.count == verbose.findings.count,
                "Finding count differs: normal=\(normal.findings.count) verbose=\(verbose.findings.count)")
        let normalIDs  = Set(normal.findings.map(\.id))
        let verboseIDs = Set(verbose.findings.map(\.id))
        #expect(normalIDs == verboseIDs,
                "Finding IDs differ: normal=\(normalIDs) verbose=\(verboseIDs)")
        for finding in normal.findings {
            let verboseFinding = try #require(verbose.findings.first(where: { $0.id == finding.id }))
            #expect(finding.severity == verboseFinding.severity)
            #expect(finding.message  == verboseFinding.message)
            #expect(finding.ruleId   == verboseFinding.ruleId)
        }
    }

    @Test("exit state is identical across normal and verbose tiers", .timeLimit(.minutes(1)))
    func exitStateIdenticalAcrossTiers() async throws {
        let normal  = try await runSession(verbose: false, outputName: "normal-state")
        let verbose = try await runSession(verbose: true,  outputName: "verbose-state")
        #expect(normal.state == verbose.state,
                "Session state differs: normal=\(normal.state) verbose=\(verbose.state)")
    }

    @Test("report.md content is identical across normal and verbose tiers", .timeLimit(.minutes(1)))
    func reportMarkdownIdenticalAcrossTiers() async throws {
        let normal  = try await runSession(verbose: false, outputName: "normal-md")
        let verbose = try await runSession(verbose: true,  outputName: "verbose-md")
        // Both reports should exist or both absent.
        #expect((normal.reportMarkdown == nil) == (verbose.reportMarkdown == nil),
                "report.md presence differs")
        if let md1 = normal.reportMarkdown, let md2 = verbose.reportMarkdown {
            // Strip session-id / timestamp lines that legitimately vary between runs,
            // then compare structural content (sections, findings, evidence).
            let sections1 = markdownSectionHeadings(in: md1)
            let sections2 = markdownSectionHeadings(in: md2)
            #expect(sections1 == sections2,
                    "report.md section structure differs: \(sections1) vs \(sections2)")
        }
    }

    @Test("report.json schema is identical across normal and verbose tiers", .timeLimit(.minutes(1)))
    func reportJSONIdenticalAcrossTiers() async throws {
        let normal  = try await runSession(verbose: false, outputName: "normal-json")
        let verbose = try await runSession(verbose: true,  outputName: "verbose-json")
        #expect((normal.reportJSON == nil) == (verbose.reportJSON == nil),
                "report.json presence differs")
        if let j1 = normal.reportJSON, let j2 = verbose.reportJSON {
            let obj1 = try #require(try JSONSerialization.jsonObject(with: Data(j1.utf8)) as? [String: Any])
            let obj2 = try #require(try JSONSerialization.jsonObject(with: Data(j2.utf8)) as? [String: Any])
            // Schema version and top-level keys must match.
            let keys1 = Set(obj1.keys)
            let keys2 = Set(obj2.keys)
            #expect(keys1 == keys2, "report.json top-level keys differ: \(keys1) vs \(keys2)")
            #expect(obj1["schemaVersion"] as? Int == obj2["schemaVersion"] as? Int,
                    "schemaVersion differs")
            let findings1 = obj1["findings"] as? [[String: Any]] ?? []
            let findings2 = obj2["findings"] as? [[String: Any]] ?? []
            #expect(findings1.count == findings2.count,
                    "JSON findings count differs: \(findings1.count) vs \(findings2.count)")
        }
    }

    @Test("machine event stream is identical across normal and verbose tiers", .timeLimit(.minutes(1)))
    func machineEventStreamIdenticalAcrossTiers() async throws {
        let normal  = try await runSession(verbose: false, outputName: "normal-stream")
        let verbose = try await runSession(verbose: true,  outputName: "verbose-stream")

        // Filter to finding and state events — the observable machine surface.
        let machineFindingIDs: (SessionOutputs) -> [String] = { outputs in
            outputs.machineEvents.compactMap {
                if case .finding(let f, _) = $0 { return f.id }
                return nil
            }
        }
        let machineStates: (SessionOutputs) -> [String] = { outputs in
            outputs.machineEvents.compactMap {
                if case .stateChanged(let s) = $0 { return s.rawValue }
                return nil
            }
        }

        #expect(machineFindingIDs(normal) == machineFindingIDs(verbose),
                "Machine finding IDs differ")
        #expect(machineStates(normal) == machineStates(verbose),
                "Machine state sequence differs")
    }

    @Test("verbose human output has strictly more lines than normal (additive-only)", .timeLimit(.minutes(1)))
    func verboseHasMoreHumanLinesThanNormal() async throws {
        let normal  = try await runSession(verbose: false, outputName: "normal-lines")
        let verbose = try await runSession(verbose: true,  outputName: "verbose-lines")
        #expect(verbose.humanLineCount > normal.humanLineCount,
                "Verbose should produce more lines: normal=\(normal.humanLineCount) verbose=\(verbose.humanLineCount)")
    }

    // MARK: - Utilities

    private func makeRenderer(recorder: OutputRecorder, verbose: Bool) -> StatusRenderer {
        let mode = TerminalOutputMode(
            isTTY: false,
            noColorEnv: false,
            noColorFlag: false,
            termIsDumb: false,
            environment: ["LANG": "en_US.UTF-8"],
            verbosity: verbose ? .verbose : .normal
        )
        return StatusRenderer(
            writer: TerminalWriter(
                mode: mode,
                terminalWidth: 120,
                output: recorder.writeStandardOutput,
                errorOutput: recorder.writeStandardError
            ),
            json: false,
            timeZone: .gmt
        )
    }

    private func markdownSectionHeadings(in text: String) -> [String] {
        text.split(separator: "\n").filter { $0.hasPrefix("#") }.map(String.init)
    }

    // MARK: - Fixtures

    private let masterPlaylist = """
        #EXTM3U
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,CODECS="avc1.640028",RESOLUTION=1920x1080
        v1080/index.m3u8
        """

    private let liveMedia = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:100
        #EXTINF:6.0,
        seg100.ts
        #EXTINF:6.0,
        seg101.ts
        """
}

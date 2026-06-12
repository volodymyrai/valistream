//
//  ValistreamCommand.swift
//  Valistream
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import ArgumentParser
import Foundation
import ValistreamCore

/// The `valistream` command-line tool: validate (and, in later increments, monitor) an HLS stream.
@main
struct ValistreamCommand: AsyncParsableCommand {
    // MARK: - Configuration

    static let configuration = CommandConfiguration(
        commandName: "valistream",
        abstract: "Validate and monitor HLS streams against RFC 8216 and Apple authoring rules.",
        version: "0.1.0"
    )



    // MARK: - Arguments

    @Argument(help: "HTTP/HTTPS URL of a master playlist (or media playlist, auto-detected).")
    var url: String

    @Flag(name: .long, help: "Enable segment validation mode.")
    var segments = false

    @Option(name: .long, help: "Bandwidth deviation tolerance in percent.")
    var tolerance: Double = 10

    @Option(name: .long, help: "Live session time limit, e.g. 90s, 15m, 24h.")
    var limit: String?

    @Option(name: .long, help: "Pre-select playlists to monitor (comma-separated patterns).")
    var select: String?

    @Flag(name: .long, help: "Select all playlists, skipping the checklist prompt.")
    var all = false

    @Flag(name: .long, help: "Never prompt; implies --all unless --select is given.")
    var nonInteractive = false

    @Option(name: .long, help: "Parent directory for session folders. The archive arrives with a later increment.")
    var outputDir: String = "./valistream-sessions"

    @Flag(name: .long, help: "Machine output: findings as JSON Lines on stdout.")
    var json = false

    @Flag(name: .long, help: "Suppress live status; findings and summary only.")
    var quiet = false



    // MARK: - Run

    mutating func run() async throws {
        guard let inputURL = URL(string: url), let scheme = inputURL.scheme,
              scheme == "http" || scheme == "https" else {
            FileHandle.standardError.write(Data("valistream: invalid URL '\(url)' (expected http/https).\n".utf8))
            throw ExitCode(2)
        }

        let config = SessionConfig(
            segmentMode: segments,
            bandwidthTolerance: tolerance / 100,
            timeLimit: limit.flatMap(Self.parseDuration),
            outputDir: URL(fileURLWithPath: outputDir),
            nonInteractive: nonInteractive || !isStdoutTTY(),
            selectionPatterns: select.map { $0.split(separator: ",").map(String.init) }
        )

        let session = ValidationSession(inputURL: inputURL, config: config, fetcher: URLSessionStreamFetcher())
        let renderer = StatusRenderer(json: json, quiet: quiet)
        let events = session.events

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await event in events {
                    renderer.render(event)
                }
            }
            group.addTask {
                await session.run()
            }
        }

        let findings = await session.recordedFindings
        let state = await session.state
        renderer.renderSummary(findings: findings, state: state, sessionFolder: nil)

        if state == .failed {
            throw ExitCode(3)
        }
        if findings.contains(where: { $0.severity == .error }) {
            throw ExitCode(1)
        }
    }



    // MARK: - Private

    /// Parses a duration string such as `90s`, `15m`, or `24h`.
    private static func parseDuration(_ raw: String) -> Duration? {
        guard let unit = raw.last, let value = Double(raw.dropLast()) else { return nil }
        switch unit {
        case "s": return .seconds(value)
        case "m": return .seconds(value * 60)
        case "h": return .seconds(value * 3600)
        default: return Double(raw).map { .seconds($0) }
        }
    }

    private func isStdoutTTY() -> Bool {
        isatty(fileno(stdout)) == 1
    }
}

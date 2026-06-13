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

    @Flag(name: .long, help: "Show extended detail: raw timestamps, all HTTP headers.")
    var verbose = false

    @Flag(name: .long, help: "Disable all terminal color output (also honored via NO_COLOR env).")
    var noColor = false



    // MARK: - Run

    mutating func run() async throws {
        guard let inputURL = URL(string: url), let scheme = inputURL.scheme,
              scheme == "http" || scheme == "https" else {
            FileHandle.standardError.write(Data("valistream: invalid URL '\(url)' (expected http/https).\n".utf8))
            throw ExitCode(2)
        }

        guard !(quiet && verbose) else {
            FileHandle.standardError.write(Data("valistream: --quiet and --verbose are mutually exclusive.\n".utf8))
            throw ExitCode(2)
        }

        let tty = isStdoutTTY()
        let verbosity: Verbosity = quiet ? .quiet : (verbose ? .verbose : .normal)
        let mode = TerminalOutputMode(
            isTTY: tty,
            noColorEnv: ProcessInfo.processInfo.environment["NO_COLOR"] != nil,
            noColorFlag: noColor,
            termIsDumb: ProcessInfo.processInfo.environment["TERM"] == "dumb",
            verbosity: verbosity
        )
        let writer = TerminalWriter(mode: mode)

        let config = SessionConfig(
            segmentMode: segments,
            bandwidthTolerance: tolerance / 100,
            timeLimit: limit.flatMap(Self.parseDuration),
            outputDir: URL(fileURLWithPath: outputDir),
            nonInteractive: nonInteractive || all || !tty,
            selectionPatterns: select.map { $0.split(separator: ",").map(String.init) },
            archiveEnabled: true
        )

        // On an interactive terminal, prompt with the checklist; otherwise the session resolves the
        // selection from --select/--all (FR-018).
        let selectPlaylists: (@Sendable ([PlaylistSelection.Candidate]) async -> [PlaylistSelection.Candidate])?
        if config.nonInteractive {
            selectPlaylists = nil
        }
        else {
            selectPlaylists = { candidates in PlaylistChecklist(candidates: candidates).run() }
        }

        let session = ValidationSession(
            inputURL: inputURL,
            config: config,
            fetcher: URLSessionStreamFetcher(),
            selectPlaylists: selectPlaylists
        )
        let renderer = StatusRenderer(writer: writer, json: json)
        let events = session.events

        let runTask = Task { await session.run() }
        let signalSources = Self.installSignalHandlers(session: session, runTask: runTask)
        defer { signalSources.forEach { $0.cancel() } }

        // T017: dedicated render task — processes events concurrently with the session (FR-002).
        let renderTask = Task {
            var progressView = ProgressView(mode: mode)
            for await event in events {
                switch event {
                case .activity(let p):
                    progressView.render(p)
                default:
                    progressView.clearLine()
                    renderer.render(event)
                }
            }
            progressView.clearLine()
        }
        await runTask.value
        await renderTask.value

        let findings = await session.recordedFindings
        let state = await session.state
        let sessionFolder = await session.sessionFolderURL?.path(percentEncoded: false)
        renderer.renderSummary(findings: findings, state: state, sessionFolder: sessionFolder)

        // Graceful interrupt (SIGINT/SIGTERM) — summary still produced (FR-015).
        if state == .aborted {
            throw ExitCode(130)
        }
        if state == .failed {
            throw ExitCode(3)
        }
        if findings.contains(where: { $0.severity == .error }) {
            throw ExitCode(1)
        }
    }



    // MARK: - Private

    /// Installs SIGINT/SIGTERM handlers that gracefully abort the session and cancel its run task,
    /// so in-flight reloads stop promptly and a summary + report are still produced (FR-015,
    /// contracts/cli-interface.md exit code 130). The returned sources must be retained for the
    /// duration of the run.
    private static func installSignalHandlers(
        session: ValidationSession,
        runTask: Task<Void, Never>
    ) -> [any DispatchSourceSignal] {
        [SIGINT, SIGTERM].map { signalNumber in
            // Ignore the default disposition so the DispatchSource observes the signal instead.
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber)
            source.setEventHandler {
                Task {
                    await session.abort()
                    runTask.cancel()
                }
            }
            source.resume()
            return source
        }
    }

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

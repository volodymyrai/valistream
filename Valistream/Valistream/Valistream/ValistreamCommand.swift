//
//  ValistreamCommand.swift
//  Valistream
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import ArgumentParser
import Foundation
import os
import ValistreamCore

/// The `valistream` command-line tool: validate (and, in later increments, monitor) an HLS stream.
@main
struct ValistreamCommand: AsyncParsableCommand {
    // MARK: - Configuration

    static let configuration = CommandConfiguration(
        commandName: "valistream",
        abstract: "Validate and monitor HLS streams against RFC 8216 and Apple authoring rules.",
        discussion: """
            BREAKING CHANGES in 0.3.0 (selection flags)
            ─────────────────────────────────────────────
            --all                  → (removed; all renditions are now the default)
            --select <pattern>     → --preselect <pattern>
            --select (no value)    → --select  (now the interactive checklist)
            """,
        version: "0.3.0"
    )



    // MARK: - Entry point

    /// Custom entry point mapping ArgumentParser's usage/validation failure (`EX_USAGE` = 64 on
    /// Darwin) onto the tool's FROZEN exit code 2 for usage errors (cli-interface.md). Clean exits
    /// (`--help`/`--version`) still exit 0, and explicit `ExitCode`s thrown by `run()` (1/2/3/130)
    /// pass through unchanged.
    static func main() async {
        do {
            var command = try parseAsRoot(nil)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            }
            else {
                try command.run()
            }
        }
        catch {
            let code = Self.exitCode(for: error)
            if code == .success {
                print(Self.fullMessage(for: error))
                Foundation.exit(ExitCode.success.rawValue)
            }
            let message = Self.fullMessage(for: error)
            if message.isEmpty == false {
                FileHandle.standardError.write(Data((message + "\n").utf8))
            }
            Foundation.exit(code == .validationFailure ? 2 : code.rawValue)
        }
    }



    // MARK: - Arguments

    @Argument(help: "HTTP/HTTPS URL of a master playlist (or media playlist, auto-detected).")
    var url: String

    @Flag(name: .long, help: .hidden)
    var segments = false

    @Option(name: .long, help: .hidden)
    var tolerance: Double = 10

    @Option(name: .long, help: "Live session time limit, e.g. 90s, 15m, 24h.")
    var limit: String?

    /// Replaced by default-all behaviour — kept hidden so the parser rejects it as unknown (exit 2).
    // NOTE: --all is intentionally absent so ArgumentParser exits 2 with "unknown option".

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Pre-select a subset of renditions (comma-separated patterns matching ID, group, name, or URL).",
            discussion: "Unattended/scriptable; no prompt is shown. Formerly --select <pattern> (≤0.2.0)."
        )
    )
    var preselect: String?

    @Flag(
        name: .long,
        help: ArgumentHelp(
            "Open the interactive multi-select checklist with all renditions pre-selected.",
            discussion: "Requires a TTY; on non-TTY falls back to processing all renditions. Cannot be combined with --preselect."
        )
    )
    var select = false

    @Flag(name: .long, help: "Never prompt; process all renditions without interaction.")
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
        let preselectPatterns = preselect.map { $0.split(separator: ",").map(String.init) }

        // FR-025: --select and --preselect are mutually exclusive.
        let promptPolicy = SelectionPromptPolicy.from(
            isTTY: tty,
            selectFlag: select,
            preselectPatterns: preselectPatterns
        )
        if promptPolicy == .usageError {
            FileHandle.standardError.write(Data("valistream: --select and --preselect are mutually exclusive.\n".utf8))
            throw ExitCode(2)
        }

        // FR-025: --select on a non-TTY falls back to all renditions; print the documented notice.
        if select, !tty {
            FileHandle.standardError.write(Data(
                "valistream: --select requires a TTY; processing all renditions.\n".utf8
            ))
        }

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
            nonInteractive: nonInteractive || !tty,
            selectionPatterns: preselectPatterns,
            archiveEnabled: true,
            verboseEvents: verbose
        )

        let selectPlaylists: (@Sendable ([PlaylistSelection.Candidate]) async -> [PlaylistSelection.Candidate])? =
            promptPolicy == .prompt ? { @Sendable candidates in
                PromptberrySelection(candidates: candidates).run()
            } : nil

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

        // US2/T025: suppress terminal echo during live monitoring to prevent stray keystrokes
        // from corrupting the in-place heartbeat region (D8, FR-014, SC-004).
        let inputGuard = LiveInputGuard(isTTY: tty)
        let savedTermios = inputGuard.activate()
        defer { inputGuard.deactivate(savedTermios) }

        // T017: dedicated render task — processes events concurrently with the session (FR-002).
        let renderTask = Task {
            var progressView = ProgressView(mode: mode)
            for await event in events {
                switch event {
                case .sessionFolderResolved(let folder):
                    // FR-017: print absolute session folder path before any fetch.
                    writer.writeStatus("Output: \(folder.path(percentEncoded: false))")
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
        let endReason = await session.endReason
        let sessionFolder = await session.sessionFolderURL?.path(percentEncoded: false)
        renderer.renderSummary(findings: findings, state: state, sessionFolder: sessionFolder)

        // Graceful interrupt (SIGINT/SIGTERM) — summary still produced (FR-015).
        if endReason == .gracefulStop {
            throw ExitCode(130)
        }
        if state == .failed {
            let message = await session.failureMessage
            if let message {
                FileHandle.standardError.write(Data("valistream: \(message)\n".utf8))
                throw ExitCode(2)
            }
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
        let gracefulStopRequested = OSAllocatedUnfairLock<Bool>(initialState: false)
        let gracefulStop: @Sendable () -> Void = {
            Task { await session.abort(); runTask.cancel() }
        }

        // SIGINT: two-stage — first press requests graceful stop; second forces immediate exit.
        signal(SIGINT, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT)
        sigintSource.setEventHandler {
            let isFirst = gracefulStopRequested.withLock { v in
                guard !v else { return false }
                v = true
                return true
            }
            if isFirst {
                fputs("\nvalistream: shutting down gracefully… press Ctrl-C again to force exit.\n", stderr)
                gracefulStop()
            }
            else {
                _exit(130)
            }
        }
        sigintSource.resume()

        // SIGTERM: single-stage graceful stop (sent by process managers, not interactive users).
        signal(SIGTERM, SIG_IGN)
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM)
        sigtermSource.setEventHandler { gracefulStop() }
        sigtermSource.resume()

        return [sigintSource, sigtermSource]
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

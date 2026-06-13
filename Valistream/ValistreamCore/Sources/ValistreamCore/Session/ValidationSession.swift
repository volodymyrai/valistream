//
//  ValidationSession.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Orchestrates one run of the validator against one stream URL (data-model.md ValidationSession).
///
/// The session owns all mutable run state — lifecycle, findings, discovered playlists, per-playlist
/// monitor state — as an actor so the concurrent live-monitoring tasks can update it without data
/// races (research §9). Status and findings flow out through the ``events`` stream for the CLI to
/// render (FR-009). One-shot validation (US1) and live monitoring (US2) are both driven by ``run()``.
public actor ValidationSession {
    // MARK: - Lets & Vars

    public let id: String
    public let inputURL: URL
    public let config: SessionConfig

    /// The live event stream consumed by the presentation layer.
    public nonisolated let events: AsyncStream<SessionEvent>

    private let fetcher: any StreamFetching
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let selectPlaylists: (@Sendable ([PlaylistSelection.Candidate]) async -> [PlaylistSelection.Candidate])?
    private let continuation: AsyncStream<SessionEvent>.Continuation
    private let loader: PlaylistLoader
    private let engine: RuleEngine
    private let classifier = StreamClassifier()
    private let continuityChecker = ContinuityChecker()
    private let stalenessDetector = StalenessDetector()

    private struct PlaylistTrack {
        var kind: PlaylistKind
        var role: PlaylistRole?
        var url: URL
        var selected: Bool
        var refreshCount: Int
    }

    private var lifecycle = SessionLifecycle()
    private var findings: [Finding] = []
    private var recordedSignatures: Set<String> = []
    private var monitorStates: [String: MonitorState] = [:]
    private var streamKind: StreamKind?
    private var findingCounter = 0
    private var stopRequested = false
    private var timeLimitExpired = false
    public private(set) var endReason: SessionEndReason?
    public private(set) var failureMessage: String?
    private var archive: SessionArchive?
    private var findingsLog: FindingsLog?
    private var diskWatcher: DiskSpaceWatcher?
    private var archiveStopped = false
    private var startedAt: Date?
    private var playlistTracks: [String: PlaylistTrack] = [:]



    // MARK: - Lifecycle

    public init(
        inputURL: URL,
        config: SessionConfig,
        fetcher: any StreamFetching,
        id: String? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        selectPlaylists: (@Sendable ([PlaylistSelection.Candidate]) async -> [PlaylistSelection.Candidate])? = nil
    ) {
        self.inputURL = inputURL
        self.config = config
        self.fetcher = fetcher
        self.now = now
        self.sleep = sleep
        self.selectPlaylists = selectPlaylists
        self.id = id ?? Self.makeSessionID(now())
        self.loader = PlaylistLoader(fetcher: fetcher)
        self.engine = RuleEngine(rules: [
            RFC8216MasterRules(),
            RFC8216MediaRules(),
            AppleAuthoringRules(),
        ])
        (self.events, self.continuation) = AsyncStream.makeStream()
    }



    // MARK: - Public

    /// The current lifecycle state.
    public var state: SessionState {
        lifecycle.state
    }

    /// All findings recorded so far, in order.
    public var recordedFindings: [Finding] {
        findings
    }

    /// The stream classification once determined.
    public var classification: StreamKind? {
        streamKind
    }

    /// The latest monitor state per playlist id (FR-009).
    public var playlistMonitorStates: [String: MonitorState] {
        monitorStates
    }

    /// The session folder created by the archive, or `nil` when archiving is disabled.
    public var sessionFolderURL: URL? {
        archive?.sessionFolder
    }

    /// Requests a graceful, user-initiated stop (Ctrl-C). Monitoring unwinds and the session ends in
    /// the `aborted` state with a summary still produced (FR-015). Cancel the task running ``run()``
    /// alongside this call to interrupt in-flight sleeps promptly.
    public func abort() {
        stopRequested = true
    }

    /// Runs the session: fetch the master (or direct media) playlist, fetch every referenced media
    /// playlist, classify the stream, and evaluate all rules (US1). For live/event streams it then
    /// monitors the selected playlists on player-accurate cadence until stopped or the time limit
    public func run() async {
        startedAt = now()
        if config.archiveEnabled {
            do {
                let location = try OutputLocation.resolve(outputDir: config.outputDir, sessionID: id)
                archive = try? SessionArchive(sessionID: id, outputDir: location.baseDirectory)
                if let folder = archive?.sessionFolder {
                    findingsLog = try? FindingsLog(folder: folder)
                    diskWatcher = DiskSpaceWatcher(volumeURL: folder)
                }
                continuation.yield(.sessionFolderResolved(location.sessionFolder))
            } catch let err as OutputLocationError {
                failureMessage = err.description
                setState(.failed)
                return
            } catch {
                failureMessage = error.localizedDescription
                setState(.failed)
                return
            }
        }

        // Graceful stop requested before any fetch (spec §Edge Cases).
        if stopRequested {
            await finish(reason: .gracefulStop)
            return
        }

        setState(.fetchingMaster)
        let rootLoad = await loader.load(inputURL)
        await archiveFetch(rootLoad.result, playlistID: "master")
        for violation in rootLoad.deliveryViolations {
            record(violation, resource: inputURL)
        }
        guard let rootPlaylist = rootLoad.playlist else {
            await writeReport(interruption: nil)
            setState(.failed)
            return
        }
        trackPlaylist("master", kind: .master, role: nil, url: inputURL, selected: true, refreshCount: 1)

        setState(.validatingInitial)

        var references: [PlaylistReference] = []
        var mediaLoads: [LoadedPlaylist] = []
        if case .master(let master) = rootPlaylist {
            references = loader.mediaReferences(in: master)
            let activityLabel = "validating media playlists"
            for (index, reference) in references.enumerated() {
                // T022: check stop between playlist loads so a partial report can be written.
                if stopRequested {
                    await finish(reason: .gracefulStop)
                    return
                }
                continuation.yield(.activity(ActivityProgress(
                    activity: activityLabel,
                    completed: index,
                    total: references.count
                )))
                let load = await loader.load(reference.url, role: reference.role)
                let playlistID = "\(reference.role.rawValue)-\(index)"
                await archiveFetch(load.result, playlistID: playlistID)
                if load.playlist != nil {
                    trackPlaylist(playlistID, kind: .media, role: reference.role, url: reference.url, selected: true, refreshCount: 1)
                }
                mediaLoads.append(load)
                continuation.yield(.activity(ActivityProgress(
                    activity: activityLabel,
                    completed: index + 1,
                    total: references.count
                )))
            }
        }
        else {
            mediaLoads.append(rootLoad)
            trackPlaylist("media", kind: .media, role: .variant, url: inputURL, selected: true, refreshCount: 1)
            continuation.yield(.activity(ActivityProgress(activity: "validating media playlist", completed: 1, total: 1)))
        }

        let representativeMedia = mediaLoads.lazy.compactMap { $0.playlist?.media }.first
        let kind = representativeMedia.map { classifier.classify($0) } ?? .vod
        setClassification(kind)

        if case .master = rootPlaylist {
            evaluate(playlist: rootPlaylist, tokens: rootLoad.tokens, resource: inputURL, kind: kind)
        }

        for load in mediaLoads {
            guard let playlist = load.playlist else {
                for violation in load.deliveryViolations {
                    record(violation, resource: load.url)
                }
                continue
            }
            evaluate(playlist: playlist, tokens: load.tokens, resource: load.url, kind: kind)
            if let media = playlist.media {
                for violation in classifier.infoViolations(for: media, tokens: load.tokens) {
                    record(violation, resource: load.url)
                }
            }
        }

        // VOD never monitors — it has ended by definition (FR-005).
        guard kind != .vod else {
            await finish(reason: .completed)
            return
        }

        setState(.selectingPlaylists)
        let directMediaURL = rootPlaylist.media != nil ? inputURL : nil
        let candidates = PlaylistSelection.candidates(references: references, directMediaURL: directMediaURL)
        let selected: [PlaylistSelection.Candidate]
        if config.nonInteractive == false, let selectPlaylists {
            selected = await selectPlaylists(candidates)
        }
        else {
            selected = PlaylistSelection.resolve(candidates, patterns: config.selectionPatterns)
        }
        guard selected.isEmpty == false else {
            recordSelectionEmptyNote()
            await finish(reason: .completed)
            return
        }

        let loadedByURL = Dictionary(mediaLoads.map { ($0.url, $0) }, uniquingKeysWith: { _, last in last })

        setState(.monitoring)
        await monitor(selected: selected, loadedByURL: loadedByURL, kind: kind)

        if stopRequested {
            await finish(reason: .gracefulStop)
        }
        else if timeLimitExpired {
            await finish(reason: .timeLimit)
        }
        else {
            await finish(reason: .completed)
        }
    }



    // MARK: - Internal

    /// Transitions the lifecycle and emits a `stateChanged` event. Invalid transitions are ignored
    /// defensively so a late abort/finish cannot crash the engine.
    func setState(_ target: SessionState) {
        guard (try? lifecycle.transition(to: target)) != nil else { return }
        continuation.yield(.stateChanged(target))
        if target.isTerminal {
            continuation.finish()
        }
    }

    /// Records the stream classification and emits it.
    func setClassification(_ kind: StreamKind) {
        streamKind = kind
        continuation.yield(.streamClassified(kind))
    }

    /// Mints a ``Finding`` from a rule violation, assigning a session-unique id and timestamp,
    /// records it, and emits it on the event stream.
    @discardableResult
    func record(_ violation: RuleViolation, resource: URL, refreshIndex: Int? = nil) -> Finding {
        findingCounter += 1
        let finding = Finding(
            id: "f\(findingCounter)",
            ruleId: violation.ruleId,
            source: violation.source,
            severity: violation.severity,
            category: violation.category,
            resource: resource,
            location: violation.location,
            refreshIndex: refreshIndex,
            observedAt: now(),
            message: violation.message,
            context: violation.context
        )
        findings.append(finding)
        recordedSignatures.insert(Self.signature(violation, resource: resource))
        try? findingsLog?.append(finding)
        continuation.yield(.finding(finding))
        return finding
    }

    /// Records a violation only if an identical one has not already been recorded, so re-validating
    /// a structurally unchanged playlist on every refresh does not flood the report.
    func recordIfNew(_ violation: RuleViolation, resource: URL, refreshIndex: Int? = nil) {
        guard recordedSignatures.contains(Self.signature(violation, resource: resource)) == false else {
            return
        }
        record(violation, resource: resource, refreshIndex: refreshIndex)
    }

    /// Updates a playlist's monitor state and emits the change (de-duplicating no-op updates).
    func setMonitorState(_ playlistID: String, _ state: MonitorState) {
        guard monitorStates[playlistID] != state else { return }
        monitorStates[playlistID] = state
        continuation.yield(.monitorStateChanged(playlistID: playlistID, state: state))
    }

    /// The fetcher this session uses (for the flow tasks wired by US1+).
    var streamFetcher: any StreamFetching {
        fetcher
    }



    // MARK: - Private

    private func monitor(
        selected: [PlaylistSelection.Candidate],
        loadedByURL: [URL: LoadedPlaylist],
        kind: StreamKind
    ) async {
        let deadline = config.timeLimit.map { now().addingTimeInterval($0.seconds) }
        await withDiscardingTaskGroup { group in
            for candidate in selected {
                let initial = loadedByURL[candidate.url]
                group.addTask {
                    await self.monitorPlaylist(candidate, initial: initial, kind: kind, deadline: deadline)
                }
            }
        }
    }

    private func monitorPlaylist(
        _ candidate: PlaylistSelection.Candidate,
        initial: LoadedPlaylist?,
        kind: StreamKind,
        deadline: Date?
    ) async {
        guard var previous = initial?.playlist?.media else {
            setMonitorState(candidate.id, .stopped)
            return
        }
        setMonitorState(candidate.id, .monitoring)

        var refreshIndex = 0
        var lastChangedAt = now()
        var lastChanged = true
        var targetDuration = duration(previous.targetDuration)

        while stopRequested == false {
            if previous.hasEndList { break }
            if let deadline, now() >= deadline {
                timeLimitExpired = true
                break
            }

            let scheduler = RefreshScheduler(targetDuration: targetDuration)
            let delay = refreshIndex == 0 ? scheduler.initialDelay : scheduler.nextDelay(didChange: lastChanged)
            do {
                try await sleep(delay)
            }
            catch {
                break
            }
            if stopRequested { break }
            if let deadline, now() >= deadline {
                timeLimitExpired = true
                break
            }

            refreshIndex += 1
            let load = await loader.load(candidate.url, role: candidate.role)
            await archiveFetch(load.result, playlistID: candidate.id)
            incrementRefreshCount(candidate.id)
            for violation in load.deliveryViolations {
                record(violation, resource: candidate.url, refreshIndex: refreshIndex)
            }
            if let media = load.playlist?.media {
                evaluateStructural(load: load, kind: kind, refreshIndex: refreshIndex)
                for violation in continuityChecker.check(previous: previous, current: media) {
                    record(violation, resource: candidate.url, refreshIndex: refreshIndex)
                }
                let changed = media != previous
                if changed {
                    lastChangedAt = now()
                    targetDuration = duration(media.targetDuration)
                    setMonitorState(candidate.id, .monitoring)
                }
                else {
                    evaluateStaleness(candidate, since: lastChangedAt, target: targetDuration, refreshIndex: refreshIndex)
                }
                lastChanged = changed
                previous = media
            }
            else {
                lastChanged = false
                evaluateStaleness(candidate, since: lastChangedAt, target: targetDuration, refreshIndex: refreshIndex)
            }

            continuation.yield(.activity(ActivityProgress(
                activity: "monitoring live",
                completed: refreshIndex,
                refreshes: refreshIndex,
                aliasInScope: candidate.id
            )))
        }

        setMonitorState(candidate.id, .stopped)
    }

    private func evaluateStructural(load: LoadedPlaylist, kind: StreamKind, refreshIndex: Int) {
        guard let playlist = load.playlist else { return }
        let context = RuleContext(
            playlist: playlist,
            tokens: load.tokens,
            resource: load.url,
            streamKind: kind,
            refreshIndex: refreshIndex
        )
        for violation in engine.evaluate(context) {
            recordIfNew(violation, resource: load.url, refreshIndex: refreshIndex)
        }
        if let media = playlist.media {
            for violation in classifier.infoViolations(for: media, tokens: load.tokens) {
                recordIfNew(violation, resource: load.url, refreshIndex: refreshIndex)
            }
        }
    }

    private func evaluateStaleness(
        _ candidate: PlaylistSelection.Candidate,
        since lastChangedAt: Date,
        target: Duration,
        refreshIndex: Int
    ) {
        let staleFor = Duration.seconds(now().timeIntervalSince(lastChangedAt))
        guard let violation = stalenessDetector.violation(staleFor: staleFor, targetDuration: target) else {
            return
        }
        record(violation, resource: candidate.url, refreshIndex: refreshIndex)
        setMonitorState(candidate.id, violation.severity == .error ? .staleError : .staleWarning)
    }

    private func recordSelectionEmptyNote() {
        record(
            RuleViolation(
                ruleId: "TOOL.selection-empty",
                source: .tool,
                severity: .info,
                category: .delivery,
                message: "No playlists were selected for monitoring; the session finished after initial validation."
            ),
            resource: inputURL
        )
    }

    private func evaluate(playlist: Playlist, tokens: [M3U8Token], resource: URL, kind: StreamKind) {
        let context = RuleContext(playlist: playlist, tokens: tokens, resource: resource, streamKind: kind)
        for violation in engine.evaluate(context) {
            record(violation, resource: resource)
        }
    }

    private func finish(reason: SessionEndReason) async {
        setState(.finishing)
        let isPartial = reason == .gracefulStop && streamKind != .live && streamKind != .event
        let interruption: String? = switch reason {
        case .completed: nil
        case .gracefulStop: isPartial ? "graceful stop — PARTIAL" : "graceful stop"
        case .timeLimit: "time limit"
        }
        endReason = reason
        setState(.completed)
        await writeReport(interruption: interruption)
    }

    private func archiveFetch(_ result: FetchResult, playlistID: String) async {
        guard let archive, !archiveStopped else { return }
        if let watcher = diskWatcher {
            switch try? watcher.check() {
            case .critical(let bytes):
                if !archiveStopped {
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
            default: break
            }
        }
        _ = try? await archive.store(result: result, playlistID: playlistID)
    }

    private func writeReport(interruption: String?) async {
        guard let archive else { return }
        let artifactIndex = await archive.artifactIndex
        let folder = archive.sessionFolder
        let snapshot = SessionReportBuilder.SessionSnapshot(
            id: id,
            inputURL: inputURL,
            startedAt: startedAt ?? now(),
            endedAt: now(),
            state: lifecycle.state,
            config: config,
            streamKind: streamKind,
            lowLatencyDetected: findings.contains { $0.ruleId == "TOOL.low-latency" },
            encryptionDetected: findings.contains { $0.ruleId == "TOOL.encryption" },
            interruption: interruption
        )
        let playlistInfos = playlistTracks.map { id, track in
            let stalenessEpisodes = findings.count {
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
            findings: findings,
            artifactIndex: artifactIndex
        ) {
            try? jsonData.write(to: folder.appending(path: "report.json"))
        }
        let markdown = builder.buildMarkdown(session: snapshot, playlists: playlistInfos, findings: findings)
        try? markdown.write(to: folder.appending(path: "report.md"), atomically: true, encoding: .utf8)
    }

    private func trackPlaylist(
        _ id: String,
        kind: PlaylistKind,
        role: PlaylistRole?,
        url: URL,
        selected: Bool,
        refreshCount: Int
    ) {
        playlistTracks[id] = PlaylistTrack(kind: kind, role: role, url: url, selected: selected, refreshCount: refreshCount)
    }

    private func incrementRefreshCount(_ playlistID: String) {
        playlistTracks[playlistID]?.refreshCount += 1
    }

    /// Cadence baseline used when a media playlist omits `EXT-X-TARGETDURATION`.
    private static let defaultTargetDuration = Duration.seconds(6)

    private func duration(_ seconds: Double?) -> Duration {
        seconds.map { .seconds($0) } ?? Self.defaultTargetDuration
    }

    private static func signature(_ violation: RuleViolation, resource: URL) -> String {
        let line = violation.location?.line.map(String.init) ?? "-"
        return "\(resource.absoluteString)|\(violation.ruleId)|\(line)|\(violation.message)"
    }

    private static func makeSessionID(_ date: Date) -> String {
        let stamp = date.formatted(
            .verbatim(
                "\(year: .extended(minimumLength: 4))\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                timeZone: .current,
                calendar: .current
            )
        )
        let random = String(UInt32.random(in: 0..<0xFFFF), radix: 16)
        return "\(stamp)-\(random)"
    }
}

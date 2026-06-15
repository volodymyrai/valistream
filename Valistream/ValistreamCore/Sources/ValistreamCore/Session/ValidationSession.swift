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
///
/// Monitoring loop lives in `ValidationSession+Monitoring.swift`;
/// report writing lives in `ValidationSession+Reporting.swift`.
public actor ValidationSession {
    // MARK: - Lets & Vars

    public let id: String
    public let inputURL: URL
    public let config: SessionConfig

    /// The live event stream consumed by the presentation layer.
    public nonisolated let events: AsyncStream<SessionEvent>

    // Internal — accessed from Monitoring and Reporting extension files.
    let fetcher: any StreamFetching
    let now: @Sendable () -> Date
    let sleep: @Sendable (Duration) async throws -> Void
    let selectPlaylists: (@Sendable ([PlaylistSelection.Candidate]) async -> [PlaylistSelection.Candidate])?
    let continuation: AsyncStream<SessionEvent>.Continuation
    let loader: PlaylistLoader
    let engine: RuleEngine
    let classifier = StreamClassifier()
    let continuityChecker = ContinuityChecker()
    let stalenessDetector = StalenessDetector()

    struct PlaylistTrack {
        var kind: PlaylistKind
        var role: PlaylistRole?
        var url: URL
        var selected: Bool
        var refreshCount: Int
    }

    private var lifecycle = SessionLifecycle()
    private var findings: [Finding] = []
    private var recordedSignatures: Set<String> = []
    var evidenceEntries: [SessionArchive.IndexEntry] = []

    private var monitorStates: [String: MonitorState] = [:]
    private var streamKind: StreamKind?
    private var findingCounter = 0
    var stopRequested = false
    var timeLimitExpired = false
    public private(set) var endReason: SessionEndReason?
    public private(set) var failureMessage: String?
    var archive: SessionArchive?
    private var findingsLog: FindingsLog?
    var diskWatcher: DiskSpaceWatcher?
    var archiveStopped = false
    var startedAt: Date?
    var playlistTracks: [String: PlaylistTrack] = [:]

    /// Session-wide monotonic refresh counter (D7, FR-013, SC-004).
    ///
    /// Incremented once per completed refresh across **all** playlists in the session.
    /// Lives on the actor so all `monitorPlaylist` tasks can increment it safely without awaiting.
    private(set) var sessionRefreshTotal = 0

    /// Stable alias map built during playlist discovery (T039, FR-026).
    var aliasRegistry = AliasRegistry()



    // MARK: - Lifecycle

/// Occurrence-stamped events for human-readable renderers and reports.
    public nonisolated let timestampedEvents: AsyncStream<TimestampedEvent>

    let timestampedContinuation: AsyncStream<TimestampedEvent>.Continuation
    var timelineSequence = 0
    var loadedPlaylistInfo: Set<String> = []
    var previousRoster: [RosterEntry]?
    var playlistInformation: [PlaylistInformation] = []
    var recordedTimelineEvents: [RecordedTimelineEvent] = []

    struct RecordedTimelineEvent: Sendable {
        let sequence: Int
        let timestampedEvent: TimestampedEvent
    }

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
        (self.timestampedEvents, self.timestampedContinuation) = AsyncStream.makeStream()
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
    /// monitors the selected playlists on player-accurate cadence until stopped or the time limit.
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
                emit(.sessionFolderResolved(location.sessionFolder))
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

        if stopRequested {
            await finish(reason: .gracefulStop)
            return
        }

        setState(.fetchingMaster)
        let rootLoad = await loader.load(inputURL)
        await archiveFetch(rootLoad.result, requestURL: inputURL, playlistID: "master")
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
            aliasRegistry.alias(for: inputURL, role: .master, attributes: [:])
            for reference in references {
                let attrs = makeAttributes(for: reference, in: master)
                aliasRegistry.alias(for: reference.url, role: AliasRole(from: reference.role), attributes: attrs)
            }

            emitRoster(masterURL: inputURL, references: references)
            let masterID = aliasRegistry.alias(for: inputURL)?.alias ?? "master"
            emitPlaylistInformation(playlistID: masterID, playlist: rootPlaylist)

            let activityLabel = "validating media playlists"
            for (index, reference) in references.enumerated() {
                if stopRequested {
                    await finish(reason: .gracefulStop)
                    return
                }
                emit(.activity(ActivityProgress(
                    activity: activityLabel,
                    completed: index,
                    total: references.count,
                    aliasInScope: aliasRegistry.alias(for: reference.url)?.alias
                )))
                let load = await loader.load(reference.url, role: reference.role)
                let playlistID = "\(reference.role.rawValue)-\(index)"
                await archiveFetch(load.result, requestURL: reference.url, playlistID: playlistID)
                if let playlist = load.playlist {
                    trackPlaylist(playlistID, kind: .media, role: reference.role, url: reference.url, selected: true, refreshCount: 1)
                    let presentationID = aliasRegistry.alias(for: reference.url)?.alias ?? playlistID
                    let loadedKind = playlist.media.map(classifier.classify)
                    emitPlaylistInformation(
                        playlistID: presentationID,
                        playlist: playlist,
                        streamKind: loadedKind
                    )
                }
                mediaLoads.append(load)
                emit(.activity(ActivityProgress(
                    activity: activityLabel,
                    completed: index + 1,
                    total: references.count,
                    aliasInScope: aliasRegistry.alias(for: reference.url)?.alias
                )))
            }
        } else {
            aliasRegistry.alias(for: inputURL, role: .video, attributes: [:])
            mediaLoads.append(rootLoad)
            trackPlaylist("media", kind: .media, role: .variant, url: inputURL, selected: true, refreshCount: 1)
            emitRoster(masterURL: nil, references: [])
            let presentationID = aliasRegistry.alias(for: inputURL)?.alias ?? "media"
            let loadedKind = rootPlaylist.media.map(classifier.classify)
            emitPlaylistInformation(
                playlistID: presentationID,
                playlist: rootPlaylist,
                streamKind: loadedKind
            )
            emit(.activity(ActivityProgress(activity: "validating media playlist", completed: 1, total: 1)))
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
        } else {
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
        } else if timeLimitExpired {
            await finish(reason: .timeLimit)
        } else {
            await finish(reason: .completed)
        }
    }



    // MARK: - Internal

    /// Transitions the lifecycle and emits a `stateChanged` event. Invalid transitions are ignored
    /// defensively so a late abort/finish cannot crash the engine.
func emit(_ event: SessionEvent, at occurrence: Date? = nil) {
        let timestampedEvent = TimestampedEvent(at: occurrence ?? now(), event: event)
        continuation.yield(event)
        timestampedContinuation.yield(timestampedEvent)

        guard isTimelineEligible(event) else { return }
        timelineSequence += 1
        recordedTimelineEvents.append(RecordedTimelineEvent(
            sequence: timelineSequence,
            timestampedEvent: timestampedEvent
        ))
    }

    private func isTimelineEligible(_ event: SessionEvent) -> Bool {
        switch event {
        case .finding, .playlistLifecycle:
            true
        case .stateChanged(let state):
            state.isTerminal
        default:
            false
        }
    }

    func setState(_ target: SessionState) {
        guard (try? lifecycle.transition(to: target)) != nil else { return }
        emit(.stateChanged(target))
        if target.isTerminal {
            continuation.finish()
            timestampedContinuation.finish()
        }
    }

    /// Records the stream classification and emits it.
    func setClassification(_ kind: StreamKind) {
        streamKind = kind
        emit(.streamClassified(kind))
    }

    /// Mints a ``Finding`` from a rule violation, assigning a session-unique id and timestamp,
    /// records it, and emits it on the event stream.
    /// Mints, records, and emits a finding with its resolved archive evidence.
    @discardableResult
    func record(
        _ violation: RuleViolation,
        resource: URL,
        refreshIndex: Int? = nil,
        evidenceBaselineRefreshIndex: Int? = nil
    ) -> Finding {
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
        let evidence: EvidenceReference? = finding.severity == .info ? nil : EvidenceResolver().resolve(
            finding,
            aliases: aliasRegistry,
            artifactIndex: evidenceEntries,
            fallbackID: resource == inputURL ? "master" : "playlist_1",
            baselineRefreshIndex: evidenceBaselineRefreshIndex
        )
        emit(.finding(finding, evidence: evidence), at: finding.observedAt)

        return finding
    }

    /// Records a violation only if an identical one has not already been recorded.
    func recordIfNew(_ violation: RuleViolation, resource: URL, refreshIndex: Int? = nil) {
        guard recordedSignatures.contains(Self.signature(violation, resource: resource)) == false else {
            return
        }
        record(violation, resource: resource, refreshIndex: refreshIndex)
    }

    /// Updates a playlist's monitor state and emits the change (de-duplicating no-op updates).
    func setMonitorState(_ playlistID: String, _ state: MonitorState) {
        let previousState = monitorStates[playlistID]
        guard previousState != state else { return }
        monitorStates[playlistID] = state

        let occurrence = now()
        emit(.monitorStateChanged(playlistID: playlistID, state: state), at: occurrence)

        let lifecycleKind: PlaylistLifecycleEvent.Kind?
        if state == .staleError {
            lifecycleKind = .unavailable
        } else if previousState == .staleError, state == .monitoring {
            lifecycleKind = .recovered
        } else {
            lifecycleKind = nil
        }

        if let lifecycleKind {
            emit(.playlistLifecycle(PlaylistLifecycleEvent(
                playlistID: playlistID,
                at: occurrence,
                kind: lifecycleKind
            )), at: occurrence)
        }
    }

    /// The monitor state currently recorded for a playlist, or `nil` if none yet. Lets the monitor
    /// loop (in the extension) record staleness only on a level transition.
    func monitorState(for playlistID: String) -> MonitorState? {
        monitorStates[playlistID]
    }

    /// The fetcher this session uses (for the flow tasks wired by US1+).
    var streamFetcher: any StreamFetching {
        fetcher
    }



    // MARK: - Private

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

    func incrementRefreshCount(_ playlistID: String) {
        playlistTracks[playlistID]?.refreshCount += 1
        sessionRefreshTotal += 1
    }

    /// Builds alias-derivation attributes from the master playlist context.
    private func makeAttributes(for reference: PlaylistReference, in master: MasterPlaylist) -> [String: String] {
        var attrs: [String: String] = [:]
        switch reference.role {
        case .variant:
            if let variant = master.variants.first(where: { $0.uri == reference.url }) {
                if let res = variant.resolution {
                    attrs["RESOLUTION"] = "\(res.width)x\(res.height)"
                }
                if let codecs = variant.attributes["CODECS"] {
                    attrs["CODECS"] = codecs
                }
            }
        case .audio, .subtitles:
            if let rendition = master.renditions.first(where: { $0.uri == reference.url }) {
                if let lang = rendition.language { attrs["LANGUAGE"] = lang }
                if let name = rendition.name     { attrs["NAME"] = name }
            } else if let name = reference.name {
                attrs["NAME"] = name
            }
        case .iframe:
            if let iframe = master.iFrameStreams.first(where: { $0.uri == reference.url }),
               let res = iframe.resolution {
                attrs["RESOLUTION"] = "\(res.width)x\(res.height)"
            }
        }
        return attrs
    }

    /// Cadence baseline used when a media playlist omits `EXT-X-TARGETDURATION`.
    private static let defaultTargetDuration = Duration.seconds(6)

    func duration(_ seconds: Double?) -> Duration {
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

    /// Emits a `.rosterReady` event listing all discovered playlist IDs, URLs, and roles (FR-011, US2).
    ///
    /// Called once after all aliases are registered and before any media fetch, so the roster
    /// appears before any body output and full URLs never repeat afterward (SC-003).
    private func emitRoster(masterURL: URL?, references: [PlaylistReference]) {
        var entries: [RosterEntry] = []
        if let masterURL {
            let id = aliasRegistry.alias(for: masterURL)?.alias ?? "master"
            entries.append(RosterEntry(id: id, url: masterURL, role: "master"))
        }
        for reference in references {
            let id = aliasRegistry.alias(for: reference.url)?.alias ?? reference.role.rawValue
            entries.append(RosterEntry(id: id, url: reference.url, role: reference.role.rawValue))
        }
        if entries.isEmpty {
            let id = aliasRegistry.alias(for: inputURL)?.alias ?? "media"
            entries.append(RosterEntry(id: id, url: inputURL, role: "video"))
        }

        let occurrence = now()
        if let previousRoster {
            let previousByURL = Dictionary(uniqueKeysWithValues: previousRoster.map { ($0.url, $0) })
            let currentByURL = Dictionary(uniqueKeysWithValues: entries.map { ($0.url, $0) })

            for entry in previousRoster where currentByURL[entry.url] == nil {
                emit(.playlistLifecycle(PlaylistLifecycleEvent(
                    playlistID: entry.id,
                    at: occurrence,
                    kind: .removed
                )), at: occurrence)
            }
            for entry in entries {
                guard let previous = previousByURL[entry.url] else {
                    emit(.playlistLifecycle(PlaylistLifecycleEvent(
                        playlistID: entry.id,
                        at: occurrence,
                        kind: .added
                    )), at: occurrence)
                    continue
                }
                if previous.id != entry.id {
                    emit(.playlistLifecycle(PlaylistLifecycleEvent(
                        playlistID: entry.id,
                        at: occurrence,
                        kind: .identityChanged
                    )), at: occurrence)
                }
            }
        }

        previousRoster = entries
        emit(.rosterReady(entries), at: occurrence)
    }
}

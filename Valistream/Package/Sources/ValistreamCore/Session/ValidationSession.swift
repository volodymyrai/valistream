//
//  ValidationSession.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Orchestrates one run of the validator against one stream URL (data-model.md ValidationSession).
///
/// The session owns all mutable run state — lifecycle, findings, discovered playlists — as an actor
/// so live monitoring tasks can update it without data races (research §9). Status and findings flow
/// out through the ``events`` stream for the CLI to render (FR-009). This type is the skeleton:
/// the one-shot and monitoring flows are wired in their respective user-story tasks.
public actor ValidationSession {
    // MARK: - Lets & Vars

    public let id: String
    public let inputURL: URL
    public let config: SessionConfig

    /// The live event stream consumed by the presentation layer.
    public nonisolated let events: AsyncStream<SessionEvent>

    private let fetcher: any StreamFetching
    private let now: @Sendable () -> Date
    private let continuation: AsyncStream<SessionEvent>.Continuation
    private let loader: PlaylistLoader
    private let engine: RuleEngine
    private let classifier = StreamClassifier()

    private var lifecycle = SessionLifecycle()
    private var findings: [Finding] = []
    private var streamKind: StreamKind?
    private var findingCounter = 0



    // MARK: - Lifecycle

    public init(
        inputURL: URL,
        config: SessionConfig,
        fetcher: any StreamFetching,
        id: String? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.inputURL = inputURL
        self.config = config
        self.fetcher = fetcher
        self.now = now
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

    /// Runs a one-shot validation: fetch the master (or direct media) playlist, fetch every
    /// referenced media playlist, classify the stream, and evaluate all rules. Findings are emitted
    /// on ``events`` as they are recorded (US1, FR-002/FR-004/FR-005).
    public func run() async {
        setState(.fetchingMaster)
        let rootLoad = await loader.load(inputURL)
        for violation in rootLoad.deliveryViolations {
            record(violation, resource: inputURL)
        }
        guard let rootPlaylist = rootLoad.playlist else {
            setState(.failed)
            return
        }

        setState(.validatingInitial)

        var mediaLoads: [LoadedPlaylist] = []
        if case .master(let master) = rootPlaylist {
            for reference in loader.mediaReferences(in: master) {
                mediaLoads.append(await loader.load(reference.url, role: reference.role))
            }
        }
        else {
            mediaLoads.append(rootLoad)
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

        setState(.finishing)
        setState(.completed)
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
        continuation.yield(.finding(finding))
        return finding
    }

    /// The fetcher this session uses (for the flow tasks wired by US1+).
    var streamFetcher: any StreamFetching {
        fetcher
    }



    // MARK: - Private

    private func evaluate(playlist: Playlist, tokens: [M3U8Token], resource: URL, kind: StreamKind) {
        let context = RuleContext(playlist: playlist, tokens: tokens, resource: resource, streamKind: kind)
        for violation in engine.evaluate(context) {
            record(violation, resource: resource)
        }
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

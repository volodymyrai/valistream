//
//  SessionConfig.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// User-supplied configuration for a validation session (data-model.md ValidationSession.config).
public struct SessionConfig: Sendable, Equatable {
    /// Whether to download and audit segments (FR-012). Off by default.
    public var segmentMode: Bool

    /// Allowed bandwidth deviation as a fraction, default 0.10 (FR-012).
    public var bandwidthTolerance: Double

    /// Optional live-session time cap (FR-015).
    public var timeLimit: Duration?

    /// Parent directory for session folders (FR-010). `nil` selects the platform default base
    /// (`OutputLocation.defaultBase()` — `~/.valistream/sessions/` on macOS).
    public var outputDir: URL?

    /// Suppresses the interactive checklist prompt (FR-018).
    public var nonInteractive: Bool

    /// Pre-supplied playlist selection patterns for non-interactive runs (FR-018).
    public var selectionPatterns: [String]?

    /// Whether to archive fetched playlists and produce session reports (US3).
    ///
    /// Defaults to `false` so integration tests do not create filesystem artefacts unless
    /// they explicitly opt in. The CLI sets this to `true`.
    public var archiveEnabled: Bool

    /// Whether to emit verbose `.trace` events for detailed action tracing (US2, D9).
    ///
    /// Defaults to `false`; the CLI sets this to `true` when `--verbose` is passed.
    public var verboseEvents: Bool

    public init(
        segmentMode: Bool = false,
        bandwidthTolerance: Double = 0.10,
        timeLimit: Duration? = nil,
        outputDir: URL? = nil,
        nonInteractive: Bool = false,
        selectionPatterns: [String]? = nil,
        archiveEnabled: Bool = false,
        verboseEvents: Bool = false
    ) {
        self.segmentMode = segmentMode
        self.bandwidthTolerance = bandwidthTolerance
        self.timeLimit = timeLimit
        self.outputDir = outputDir
        self.nonInteractive = nonInteractive
        self.selectionPatterns = selectionPatterns
        self.archiveEnabled = archiveEnabled
        self.verboseEvents = verboseEvents
    }
}

/// One entry in the start-of-session roster (FR-011, SC-003).
///
/// Contains the short presentation ID, the full source URL, and a human-readable role label.
/// The roster is the **only** place full URLs are printed; the body uses IDs only.
public struct RosterEntry: Sendable, Equatable {
    /// The short, human-readable playlist ID (e.g. `master`, `1080p_avc1`, `audio_en`).
    public let id: String

    /// The full source URL — printed once in the roster, never repeated in the body.
    public let url: URL

    /// The human-readable role label (e.g. `master`, `video`, `audio`).
    public let role: String

    /// Optional additional attributes string (e.g. resolution, codec, language).
    public let attributes: String?

    public init(id: String, url: URL, role: String, attributes: String? = nil) {
        self.id = id
        self.url = url
        self.role = role
        self.attributes = attributes
    }
}

/// A verbose-tier trace event covering one action the session performed (D9, FR-015b).
///
/// All cases carry only playlist IDs and snapshot labels — never raw URLs — preserving SC-003.
public enum TraceEvent: Sendable, Equatable {
    /// About to fetch a playlist URL (emitted at fetch start, verbose tier).
    case fetchStarted(url: URL, playlistID: String, refreshIndex: Int)

    /// About to request a playlist snapshot.
    case fetchIntent(snapshotID: String)

    /// A playlist fetch completed with an HTTP response.
    case fetchResult(snapshotID: String, httpStatus: Int, durationMs: Int, bytes: Int)

    /// A playlist snapshot passed all validation rules.
    case validationPlaylistOK(snapshotID: String)

    /// A playlist snapshot produced at least one finding.
    case validationPlaylistFail(snapshotID: String, errorCount: Int, warnCount: Int)

    /// A single validation rule passed for a snapshot.
    case validationRuleOK(snapshotID: String, ruleID: String)

    /// A single validation rule fired a finding for a snapshot.
    case validationRuleFail(snapshotID: String, ruleID: String)

    /// A snapshot body was written to the archive.
    case stored(snapshotID: String, archivePath: String)

    /// The refresh scheduler decided the next sleep delay.
    case refreshScheduled(playlistID: String, delaySeconds: Double)

    /// The actual refresh arrived with a measurable cadence drift.
    case refreshDrift(playlistID: String, driftSeconds: Double)

    /// A continuity comparison was performed between two consecutive snapshots.
    case continuityCompare(olderSnapshotID: String, newerSnapshotID: String)

    /// A new rendition appeared in the stream.
    case renditionAdded(playlistID: String)

    /// A previously seen rendition disappeared from the stream.
    case renditionDropped(playlistID: String)
}

/// An event emitted on the session's live event stream, consumed by the CLI (FR-009).
public enum SessionEvent: Sendable {
    case stateChanged(SessionState)
    case streamClassified(StreamKind)
    case finding(Finding, evidence: EvidenceReference?)
    case monitorStateChanged(playlistID: String, state: MonitorState)
    case activity(ActivityProgress)
    /// Fired once after the output directory is resolved and writable-verified, before any fetch (FR-017).
    case sessionFolderResolved(URL)

    // MARK: - Human-readable output additions

    /// Fired once for each playlist after its first successful load.
    case playlistInformation(PlaylistInformation)

    /// Fired when a playlist's availability or roster identity changes.
    case playlistLifecycle(PlaylistLifecycleEvent)

    // MARK: - US2 additions (additive — no JSON/exit impact)

    /// Fired once after all playlist IDs are assigned and before the first fetch (FR-011).
    case rosterReady([RosterEntry])

    /// Fired once per completed refresh cycle for a playlist (normal+ tier, FR-015a).
    case refreshCompleted(playlistID: String, index: Int, errors: Int, warnings: Int)

    /// A verbose-tier action trace (emitted only when `SessionConfig.verboseEvents == true`, D9).
    case trace(TraceEvent)
}

/// Why a session finalized — drives report labeling and the CLI shutdown notice (US2, data-model).
/// An event paired with the instant at which it occurred.
public struct TimestampedEvent: Sendable {
    /// The occurrence instant captured by the session clock.
    public let at: Date

    /// The raw session event.
    public let event: SessionEvent

    /// Creates an occurrence-stamped event.
    public init(at: Date, event: SessionEvent) {
        self.at = at
        self.event = event
    }
}

public enum SessionEndReason: Sendable {
    case completed
    case gracefulStop
    case timeLimit
}

/// Live activity and progress state emitted on the events stream (US1, data-model).
public struct ActivityProgress: Sendable {

    // MARK: - Lets & Vars

    public let activity: String
    public let completed: Int
    public let total: Int?
    public let refreshes: Int?
    public let aliasInScope: String?
    /// Session-wide monotonic refresh counter (D7, FR-013, SC-004).
    ///
    /// Incremented once per completed refresh across **all** playlists in the session.
    /// Never decreases. `nil` when no refresh has completed yet or when the event is
    /// not refresh-related (e.g. initial scan activity).
    public let sessionRefreshTotal: Int?



    // MARK: - Lifecycle

    public init(
        activity: String,
        completed: Int,
        total: Int? = nil,
        refreshes: Int? = nil,
        aliasInScope: String? = nil,
        sessionRefreshTotal: Int? = nil
    ) {
        self.activity = activity
        self.completed = completed
        self.total = total
        self.refreshes = refreshes
        self.aliasInScope = aliasInScope
        self.sessionRefreshTotal = sessionRefreshTotal
    }
}

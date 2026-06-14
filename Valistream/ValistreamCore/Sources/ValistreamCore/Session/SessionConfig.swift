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

    /// Parent directory for session folders (FR-010).
    public var outputDir: URL

    /// Suppresses the interactive checklist prompt (FR-018).
    public var nonInteractive: Bool

    /// Pre-supplied playlist selection patterns for non-interactive runs (FR-018).
    public var selectionPatterns: [String]?

    /// Whether to archive fetched playlists and produce session reports (US3).
    ///
    /// Defaults to `false` so integration tests do not create filesystem artefacts unless
    /// they explicitly opt in. The CLI sets this to `true`.
    public var archiveEnabled: Bool

    public init(
        segmentMode: Bool = false,
        bandwidthTolerance: Double = 0.10,
        timeLimit: Duration? = nil,
        outputDir: URL = URL(fileURLWithPath: "./valistream-sessions"),
        nonInteractive: Bool = false,
        selectionPatterns: [String]? = nil,
        archiveEnabled: Bool = false
    ) {
        self.segmentMode = segmentMode
        self.bandwidthTolerance = bandwidthTolerance
        self.timeLimit = timeLimit
        self.outputDir = outputDir
        self.nonInteractive = nonInteractive
        self.selectionPatterns = selectionPatterns
        self.archiveEnabled = archiveEnabled
    }
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
}

/// Why a session finalized — drives report labeling and the CLI shutdown notice (US2, data-model).
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



    // MARK: - Lifecycle

    public init(
        activity: String,
        completed: Int,
        total: Int? = nil,
        refreshes: Int? = nil,
        aliasInScope: String? = nil
    ) {
        self.activity = activity
        self.completed = completed
        self.total = total
        self.refreshes = refreshes
        self.aliasInScope = aliasInScope
    }
}

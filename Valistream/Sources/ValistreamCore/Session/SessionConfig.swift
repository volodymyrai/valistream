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

    public init(
        segmentMode: Bool = false,
        bandwidthTolerance: Double = 0.10,
        timeLimit: Duration? = nil,
        outputDir: URL = URL(fileURLWithPath: "./valistream-sessions"),
        nonInteractive: Bool = false,
        selectionPatterns: [String]? = nil
    ) {
        self.segmentMode = segmentMode
        self.bandwidthTolerance = bandwidthTolerance
        self.timeLimit = timeLimit
        self.outputDir = outputDir
        self.nonInteractive = nonInteractive
        self.selectionPatterns = selectionPatterns
    }
}

/// An event emitted on the session's live event stream, consumed by the CLI (FR-009).
public enum SessionEvent: Sendable {
    case stateChanged(SessionState)
    case streamClassified(StreamKind)
    case finding(Finding)
}

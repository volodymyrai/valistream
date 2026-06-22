import Foundation

// MARK: - TimelineKind

/// The classification of an entry in the incident timeline.
public enum TimelineKind: Equatable, Sendable {
    /// A playlist lifecycle transition (unavailable, recovered, added, removed, identity changed).
    case lifecycle(PlaylistLifecycleEvent.Kind)
    /// A finding with the given severity (warning or error only; info is excluded).
    case finding(Finding.Severity)
    /// An operational failure: session failed, fetch failure, or evidence-capture failure.
    case operationalFailure
}

// MARK: - IncidentTimeline

/// An ordered, deduplicated record of noteworthy session events suitable for the report
/// incident timeline section.
///
/// Routine refreshes and informational findings are excluded. Entries are ordered by
/// `(occurrence, sequence)` ascending so that the ordering is deterministic regardless of
/// the order in which events were supplied.
public struct IncidentTimeline: Equatable, Sendable {

    // MARK: - Entry

    /// A single row in the incident timeline.
    public struct Entry: Equatable, Sendable {
        /// The monotonic sequence number of the underlying event (used for deterministic tie-breaking).
        public let sequence: Int
        /// The kind of event.
        public let kind: TimelineKind
        /// The markdown anchor for the finding this entry links to, or `nil` for non-finding entries.
        /// Format: `"finding-<id>"`.
        public let findingAnchor: String?
        /// A compact human-readable summary. Finding entries do NOT include the finding message or
        /// evidence path — they link via `findingAnchor` only (R11).
        public let summary: String

        init(sequence: Int, kind: TimelineKind, findingAnchor: String? = nil, summary: String) {
            self.sequence = sequence
            self.kind = kind
            self.findingAnchor = findingAnchor
            self.summary = summary
        }
    }

    // MARK: - Public

    /// The timeline entries, ordered by `(occurrence timestamp, sequence)` ascending.
    public let entries: [Entry]

    // MARK: - Lifecycle

    /// Assembles an incident timeline from raw recorded events.
    ///
    /// - Parameter events: Tuples of `(sequence, TimestampedEvent)` as accumulated by
    ///   `ValidationSession`. Events that are not timeline-eligible (e.g. routine refreshes,
    ///   informational findings) are silently excluded.
    public init(events: [(sequence: Int, event: TimestampedEvent)]) {
        let eligible = events.compactMap { pair -> (at: Date, sequence: Int, entry: Entry)? in
            Self.makeEntry(sequence: pair.sequence, timestampedEvent: pair.event)
        }
        let sorted = eligible.sorted { lhs, rhs in
            if lhs.at == rhs.at { return lhs.sequence < rhs.sequence }
            return lhs.at < rhs.at
        }
        self.entries = sorted.map(\.entry)
    }

    // MARK: - Private

    private static func makeEntry(
        sequence: Int,
        timestampedEvent: TimestampedEvent
    ) -> (at: Date, sequence: Int, entry: Entry)? {
        let at = timestampedEvent.at
        switch timestampedEvent.event {
        case .finding(let finding, _):
            // Exclude info-severity findings; only warning and error are incident-worthy.
            guard finding.severity != .info else { return nil }
            let anchor = "finding-\(finding.id)"
            let summary = "\(finding.severity.rawValue.capitalized) finding in \(finding.resource.lastPathComponent)"
            let entry = Entry(
                sequence: sequence,
                kind: .finding(finding.severity),
                findingAnchor: anchor,
                summary: summary
            )
            return (at: at, sequence: sequence, entry: entry)

        case .playlistLifecycle(let lifecycle):
            let summary = lifecycleSummary(for: lifecycle)
            let entry = Entry(
                sequence: sequence,
                kind: .lifecycle(lifecycle.kind),
                findingAnchor: nil,
                summary: summary
            )
            return (at: at, sequence: sequence, entry: entry)

        case .stateChanged(let state):
            // Operational failures: failed state.
            guard state == .failed || state == .aborted else { return nil }
            let summary = state == .failed
                ? "Session failed and could not continue."
                : "Session was interrupted."
            let entry = Entry(
                sequence: sequence,
                kind: .operationalFailure,
                findingAnchor: nil,
                summary: summary
            )
            return (at: at, sequence: sequence, entry: entry)

        default:
            // refreshCompleted, activity, rosterReady, trace, monitorStateChanged,
            // sessionFolderResolved, streamClassified, playlistInformation — all excluded.
            return nil
        }
    }

    private static func lifecycleSummary(for lifecycle: PlaylistLifecycleEvent) -> String {
        switch lifecycle.kind {
        case .unavailable:
            "Playlist \(lifecycle.playlistID) became unavailable."
        case .recovered:
            "Playlist \(lifecycle.playlistID) recovered."
        case .added:
            "Playlist \(lifecycle.playlistID) was added to the roster."
        case .removed:
            "Playlist \(lifecycle.playlistID) was removed from the roster."
        case .identityChanged:
            "Playlist \(lifecycle.playlistID) changed identity."
        }
    }
}

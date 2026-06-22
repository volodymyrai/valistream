//
//  MonitorState.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

/// The live-monitoring state of one media playlist (data-model.md PlaylistDescriptor.monitorState,
/// FR-007/FR-009).
public enum MonitorState: String, Sendable, Equatable, Codable {
    /// Discovered but not yet being monitored.
    case idle

    /// Refreshing on cadence with no staleness escalation.
    case monitoring

    /// Has not changed for longer than 1.5× its target duration.
    case staleWarning

    /// Has not changed for longer than 3× its target duration (effective outage).
    case staleError

    /// Monitoring ended — the playlist hit `EXT-X-ENDLIST`, the session stopped, or the time limit
    /// expired.
    case stopped
}

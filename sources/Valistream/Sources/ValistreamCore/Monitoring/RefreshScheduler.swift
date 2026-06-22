//
//  RefreshScheduler.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

/// Computes player-accurate reload delays for one monitored media playlist per RFC 8216 §6.3.4
/// (research §4).
///
/// A client reloads no earlier than the playlist's target duration after a load; when a reload
/// shows no change it backs off to one-half the target duration before retrying, and never reloads
/// faster than that. The scheduler is pure — the session owns the clock and the sleeping (research
/// §9) — so cadence is unit-testable with no wall-clock waiting.
public struct RefreshScheduler: Sendable {
    // MARK: - Lets & Vars

    /// The playlist's declared target duration: the cadence baseline.
    public let targetDuration: Duration



    // MARK: - Lifecycle

    /// Creates a scheduler for a playlist with the given target duration.
    public init(targetDuration: Duration) {
        self.targetDuration = targetDuration
    }



    // MARK: - Public

    /// The delay before the first reload, measured from the initial load: one target duration.
    public var initialDelay: Duration {
        targetDuration
    }

    /// The delay before the next reload, given whether the most recent refresh changed the playlist:
    /// one target duration when it changed, one-half when it did not (the §6.3.4 no-change backoff).
    /// The result is never shorter than half the target duration, so the client never hammers.
    public func nextDelay(didChange changed: Bool) -> Duration {
        changed ? targetDuration : targetDuration / 2
    }
}

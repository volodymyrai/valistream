//
//  ManualClock.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import os
import ValistreamCore

/// A deterministic `Clock` whose time only moves when a test calls ``advance(by:)``.
///
/// Tasks that `sleep(until:)` suspend until the clock is advanced past their deadline, so live
/// monitoring cadence (research §4/§9) can be exercised with zero wall-clock waiting. All state is
/// guarded by an unfair lock, making the clock safe to share across the session's monitor tasks.
///
/// Example:
/// ```swift
/// let clock = ManualClock()
/// let task = Task { try await clock.sleep(for: .seconds(6)) }
/// clock.advance(by: .seconds(6))   // resumes the sleeping task
/// ```
final class ManualClock: Clock, @unchecked Sendable {
    // MARK: - Nested types

    /// An instant expressed as a `Duration` offset from the clock's start.
    struct Instant: InstantProtocol {
        let offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
        var nextID = 0
    }



    // MARK: - Lets & Vars

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var now: Instant { lock.withLock { $0.now } }

    var minimumResolution: Duration { .zero }

    /// The number of tasks currently suspended in ``sleep(until:tolerance:)``.
    ///
    /// Tests poll this to know a monitor loop has parked on the clock before advancing it, so a
    /// cadence step deterministically wakes exactly the intended sleepers.
    var sleeperCount: Int { lock.withLock { $0.sleepers.count } }

    /// The current time expressed as fractional seconds since the clock's start.
    var elapsedSeconds: Double {
        now.offset.seconds
    }



    // MARK: - Internal

    /// Moves time forward and resumes every sleeper whose deadline has now passed.
    func advance(by duration: Duration) {
        let due: [Sleeper] = lock.withLock { state in
            state.now = state.now.advanced(by: duration)
            let ready = state.sleepers.filter { $0.deadline <= state.now }
            state.sleepers.removeAll { $0.deadline <= state.now }
            return ready
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }

    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try Task.checkCancellation()
        let id = lock.withLock { state -> Int in
            let next = state.nextID
            state.nextID += 1
            return next
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let resumeImmediately = lock.withLock { state -> Bool in
                    if deadline <= state.now {
                        return true
                    }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return false
                }
                if resumeImmediately {
                    continuation.resume()
                }
            }
        } onCancel: {
            let cancelled: CheckedContinuation<Void, any Error>? = lock.withLock { state in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                    return nil
                }
                return state.sleepers.remove(at: index).continuation
            }
            cancelled?.resume(throwing: CancellationError())
        }
    }
}

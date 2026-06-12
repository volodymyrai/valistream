//
//  ValidationSessionState.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

/// The lifecycle states of a validation session (data-model.md lifecycle).
public enum SessionState: String, Sendable, Equatable, Codable {
    case initializing
    case fetchingMaster
    case validatingInitial
    case selectingPlaylists
    case monitoring
    case finishing
    case completed
    case aborted
    case failed

    /// Whether no further transitions are permitted from this state.
    public var isTerminal: Bool {
        switch self {
        case .completed, .aborted, .failed: true
        default: false
        }
    }
}

/// Guards the session's state transitions so the engine can only move along the defined lifecycle.
///
/// A session may abort or fail from any active state (user interrupt or fatal error — FR-015,
/// edge cases); terminal states are final. The empty-selection short-circuit is expressed as the
/// `selectingPlaylists → finishing` edge (data-model.md).
public struct SessionLifecycle: Sendable, Equatable {
    // MARK: - Nested types

    /// Thrown when a transition is not permitted from the current state.
    public struct InvalidTransition: Error, Equatable {
        public let from: SessionState
        public let to: SessionState
    }



    // MARK: - Lets & Vars

    public private(set) var state: SessionState



    // MARK: - Lifecycle

    public init() {
        self.state = .initializing
    }



    // MARK: - Public

    /// Whether a transition to `target` is permitted from the current state.
    public func canTransition(to target: SessionState) -> Bool {
        Self.allowed(from: state).contains(target)
    }

    /// Transitions to `target`, throwing if the move is not part of the lifecycle.
    public mutating func transition(to target: SessionState) throws(InvalidTransition) {
        guard canTransition(to: target) else {
            throw InvalidTransition(from: state, to: target)
        }
        state = target
    }



    // MARK: - Private

    private static func allowed(from state: SessionState) -> Set<SessionState> {
        if state.isTerminal {
            return []
        }
        // Abort and failure are reachable from every active state.
        var transitions: Set<SessionState> = [.aborted, .failed]
        switch state {
        case .initializing:
            transitions.insert(.fetchingMaster)
        case .fetchingMaster:
            transitions.insert(.validatingInitial)
        case .validatingInitial:
            transitions.formUnion([.selectingPlaylists, .finishing])
        case .selectingPlaylists:
            transitions.formUnion([.monitoring, .finishing])
        case .monitoring:
            transitions.insert(.finishing)
        case .finishing:
            transitions.insert(.completed)
        case .completed, .aborted, .failed:
            break
        }
        return transitions
    }
}

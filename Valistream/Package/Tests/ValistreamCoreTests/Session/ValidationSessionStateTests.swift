//
//  ValidationSessionStateTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite("SessionLifecycle", .tags(.session))
struct ValidationSessionStateTests {
    // MARK: - Happy paths

    @Test("walks the full live monitoring lifecycle")
    func liveLifecycle() throws {
        var lifecycle = SessionLifecycle()
        let path: [SessionState] = [
            .fetchingMaster, .validatingInitial, .selectingPlaylists, .monitoring, .finishing, .completed,
        ]
        for state in path {
            try lifecycle.transition(to: state)
        }
        #expect(lifecycle.state == .completed)
    }

    @Test("walks the one-shot VOD lifecycle without monitoring")
    func vodLifecycle() throws {
        var lifecycle = SessionLifecycle()
        for state in [SessionState.fetchingMaster, .validatingInitial, .finishing, .completed] {
            try lifecycle.transition(to: state)
        }
        #expect(lifecycle.state == .completed)
    }

    @Test("short-circuits to finishing when the selection is empty")
    func emptySelectionShortCircuits() throws {
        var lifecycle = SessionLifecycle()
        for state in [SessionState.fetchingMaster, .validatingInitial, .selectingPlaylists] {
            try lifecycle.transition(to: state)
        }
        try lifecycle.transition(to: .finishing)
        #expect(lifecycle.state == .finishing)
    }



    // MARK: - Abort and failure

    @Test("aborts from any active state", arguments: [
        SessionState.fetchingMaster, .validatingInitial, .selectingPlaylists, .monitoring, .finishing,
    ])
    func abortsFromActiveState(_ from: SessionState) throws {
        var lifecycle = SessionLifecycle()
        try lifecycle.transition(to: .fetchingMaster)
        if from != .fetchingMaster {
            try lifecycle.advance(through: from)
        }
        try lifecycle.transition(to: .aborted)
        #expect(lifecycle.state == .aborted)
    }

    @Test("fails from an active state")
    func failsFromActiveState() throws {
        var lifecycle = SessionLifecycle()
        try lifecycle.transition(to: .fetchingMaster)
        try lifecycle.transition(to: .failed)
        #expect(lifecycle.state == .failed)
    }



    // MARK: - Invalid transitions

    @Test("rejects skipping fetchingMaster")
    func rejectsSkippingFetch() {
        var lifecycle = SessionLifecycle()
        #expect(throws: SessionLifecycle.InvalidTransition.self) {
            try lifecycle.transition(to: .completed)
        }
    }

    @Test("rejects transitions out of a terminal state", arguments: [
        SessionState.completed, .aborted, .failed,
    ])
    func rejectsLeavingTerminal(_ terminal: SessionState) throws {
        var lifecycle = SessionLifecycle()
        try lifecycle.transition(to: .fetchingMaster)
        try lifecycle.transition(to: terminal == .completed ? .validatingInitial : terminal)
        if terminal == .completed {
            try lifecycle.transition(to: .finishing)
            try lifecycle.transition(to: .completed)
        }
        #expect(throws: SessionLifecycle.InvalidTransition.self) {
            try lifecycle.transition(to: .fetchingMaster)
        }
    }

    @Test("rejects going backwards from monitoring to fetchingMaster")
    func rejectsBackwards() throws {
        var lifecycle = SessionLifecycle()
        for state in [SessionState.fetchingMaster, .validatingInitial, .selectingPlaylists, .monitoring] {
            try lifecycle.transition(to: state)
        }
        #expect(throws: SessionLifecycle.InvalidTransition.self) {
            try lifecycle.transition(to: .fetchingMaster)
        }
    }
}

// MARK: - Test helpers

private extension SessionLifecycle {
    /// Advances in order through the canonical active states up to and including `target`.
    mutating func advance(through target: SessionState) throws(SessionLifecycle.InvalidTransition) {
        let order: [SessionState] = [.fetchingMaster, .validatingInitial, .selectingPlaylists, .monitoring, .finishing]
        guard let end = order.firstIndex(of: target) else { return }
        for state in order[1...end] where state != self.state {
            try transition(to: state)
        }
    }
}

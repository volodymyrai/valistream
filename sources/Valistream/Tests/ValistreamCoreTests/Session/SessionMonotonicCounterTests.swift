//
//  SessionMonotonicCounterTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import Testing
@testable import ValistreamCore

/// Tests the additive `ActivityProgress.sessionRefreshTotal` field that carries the
/// session-wide monotonic refresh counter (FR-013, SC-004, D7).
///
/// The end-to-end monotonic-across-refreshes behaviour is driven deterministically by
/// the integration `HeartbeatMonotonicTests` (the `ManualClock`/`ScriptedStreamFetcher`
/// seam lives in the integration-test target); this suite pins the API contract.
@Suite(.tags(.session), .timeLimit(.minutes(1)))
struct SessionMonotonicCounterTests {

    @Test("sessionRefreshTotal field exists on ActivityProgress")
    func sessionRefreshTotalFieldExists() {
        let progress = ActivityProgress(activity: "test", completed: 0, sessionRefreshTotal: 0)
        #expect(progress.sessionRefreshTotal == 0)
    }

    @Test("sessionRefreshTotal defaults to nil on existing call sites")
    func sessionRefreshTotalDefaultsNil() {
        let progress = ActivityProgress(activity: "test", completed: 0)
        #expect(progress.sessionRefreshTotal == nil)
    }

    @Test("sessionRefreshTotal is non-negative when set")
    func sessionRefreshTotalNonNegative() {
        let progress = ActivityProgress(
            activity: "monitoring live",
            completed: 5,
            refreshes: 5,
            sessionRefreshTotal: 5
        )
        #expect((progress.sessionRefreshTotal ?? -1) >= 0)
    }

    @Test("sessionRefreshTotal coexists with aliasInScope on the same activity")
    func sessionRefreshTotalAlongsideAliasInScope() {
        let progress = ActivityProgress(
            activity: "monitoring live",
            completed: 3,
            refreshes: 3,
            aliasInScope: "1080p_avc1",
            sessionRefreshTotal: 10
        )
        #expect(progress.aliasInScope == "1080p_avc1")
        #expect(progress.sessionRefreshTotal == 10)
    }
}

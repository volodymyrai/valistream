//
//  SessionEventProgressTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite(.tags(.session))
struct SessionEventProgressTests {

    // MARK: - SessionEndReason

    @Test("SessionEndReason has completed, gracefulStop and timeLimit cases")
    func sessionEndReasonCases() {
        _ = SessionEndReason.completed
        _ = SessionEndReason.gracefulStop
        _ = SessionEndReason.timeLimit
    }



    // MARK: - ActivityProgress

    @Test("ActivityProgress stores all fields")
    func activityProgressAllFields() {
        let p = ActivityProgress(
            activity: "fetching master",
            completed: 2,
            total: 5,
            refreshes: 3,
            aliasInScope: "video-1080p"
        )
        #expect(p.activity == "fetching master")
        #expect(p.completed == 2)
        #expect(p.total == 5)
        #expect(p.refreshes == 3)
        #expect(p.aliasInScope == "video-1080p")
    }

    @Test("ActivityProgress optional fields default to nil")
    func activityProgressOptionalDefaults() {
        let p = ActivityProgress(activity: "validating media playlist", completed: 1)
        #expect(p.total == nil)
        #expect(p.refreshes == nil)
        #expect(p.aliasInScope == nil)
    }



    // MARK: - SessionEvent.activity

    @Test("SessionEvent.activity case carries ActivityProgress payload")
    func sessionEventActivityCase() {
        let progress = ActivityProgress(activity: "monitoring live", completed: 5)
        let event = SessionEvent.activity(progress)
        guard case .activity(let p) = event
        else {
            Issue.record("Expected .activity case")
            return
        }
        #expect(p.activity == "monitoring live")
        #expect(p.completed == 5)
    }
}

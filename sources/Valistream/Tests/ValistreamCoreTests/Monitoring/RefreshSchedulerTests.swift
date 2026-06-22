//
//  RefreshSchedulerTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite("RefreshScheduler", .tags(.monitoring))
struct RefreshSchedulerTests {
    @Test("first reload waits one full target duration")
    func initialDelayIsTargetDuration() {
        let scheduler = RefreshScheduler(targetDuration: .seconds(6))

        #expect(scheduler.initialDelay == .seconds(6))
    }

    @Test("a changed reload waits one full target duration")
    func changedReloadWaitsTargetDuration() {
        let scheduler = RefreshScheduler(targetDuration: .seconds(6))

        #expect(scheduler.nextDelay(didChange: true) == .seconds(6))
    }

    @Test("an unchanged reload backs off to half the target duration")
    func unchangedReloadBacksOffToHalf() {
        let scheduler = RefreshScheduler(targetDuration: .seconds(6))

        #expect(scheduler.nextDelay(didChange: false) == .seconds(3))
    }

    @Test("the backoff is never shorter than half the target duration", arguments: [4, 6, 10, 30])
    func neverReloadsFasterThanHalfTarget(targetSeconds: Int) {
        let target = Duration.seconds(targetSeconds)
        let scheduler = RefreshScheduler(targetDuration: target)

        #expect(scheduler.nextDelay(didChange: false) >= target / 2)
        #expect(scheduler.nextDelay(didChange: true) >= target / 2)
    }
}

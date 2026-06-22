//
//  StalenessDetectorTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite("StalenessDetector", .tags(.monitoring))
struct StalenessDetectorTests {
    private let detector = StalenessDetector()
    private let target = Duration.seconds(6)

    @Test("a fresh playlist produces no finding")
    func freshPlaylistIsClean() {
        #expect(detector.violation(staleFor: .seconds(6), targetDuration: target) == nil)
    }

    @Test("at exactly 1.5x the target duration it is still fresh")
    func warningBoundaryIsExclusive() {
        #expect(detector.violation(staleFor: .seconds(9), targetDuration: target) == nil)
    }

    @Test("past 1.5x the target duration it warns")
    func warnsPastWarningThreshold() {
        let violation = detector.violation(staleFor: .seconds(10), targetDuration: target)

        #expect(violation?.ruleId == "TOOL.staleness")
        #expect(violation?.severity == .warning)
    }

    @Test("at exactly 3x the target duration it is still a warning")
    func errorBoundaryIsExclusive() {
        #expect(detector.violation(staleFor: .seconds(18), targetDuration: target)?.severity == .warning)
    }

    @Test("past 3x the target duration it escalates to error")
    func escalatesToErrorPastErrorThreshold() {
        #expect(detector.violation(staleFor: .seconds(19), targetDuration: target)?.severity == .error)
    }

    @Test("the finding context carries the observed stale duration")
    func contextCarriesStaleDuration() throws {
        let violation = try #require(detector.violation(staleFor: .seconds(20), targetDuration: target))

        #expect(violation.context["staleSeconds"] == .double(20))
        #expect(violation.context["targetDurationSeconds"] == .double(6))
    }
}

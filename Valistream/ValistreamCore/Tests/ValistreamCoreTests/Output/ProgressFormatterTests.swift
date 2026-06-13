//
//  ProgressFormatterTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite(.tags(.output))
struct ProgressFormatterTests {

    // MARK: - Known total

    struct KnownTotalCase: CustomTestStringConvertible {
        let completed: Int
        let total: Int
        let expected: String
        var testDescription: String { "\(completed) of \(total)" }
    }

    @Test("formats N of M with percentage", arguments: [
        KnownTotalCase(completed: 0, total: 3,  expected: "validating — 0 of 3 (0%)"),
        KnownTotalCase(completed: 2, total: 5,  expected: "validating — 2 of 5 (40%)"),
        KnownTotalCase(completed: 5, total: 5,  expected: "validating — 5 of 5 (100%)"),
        KnownTotalCase(completed: 1, total: 10, expected: "validating — 1 of 10 (10%)"),
    ])
    func formatsKnownTotal(_ c: KnownTotalCase) {
        let p = ActivityProgress(activity: "validating", completed: c.completed, total: c.total)
        #expect(ProgressFormatter.format(p) == c.expected)
    }



    // MARK: - Refreshes

    @Test("formats 1 refresh as singular")
    func formatsOneRefreshAsSingular() {
        let p = ActivityProgress(activity: "monitoring", completed: 1, refreshes: 1)
        #expect(ProgressFormatter.format(p) == "monitoring — 1 refresh done")
    }

    @Test("formats N refreshes as plural", arguments: [2, 5, 12])
    func formatsPluralRefreshes(_ n: Int) {
        let p = ActivityProgress(activity: "monitoring", completed: n, refreshes: n)
        #expect(ProgressFormatter.format(p) == "monitoring — \(n) refreshes done")
    }

    @Test("refreshes field takes precedence over total")
    func refreshesTakesPrecedenceOverTotal() {
        let p = ActivityProgress(activity: "monitoring", completed: 3, total: 10, refreshes: 3)
        #expect(ProgressFormatter.format(p).contains("refreshes"))
    }



    // MARK: - Count only / bare activity

    @Test("formats count when total is unknown and completed > 0")
    func formatsCountOnly() {
        let p = ActivityProgress(activity: "fetching", completed: 3)
        #expect(ProgressFormatter.format(p) == "fetching — 3")
    }

    @Test("returns bare activity when completed is 0 and no total or refreshes")
    func returnsBareActivity() {
        let p = ActivityProgress(activity: "starting", completed: 0)
        #expect(ProgressFormatter.format(p) == "starting")
    }



    // MARK: - No ANSI codes

    @Test("formatted output never contains ANSI escape sequences (SC-004)")
    func noANSIEscapes() {
        let cases: [ActivityProgress] = [
            ActivityProgress(activity: "validating", completed: 2, total: 5),
            ActivityProgress(activity: "monitoring", completed: 3, refreshes: 3),
            ActivityProgress(activity: "fetching", completed: 1),
            ActivityProgress(activity: "starting", completed: 0),
        ]
        for p in cases {
            let result = ProgressFormatter.format(p)
            #expect(!result.contains("\u{1B}["), "ANSI escape found in: \(result)")
        }
    }
}

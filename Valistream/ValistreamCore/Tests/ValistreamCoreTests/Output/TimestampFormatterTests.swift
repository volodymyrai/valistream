//
//  TimestampFormatterTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite(.tags(.output))
struct TimestampFormatterTests {
    private let timeZone = TimeZone(secondsFromGMT: 7_200) ?? .gmt

    @Test("terminal timestamp uses fixed local 24-hour format with milliseconds")
    func terminalFormat() {
        #expect(TerminalTimestampFormatter.format(date, timeZone: timeZone) == "[17:06:40.500]")
    }

    @Test("report timestamp uses local ISO 8601 with milliseconds and offset")
    func reportFormat() {
        #expect(ReportTimestampFormatter.format(date, timeZone: timeZone) == "2025-06-15T17:06:40.500+02:00")
    }

    @Test("timestamped event preserves its occurrence instant")
    func timestampedEventPreservesOccurrence() {
        let event = TimestampedEvent(at: date, event: .stateChanged(.initializing))

        #expect(event.at == date)
    }

    private var date: Date { Date(timeIntervalSince1970: 1_750_000_000.5) }
}

//
//  TimestampedOutputTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation
import Testing
@testable import Valistream
import ValistreamCore

@Suite("Timestamped terminal output")
struct TimestampedOutputTests {
    @Test("every human line uses the recorded occurrence instant")
    func everyLineUsesOccurrenceTimestamp() {
        let recorder = OutputRecorder()
        let mode = TerminalOutputMode(
            isTTY: false,
            noColorEnv: false,
            noColorFlag: false,
            termIsDumb: false,
            environment: ["LANG": "C"],
            verbosity: .normal
        )
        var renderer = StatusRenderer(
            writer: TerminalWriter(
                mode: mode,
                terminalWidth: 80,
                output: recorder.writeStandardOutput,
                errorOutput: recorder.writeStandardError
            ),
            json: false,
            timeZone: .gmt
        )
        let earlier = Date(timeIntervalSince1970: 1_735_689_600.125)
        let later = Date(timeIntervalSince1970: 1_735_689_605.875)

        renderer.render(TimestampedEvent(at: later, event: .streamClassified(.live)))
        renderer.render(TimestampedEvent(at: earlier, event: .stateChanged(.initializing)))

        let lines = recorder.standardOutput.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.isEmpty == false)
        #expect(lines.allSatisfy { $0.firstMatch(of: /^\[\d{2}:\d{2}:\d{2}\.\d{3}\]/) != nil })
        #expect(lines.first?.hasPrefix("[00:00:05.875]") == true)
        #expect(lines.last?.hasPrefix("[00:00:00.125]") == true)
    }
}

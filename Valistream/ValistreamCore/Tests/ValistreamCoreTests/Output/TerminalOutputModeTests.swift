//
//  TerminalOutputModeTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite(.tags(.output))
struct TerminalOutputModeTests {

    // MARK: - colorEnabled gate

    @Test("styling on when all enabling conditions are met")
    func colorEnabledWhenAllConditionsMet() {
        let mode = TerminalOutputMode(isTTY: true, noColorEnv: false, noColorFlag: false, termIsDumb: false, verbosity: .normal)
        #expect(mode.colorEnabled == true)
    }

    @Test("styling off when stdout is not a TTY")
    func colorDisabledWhenNotTTY() {
        let mode = TerminalOutputMode(isTTY: false, noColorEnv: false, noColorFlag: false, termIsDumb: false, verbosity: .normal)
        #expect(mode.colorEnabled == false)
    }

    @Test("styling off when NO_COLOR environment variable is set")
    func colorDisabledWhenNoColorEnv() {
        let mode = TerminalOutputMode(isTTY: true, noColorEnv: true, noColorFlag: false, termIsDumb: false, verbosity: .normal)
        #expect(mode.colorEnabled == false)
    }

    @Test("styling off when --no-color flag is passed")
    func colorDisabledWhenNoColorFlag() {
        let mode = TerminalOutputMode(isTTY: true, noColorEnv: false, noColorFlag: true, termIsDumb: false, verbosity: .normal)
        #expect(mode.colorEnabled == false)
    }

    @Test("styling off when TERM=dumb")
    func colorDisabledWhenTermIsDumb() {
        let mode = TerminalOutputMode(isTTY: true, noColorEnv: false, noColorFlag: false, termIsDumb: true, verbosity: .normal)
        #expect(mode.colorEnabled == false)
    }



    // MARK: - Verbosity

    @Test("verbosity is stored correctly", arguments: Verbosity.allCases)
    func verbosityStoredCorrectly(verbosity: Verbosity) {
        let mode = TerminalOutputMode(isTTY: false, noColorEnv: false, noColorFlag: false, termIsDumb: false, verbosity: verbosity)
        #expect(mode.verbosity == verbosity)
    }
}

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
        let mode = makeMode()
        #expect(mode.colorEnabled == true)
    }

    @Test("styling off when stdout is not a TTY")
    func colorDisabledWhenNotTTY() {
        let mode = makeMode(isTTY: false)
        #expect(mode.colorEnabled == false)
    }

    @Test("styling off when NO_COLOR environment variable is set")
    func colorDisabledWhenNoColorEnv() {
        let mode = makeMode(noColorEnv: true)
        #expect(mode.colorEnabled == false)
    }

    @Test("styling off when --no-color flag is passed")
    func colorDisabledWhenNoColorFlag() {
        let mode = makeMode(noColorFlag: true)
        #expect(mode.colorEnabled == false)
    }

    @Test("styling off when TERM=dumb")
    func colorDisabledWhenTermIsDumb() {
        let mode = makeMode(termIsDumb: true)
        #expect(mode.colorEnabled == false)
    }



    // MARK: - Glyph style

    @Test(
        "UTF-8 locale variables enable Unicode markers",
        arguments: [
            ["LANG": "en_US.UTF-8"],
            ["LC_ALL": "C.UTF8"],
            ["LC_CTYPE": "nb_NO.utf-8"],
            ["LC_MESSAGES": "en_GB.UTF-8"],
        ]
    )
    func utf8LocaleUsesUnicode(environment: [String: String]) {
        #expect(makeMode(environment: environment).glyphStyle == .unicode)
    }

    @Test(
        "missing or non-UTF-8 locales use ASCII markers",
        arguments: [
            [:],
            ["LANG": "C"],
            ["LANG": "en_US.ISO-8859-1"],
        ]
    )
    func nonUTF8LocaleUsesASCII(environment: [String: String]) {
        #expect(makeMode(environment: environment).glyphStyle == .ascii)
    }

    @Test("TERM dumb forces ASCII markers even with UTF-8 locale")
    func dumbTerminalUsesASCII() {
        #expect(makeMode(termIsDumb: true).glyphStyle == .ascii)
    }



    // MARK: - Verbosity

    @Test("verbosity is stored correctly", arguments: Verbosity.allCases)
    func verbosityStoredCorrectly(verbosity: Verbosity) {
        let mode = makeMode(isTTY: false, verbosity: verbosity)
        #expect(mode.verbosity == verbosity)
    }



    // MARK: - Private

    private func makeMode(
        isTTY: Bool = true,
        noColorEnv: Bool = false,
        noColorFlag: Bool = false,
        termIsDumb: Bool = false,
        environment: [String: String] = ["LANG": "en_US.UTF-8"],
        verbosity: Verbosity = .normal
    ) -> TerminalOutputMode {
        TerminalOutputMode(
            isTTY: isTTY,
            noColorEnv: noColorEnv,
            noColorFlag: noColorFlag,
            termIsDumb: termIsDumb,
            environment: environment,
            verbosity: verbosity
        )
    }
}

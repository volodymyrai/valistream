//
//  RuleEngineTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite("RuleEngine", .tags(.validation))
struct RuleEngineTests {
    private let resource = URL(string: "https://example.com/m.m3u8")!

    private func context() -> RuleContext {
        let tokens = M3U8Tokenizer().tokenize("#EXTM3U\n#EXT-X-TARGETDURATION:6")
        let playlist = PlaylistBuilder().build(tokens: tokens, baseURL: resource)
        return RuleContext(playlist: playlist, tokens: tokens, resource: resource)
    }

    @Test("concatenates violations from every registered rule")
    func concatenatesViolations() {
        let engine = RuleEngine(rules: [StubRule(id: "A"), StubRule(id: "B")])

        let violations = engine.evaluate(context())

        #expect(violations.map(\.ruleId) == ["A", "B"])
    }

    @Test("returns no violations when no rule fires")
    func noViolations() {
        let engine = RuleEngine(rules: [StubRule(id: "A", fires: false)])

        #expect(engine.evaluate(context()).isEmpty)
    }
}

// MARK: - Test rule

private struct StubRule: ValidationRule {
    let id: String
    var fires = true
    let source: Finding.Source = .tool

    func evaluate(_ context: RuleContext) -> [RuleViolation] {
        guard fires else { return [] }
        return [RuleViolation(
            ruleId: id,
            source: source,
            severity: .info,
            category: .mediaPlaylist,
            message: "stub"
        )]
    }
}

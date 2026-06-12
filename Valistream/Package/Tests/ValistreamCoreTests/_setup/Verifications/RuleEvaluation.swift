//
//  RuleEvaluation.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
@testable import ValistreamCore

/// Shared helper that tokenizes, builds, and evaluates a playlist against a set of rules, returning
/// the raw violations for assertion. Used by every conformance and violation suite.
///
/// Example:
/// ```swift
/// let found = violations(in: text, rules: [RFC8216MediaRules()])
/// #expect(found.map(\.ruleId).contains("RFC8216.4.3.3.1"))
/// ```
/// - Parameters:
///   - text: The raw playlist body.
///   - rules: The rules to evaluate.
///   - baseURL: The resource URL used for resolution and as the finding resource.
///   - kind: Optional stream classification (some authoring rules are VOD-specific).
/// - Returns: The concatenated violations from all rules.
func violations(
    in text: String,
    rules: [any ValidationRule],
    baseURL: URL = URL(string: "https://ex.com/hls/m.m3u8")!,
    kind: StreamKind? = nil
) -> [RuleViolation] {
    let tokens = M3U8Tokenizer().tokenize(text)
    let playlist = PlaylistBuilder().build(tokens: tokens, baseURL: baseURL)
    let context = RuleContext(playlist: playlist, tokens: tokens, resource: baseURL, streamKind: kind)
    return RuleEngine(rules: rules).evaluate(context)
}

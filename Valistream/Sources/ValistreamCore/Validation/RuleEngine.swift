//
//  RuleEngine.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// The high-level classification of a stream (FR-005).
public enum StreamKind: String, Sendable, Equatable, Codable {
    case vod
    case event
    case live
}

/// Everything a rule needs to evaluate one playlist observation.
///
/// Rules read the structured ``Playlist`` for semantics and the lossless token stream for exact
/// line/tag locations (FR-008). They never mutate state — evaluation is pure, which keeps the rule
/// set trivially testable and shareable across one-shot validation and per-refresh re-validation
/// (constitution Principle IV).
public struct RuleContext: Sendable {
    public let playlist: Playlist
    public let tokens: [M3U8Token]
    public let resource: URL
    public let streamKind: StreamKind?
    public let refreshIndex: Int?

    public init(
        playlist: Playlist,
        tokens: [M3U8Token],
        resource: URL,
        streamKind: StreamKind? = nil,
        refreshIndex: Int? = nil
    ) {
        self.playlist = playlist
        self.tokens = tokens
        self.resource = resource
        self.streamKind = streamKind
        self.refreshIndex = refreshIndex
    }

    /// The first token matching a tag name, for locating a finding.
    public func firstToken(tag name: String) -> M3U8Token? {
        tokens.first { token in
            if case .tag(let tagName, _) = token.kind { return tagName == name }
            return false
        }
    }
}

/// A rule's observation, before the session assigns it an id, timestamp, and resource.
public struct RuleViolation: Sendable, Equatable {
    public let ruleId: String
    public let source: Finding.Source
    public let severity: Finding.Severity
    public let category: Finding.Category
    public let message: String
    public let location: Finding.Location?
    public let context: [String: Finding.ContextValue]

    public init(
        ruleId: String,
        source: Finding.Source,
        severity: Finding.Severity,
        category: Finding.Category,
        message: String,
        location: Finding.Location? = nil,
        context: [String: Finding.ContextValue] = [:]
    ) {
        self.ruleId = ruleId
        self.source = source
        self.severity = severity
        self.category = category
        self.message = message
        self.location = location
        self.context = context
    }
}

/// A single validation rule evaluated against one playlist observation.
public protocol ValidationRule: Sendable {
    /// The rule's stable identifier, e.g. `RFC8216.4.3.4.1` (FR-008).
    var id: String { get }

    /// The standard the rule derives from (FR-008).
    var source: Finding.Source { get }

    /// Evaluates the rule, returning zero or more violations.
    func evaluate(_ context: RuleContext) -> [RuleViolation]
}

/// Runs a collection of ``ValidationRule`` values over a ``RuleContext``.
public struct RuleEngine: Sendable {
    // MARK: - Lets & Vars

    public let rules: [any ValidationRule]



    // MARK: - Lifecycle

    public init(rules: [any ValidationRule]) {
        self.rules = rules
    }



    // MARK: - Public

    /// Evaluates every registered rule against the context, concatenating their violations.
    public func evaluate(_ context: RuleContext) -> [RuleViolation] {
        rules.flatMap { $0.evaluate(context) }
    }
}

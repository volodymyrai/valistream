//
//  Finding.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// One validation observation produced by a rule, a continuity check, or a delivery event.
///
/// `Finding` is the unit of output that reaches the report (`report.json`) and the live findings
/// stream (`findings.jsonl`). Its JSON encoding matches the `finding` definition in
/// `contracts/session-report.schema.json` (FR-008).
public struct Finding: Sendable, Equatable, Codable, Identifiable {
    // MARK: - Nested types

    /// The standard a rule derives from (FR-008).
    public enum Source: String, Sendable, Equatable, Codable {
        case rfc8216
        case appleAuthoring = "apple-authoring"
        case tool
    }

    /// Finding severity (FR-008).
    public enum Severity: String, Sendable, Equatable, Codable {
        case error
        case warning
        case info
    }

    /// The aspect of the stream a finding concerns (FR-008).
    public enum Category: String, Sendable, Equatable, Codable {
        case masterPlaylist
        case mediaPlaylist
        case continuity
        case delivery
        case segment
    }

    /// A position within an artifact: a 1-based line and/or the relevant tag name.
    public struct Location: Sendable, Equatable, Codable {
        public let line: Int?
        public let tag: String?

        public init(line: Int?, tag: String?) {
            self.line = line
            self.tag = tag
        }
    }

    /// A rule-specific context value. Encodes to its natural JSON scalar.
    public enum ContextValue: Sendable, Equatable, Codable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            }
            else if let value = try? container.decode(Int.self) {
                self = .int(value)
            }
            else if let value = try? container.decode(Double.self) {
                self = .double(value)
            }
            else {
                self = .string(try container.decode(String.self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .int(let value): try container.encode(value)
            case .double(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            }
        }
    }



    // MARK: - Lets & Vars

    public let id: String
    public let ruleId: String
    public let specRef: String?
    public let source: Source
    public let severity: Severity
    public let category: Category
    public let resource: URL
    public let location: Location?
    public let refreshIndex: Int?
    public let observedAt: Date
    public let message: String
    public let context: [String: ContextValue]



    // MARK: - Lifecycle

    public init(
        id: String,
        ruleId: String,
        source: Source,
        severity: Severity,
        category: Category,
        resource: URL,
        location: Location?,
        refreshIndex: Int?,
        observedAt: Date,
        message: String,
        context: [String: ContextValue]
    ) {
        self.id = id
        self.ruleId = ruleId
        self.specRef = SpecCatalog.reference(forRuleId: ruleId)
        self.source = source
        self.severity = severity
        self.category = category
        self.resource = resource
        self.location = location
        self.refreshIndex = refreshIndex
        self.observedAt = observedAt
        self.message = message
        self.context = context
    }



    // MARK: - Public

    /// JSON encoder configured to match the report schema (ISO-8601 dates, stable key order).
    public static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public static let prettyJSONEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return encoder
    }()

    /// JSON decoder matching ``jsonEncoder``.
    public static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

//
//  FindingTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite("Finding", .tags(.validation))
struct FindingTests {
    private let resource = URL(string: "https://example.com/hls/master.m3u8")!



    // MARK: - Encoding

    @Test("encodes enum values with the schema's string rawValues")
    func encodesRawValues() throws {
        #expect(Finding.Source.rfc8216.rawValue == "rfc8216")
        #expect(Finding.Source.appleAuthoring.rawValue == "apple-authoring")
        #expect(Finding.Source.tool.rawValue == "tool")
        #expect(Finding.Severity.error.rawValue == "error")
        #expect(Finding.Category.masterPlaylist.rawValue == "masterPlaylist")
    }

    @Test("round-trips through JSON encoding")
    func roundTrips() throws {
        let finding = Finding(
            id: "f1",
            ruleId: "RFC8216.4.3.4.1",
            source: .rfc8216,
            severity: .error,
            category: .masterPlaylist,
            resource: resource,
            location: Finding.Location(line: 12, tag: "#EXT-X-STREAM-INF"),
            refreshIndex: nil,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            message: "Missing required BANDWIDTH attribute",
            context: ["expected": .string("BANDWIDTH")]
        )

        let data = try Finding.jsonEncoder.encode(finding)
        let decoded = try Finding.jsonDecoder.decode(Finding.self, from: data)

        #expect(decoded == finding)
    }

    @Test("emits schema field names and string resource")
    func emitsSchemaFieldNames() throws {
        let finding = Finding(
            id: "f1",
            ruleId: "TOOL.delivery",
            source: .tool,
            severity: .warning,
            category: .delivery,
            resource: resource,
            location: nil,
            refreshIndex: 3,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            message: "slow response",
            context: [:]
        )

        let data = try Finding.jsonEncoder.encode(finding)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"source\":\"tool\""))
        #expect(json.contains("\"resource\":\"https://example.com/hls/master.m3u8\""))
        #expect(json.contains("\"refreshIndex\":3"))
    }

    @Test("omits the location key when there is no location")
    func omitsAbsentLocation() throws {
        let finding = Finding(
            id: "f1",
            ruleId: "TOOL.delivery",
            source: .tool,
            severity: .info,
            category: .delivery,
            resource: resource,
            location: nil,
            refreshIndex: nil,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            message: "info",
            context: [:]
        )

        let data = try Finding.jsonEncoder.encode(finding)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"location\"") == false)
    }
}

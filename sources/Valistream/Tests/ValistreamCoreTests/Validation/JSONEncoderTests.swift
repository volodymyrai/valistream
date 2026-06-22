//
//  JSONEncoderTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite("JSON encoders", .tags(.validation))
struct JSONEncoderTests {
    private let resource = URL(string: "https://example.com/hls/master.m3u8")!

    private func makeFinding() -> Finding {
        Finding(
            id: "f1",
            ruleId: "RFC8216.4.3.4.1",
            source: .rfc8216,
            severity: .error,
            category: .masterPlaylist,
            resource: resource,
            location: Finding.Location(line: 12, tag: "#EXT-X-STREAM-INF"),
            refreshIndex: 3,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            message: "Missing required BANDWIDTH attribute",
            context: ["expected": .string("BANDWIDTH")]
        )
    }


    // MARK: - prettyJSONEncoder

    @Test("prettyJSONEncoder produces multi-line output")
    func prettyEncoderIsMultiLine() throws {
        let data = try Finding.prettyJSONEncoder.encode(makeFinding())
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\n"))
    }

    @Test("prettyJSONEncoder has stable sortedKeys ordering")
    func prettyEncoderHasSortedKeys() throws {
        let data1 = try Finding.prettyJSONEncoder.encode(makeFinding())
        let data2 = try Finding.prettyJSONEncoder.encode(makeFinding())
        let json1 = try #require(String(data: data1, encoding: .utf8))
        let json2 = try #require(String(data: data2, encoding: .utf8))
        #expect(json1 == json2)
        // Keys appear in alphabetical order: category before context before id etc.
        let catRange = try #require(json1.range(of: "\"category\""))
        let ctxRange = try #require(json1.range(of: "\"context\""))
        let idRange = try #require(json1.range(of: "\"id\""))
        #expect(catRange.lowerBound < ctxRange.lowerBound)
        #expect(ctxRange.lowerBound < idRange.lowerBound)
    }

    @Test("prettyJSONEncoder and jsonEncoder decode to identical logical content")
    func bothEncodersDecodeIdentically() throws {
        let finding = makeFinding()
        let prettyData = try Finding.prettyJSONEncoder.encode(finding)
        let compactData = try Finding.jsonEncoder.encode(finding)
        let prettyDecoded = try Finding.jsonDecoder.decode(Finding.self, from: prettyData)
        let compactDecoded = try Finding.jsonDecoder.decode(Finding.self, from: compactData)
        #expect(prettyDecoded == compactDecoded)
        #expect(prettyDecoded == finding)
    }

    @Test("prettyJSONEncoder emits schema field names")
    func prettyEncoderEmitsSchemaFields() throws {
        let data = try Finding.prettyJSONEncoder.encode(makeFinding())
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"source\""))
        #expect(json.contains("\"ruleId\""))
        #expect(json.contains("\"specRef\""))
        #expect(json.contains("\"resource\""))
        #expect(json.contains("\"refreshIndex\""))
    }

    @Test("prettyJSONEncoder does not escape forward slashes")
    func prettyEncoderDoesNotEscapeSlashes() throws {
        let data = try Finding.prettyJSONEncoder.encode(makeFinding())
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("https://example.com/hls/master.m3u8"))
        #expect(json.contains("\\/") == false)
    }


    // MARK: - jsonEncoder (compact stream)

    @Test("jsonEncoder (stream) stays compact — single line per object")
    func compactEncoderIsSingleLine() throws {
        let data = try Finding.jsonEncoder.encode(makeFinding())
        let json = try #require(String(data: data, encoding: .utf8))
        let lines = json.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 1)
        #expect(json.contains("\n") == false)
    }

    @Test("jsonEncoder (stream) and prettyJSONEncoder are distinct objects")
    func encodersAreDistinct() {
        #expect(Finding.jsonEncoder !== Finding.prettyJSONEncoder)
    }
}

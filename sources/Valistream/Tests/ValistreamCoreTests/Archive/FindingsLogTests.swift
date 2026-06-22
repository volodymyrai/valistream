//
//  FindingsLogTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite(.tags(.archive))
struct FindingsLogTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "FindingsLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeFinding(id: String, severity: Finding.Severity = .error) -> Finding {
        Finding(
            id: id,
            ruleId: "RFC8216.test",
            source: .rfc8216,
            severity: severity,
            category: .mediaPlaylist,
            resource: URL(string: "https://ex.com/p.m3u8")!,
            location: nil,
            refreshIndex: nil,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            message: "test finding \(id)",
            context: [:]
        )
    }



    // MARK: - Init

    @Test("creates findings.jsonl file on init")
    func createsFile() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        _ = try FindingsLog(folder: tmp)

        let jsonlURL = tmp.appending(path: "findings.jsonl")
        #expect(FileManager.default.fileExists(atPath: jsonlURL.path(percentEncoded: false)))
    }



    // MARK: - Append

    @Test("appended finding is parseable as JSON")
    func appendedFindingParseable() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let log = try FindingsLog(folder: tmp)
        let finding = makeFinding(id: "f1")
        try log.append(finding)

        let content = try String(contentsOf: tmp.appending(path: "findings.jsonl"), encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 1)
        let decoded = try Finding.jsonDecoder.decode(Finding.self, from: Data(lines[0].utf8))
        #expect(decoded.id == "f1")
        #expect(decoded.ruleId == "RFC8216.test")
        #expect(decoded.specRef == "RFC 8216 §test")
    }

    @Test("multiple findings produce one JSON line each")
    func multipleFindings() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let log = try FindingsLog(folder: tmp)
        try log.append(makeFinding(id: "f1", severity: .error))
        try log.append(makeFinding(id: "f2", severity: .warning))
        try log.append(makeFinding(id: "f3", severity: .info))

        let content = try String(contentsOf: tmp.appending(path: "findings.jsonl"), encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 3)
        let ids = try lines.map { try Finding.jsonDecoder.decode(Finding.self, from: Data($0.utf8)).id }
        #expect(ids == ["f1", "f2", "f3"])
    }

    @Test("each line is independently parseable, simulating a mid-session abort")
    func eachLineIndependentlyParseable() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let log = try FindingsLog(folder: tmp)
        for i in 1...5 {
            try log.append(makeFinding(id: "f\(i)"))
        }

        let content = try String(contentsOf: tmp.appending(path: "findings.jsonl"), encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 5)
        for line in lines {
            #expect(throws: Never.self) {
                _ = try Finding.jsonDecoder.decode(Finding.self, from: Data(line.utf8))
            }
        }
    }

    @Test("file is non-empty after one append")
    func fileNonEmptyAfterAppend() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let log = try FindingsLog(folder: tmp)
        try log.append(makeFinding(id: "f1"))

        let attrs = try FileManager.default.attributesOfItem(atPath: tmp.appending(path: "findings.jsonl").path(percentEncoded: false))
        let size = attrs[.size] as? Int ?? 0
        #expect(size > 0)
    }
}

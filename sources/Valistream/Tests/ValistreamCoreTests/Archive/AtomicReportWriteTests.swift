//
//  AtomicReportWriteTests.swift
//  ValistreamCoreTests
//

import Testing
@testable import ValistreamCore
import Foundation

@Suite(.tags(.archive))
struct AtomicReportWriteTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtomicWriteTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeArchive(in dir: URL) throws -> SessionArchive {
        try SessionArchive(sessionID: "test-atomic", outputDir: dir)
    }

    // MARK: - Basic correctness

    @Test("writeAtomically writes complete data to target URL")
    func writesCompleteData() throws {
        let dir     = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = try makeArchive(in: dir)
        let target  = archive.sessionFolder.appendingPathComponent("report.json")
        let data    = #"{"schemaVersion":1}"#.data(using: .utf8)!

        try archive.writeAtomically(data, to: target)

        let read = try Data(contentsOf: target)
        #expect(read == data)
    }

    @Test("writeAtomically replaces existing file atomically")
    func replacesExistingFile() throws {
        let dir     = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = try makeArchive(in: dir)
        let target  = archive.sessionFolder.appendingPathComponent("report.json")

        let first  = "first content".data(using: .utf8)!
        let second = "second content".data(using: .utf8)!

        try archive.writeAtomically(first, to: target)
        try archive.writeAtomically(second, to: target)

        let read = try Data(contentsOf: target)
        #expect(read == second)
    }

    @Test("writeAtomically leaves no temp file after completion")
    func noTempFileAfterWrite() throws {
        let dir     = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = try makeArchive(in: dir)
        let target  = archive.sessionFolder.appendingPathComponent("report.json")
        let data    = "data".data(using: .utf8)!

        try archive.writeAtomically(data, to: target)

        let tmpURL = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).tmp")
        #expect(!FileManager.default.fileExists(atPath: tmpURL.path(percentEncoded: false)),
                "Temp file should be cleaned up after atomic replace")
    }

    @Test("writeAtomically throws when target directory is unwritable")
    func throwsOnUnwritableDirectory() throws {
        let dir     = try makeTempDir()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: dir.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: dir)
        }
        let archive = try makeArchive(in: dir)
        // Make session folder read-only
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: archive.sessionFolder.path(percentEncoded: false))
        let target = archive.sessionFolder.appendingPathComponent("report.json")
        let data   = "x".data(using: .utf8)!

        #expect(throws: (any Error).self) {
            try archive.writeAtomically(data, to: target)
        }
    }

    // MARK: - Concurrent safety (smoke test)

    @Test("writeAtomically with large payload writes complete valid content")
    func largePayloadIsComplete() throws {
        let dir     = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = try makeArchive(in: dir)
        let target  = archive.sessionFolder.appendingPathComponent("report.json")

        // 64 KB of JSON — larger than typical OS page to catch partial-write regressions.
        let value   = String(repeating: "x", count: 65_536)
        let json    = #"{"schemaVersion":1,"data":"\#(value)"}"#
        let data    = json.data(using: .utf8)!

        try archive.writeAtomically(data, to: target)

        let read    = try Data(contentsOf: target)
        #expect(read.count == data.count)
        #expect(throws: Never.self) {
            _ = try JSONSerialization.jsonObject(with: read)
        }
    }
}

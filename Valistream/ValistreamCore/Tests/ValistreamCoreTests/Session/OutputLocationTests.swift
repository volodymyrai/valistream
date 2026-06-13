//
//  OutputLocationTests.swift
//  ValistreamCoreTests
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite("OutputLocation", .tags(.session), .timeLimit(.minutes(1)))
struct OutputLocationTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "OutputLocationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }



    // MARK: - Base → sessionFolder

    @Test("explicit base produces sessionFolder = base/sessionID")
    func explicitBaseProducesSessionFolder() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let loc = try OutputLocation.resolve(outputDir: tmp, sessionID: "abc123")
        #expect(loc.baseDirectory.standardizedFileURL == tmp.standardizedFileURL)
        #expect(loc.sessionFolder == tmp.appending(path: "abc123", directoryHint: .isDirectory).standardizedFileURL)
    }

    @Test("two different session IDs produce non-equal session folders")
    func uniqueSessionFolders() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let loc1 = try OutputLocation.resolve(outputDir: tmp, sessionID: "s-001")
        let loc2 = try OutputLocation.resolve(outputDir: tmp, sessionID: "s-002")
        #expect(loc1.sessionFolder != loc2.sessionFolder)
    }



    // MARK: - Relative path resolution

    @Test("relative outputDir is resolved to an absolute path")
    func relativePathResolvedToAbsolute() throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let relative = URL(fileURLWithPath: "./", isDirectory: true)
            .appending(path: tmp.lastPathComponent, directoryHint: .isDirectory)
        // relative will start without '/' only if we build it as relative
        let loc = try OutputLocation.resolve(
            outputDir: URL(fileURLWithPath: ".", isDirectory: true),
            sessionID: "rel-test"
        )
        #expect(loc.baseDirectory.path.hasPrefix("/"))
        _ = relative // suppress warning
    }



    // MARK: - Default base

    @Test("defaultBase() contains valistream/sessions path components")
    func defaultBaseContainsExpectedComponents() {
        let base = OutputLocation.defaultBase()
        let path = base.path
        #expect(path.contains("valistream"))
        #expect(path.contains("sessions"))
        #expect(path.hasPrefix("/"))
    }



    // MARK: - Writability pre-flight

    @Test("unwritable base directory throws an error", .tags(.edgeCase))
    func unwritableBaseThrows() throws {
        let tmp = try makeTempDir()
        defer {
            // Restore permissions so cleanup succeeds.
            try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: tmp.path)
            try? FileManager.default.removeItem(at: tmp)
        }

        // Make the directory read+execute only — writes will be denied.
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o555)],
            ofItemAtPath: tmp.path
        )

        #expect(throws: (any Error).self) {
            _ = try OutputLocation.resolve(outputDir: tmp, sessionID: "blocked")
        }
    }
}

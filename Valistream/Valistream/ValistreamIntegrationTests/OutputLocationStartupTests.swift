//
//  OutputLocationStartupTests.swift
//  ValistreamIntegrationTests
//

import Foundation
import Testing
import ValistreamCore

@Suite("Output location startup", .timeLimit(.minutes(1)))
struct OutputLocationStartupTests {
    private let masterURL = URL(string: "https://ex.com/master.m3u8")!
    private let mediaURL  = URL(string: "https://ex.com/v0.m3u8")!

    private let master = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1280000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720
        v0.m3u8
        """

    private let vodMedia = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:6.0,
        seg0.ts
        #EXT-X-ENDLIST
        """

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "OutputLocationStartupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }



    // MARK: - Folder resolved before fetch

    @Test("sessionFolderResolved event fires before stateChanged(.fetchingMaster)")
    func folderResolvedBeforeFetch() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(masterURL, body: master)
        fetcher.stub(mediaURL, body: vodMedia)
        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let session = ValidationSession(
            inputURL: masterURL, config: config, fetcher: fetcher, id: "test-loc"
        )

        var events: [SessionEvent] = []
        let eventsStream = session.events

        let runTask = Task { await session.run() }
        let collectTask = Task {
            for await event in eventsStream { events.append(event) }
        }
        await runTask.value
        await collectTask.value

        let folderIdx = events.firstIndex(where: {
            if case .sessionFolderResolved = $0 { return true }
            return false
        })
        let fetchIdx = events.firstIndex(where: {
            if case .stateChanged(.fetchingMaster) = $0 { return true }
            return false
        })
        let folderIdx2 = try #require(folderIdx, "expected sessionFolderResolved event")
        let fetchIdx2  = try #require(fetchIdx,  "expected stateChanged(.fetchingMaster) event")
        #expect(folderIdx2 < fetchIdx2)
    }

    @Test("resolved sessionFolder URL matches session.sessionFolderURL")
    func resolvedFolderMatchesSessionFolder() async throws {
        let tmp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(masterURL, body: master)
        fetcher.stub(mediaURL, body: vodMedia)
        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let session = ValidationSession(
            inputURL: masterURL, config: config, fetcher: fetcher, id: "test-match"
        )

        await session.run()

        let sessionFolder = await session.sessionFolderURL
        #expect(sessionFolder != nil)
        #expect(sessionFolder?.lastPathComponent == "test-match")
    }



    // MARK: - Unwritable output → fail fast

    @Test("unwritable outputDir causes state .failed before any fetch")
    func unwritableOutputFailsFast() async throws {
        let tmp = try makeTempDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: tmp.path)
            try? FileManager.default.removeItem(at: tmp)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o555)],
            ofItemAtPath: tmp.path
        )

        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(masterURL, body: master)
        fetcher.stub(mediaURL, body: vodMedia)
        let config = SessionConfig(outputDir: tmp, nonInteractive: true, archiveEnabled: true)
        let session = ValidationSession(
            inputURL: masterURL, config: config, fetcher: fetcher, id: "test-fail"
        )

        await session.run()

        let state = await session.state
        let failureMessage = await session.failureMessage
        #expect(state == .failed)
        #expect(failureMessage != nil)
        // No fetches should have happened.
        #expect(fetcher.fetchCount(for: masterURL) == 0)
    }
}

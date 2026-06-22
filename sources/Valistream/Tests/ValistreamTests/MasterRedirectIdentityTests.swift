//
//  MasterRedirectIdentityTests.swift
//  ValistreamIntegrationTests
//

import Testing
@testable import ValistreamCore
import Foundation

/// Regression for bug `master-2-wrong-alias`: when the master URL redirects, the master was
/// registered under two URLs (the requested URL and the redirected final URL), yielding the dedup
/// alias `master_2` and a broken evidence join that printed
/// `[WARN] master_2_0 — no body captured for master_2`. The fix keys archive identity and the master
/// alias on the requested URL, matching findings, roster, and discovery-time registration.
@Suite("Master redirect identity", .timeLimit(.minutes(1)))
struct MasterRedirectIdentityTests {
    /// One video variant addressed absolutely, so the redirect's effect on base-URL resolution does
    /// not change which media URL is fetched — the test isolates the master identity bug.
    private static let master = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028"
        https://example.com/live/video-1080p-avc1.m3u8
        """

    private static let media = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:6.0,
        seg0.ts
        #EXT-X-ENDLIST
        """

    @Test("redirecting master keeps alias 'master' and resolves evidence (no master_2)")
    func redirectingMasterKeepsIdentity() async throws {
        let requestedMaster = URL(string: "https://example.com/live/master.m3u8")!
        let finalMaster = URL(string: "https://example.com/live/v2/master.m3u8")!
        let videoURL = URL(string: "https://example.com/live/video-1080p-avc1.m3u8")!

        let outputDir = FileManager.default.temporaryDirectory
            .appending(path: "MasterRedirectIdentityTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let config = SessionConfig(outputDir: outputDir, nonInteractive: true, archiveEnabled: true)
        let harness = LiveSessionHarness(input: requestedMaster, config: config)
        let hops = [RedirectHop(url: requestedMaster, statusCode: 301, headers: ["Location": finalMaster.absoluteString])]
        harness.fetcher.stub(requestedMaster, reply: .redirect(finalURL: finalMaster, finalBody: Self.master, hops: hops))
        harness.fetcher.stub(videoURL, body: Self.media)

        await harness.start()
        await harness.finish()

        // 1. Master alias is 'master', keyed on the requested URL — never the dedup 'master_2'.
        let aliases = await harness.session.aliasRegistry
        #expect(aliases.alias(for: requestedMaster)?.alias == "master")
        #expect(aliases.all.map(\.alias).contains("master_2") == false,
                "Redirect must not create a dedup master alias: \(aliases.all.map(\.alias))")

        // 2. The archive entry for the master is keyed on the requested URL, not the redirected final URL.
        let folder = try #require(await harness.session.sessionFolderURL)
        let artifactIndex = try Self.readArtifactIndex(at: folder)
        #expect(artifactIndex.contains { $0.url == requestedMaster })
        #expect(artifactIndex.contains { $0.url == finalMaster } == false)

        // 3. A master finding resolves to its archived body — no "no body captured" WARN.
        let resolver = EvidenceResolver()
        let finding = Finding(
            id: "f-master",
            ruleId: "TOOL.redirect-test",
            source: .tool,
            severity: .warning,
            category: .delivery,
            resource: requestedMaster,
            location: nil,
            refreshIndex: 0,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            message: "master finding",
            context: [:]
        )
        let reference = resolver.resolve(finding, aliases: aliases, artifactIndex: artifactIndex)
        #expect(reference.availablePaths.isEmpty == false, "Master evidence must resolve after redirect")
        #expect(reference.terminalMessage(for: finding).contains("no body captured") == false)
    }

    // MARK: - Private

    private static func readArtifactIndex(at folder: URL) throws -> [SessionArchive.IndexEntry] {
        let data = try Data(contentsOf: folder.appending(path: "report.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let raw = try #require(object["artifactIndex"] as? [[String: Any]])
        return try raw.map { entry in
            let urlString = try #require(entry["url"] as? String)
            let url = try #require(URL(string: urlString))
            let requestId = try #require(entry["requestId"] as? String)
            let bodyPath = try #require(entry["bodyPath"] as? String)
            let metaPath = try #require(entry["metaPath"] as? String)

            return SessionArchive.IndexEntry(requestId: requestId, url: url, bodyPath: bodyPath, metaPath: metaPath)
        }
    }
}

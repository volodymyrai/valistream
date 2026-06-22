//
//  DeliveryFailureTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
import ValistreamCore

@Suite("Delivery failures")
struct DeliveryFailureTests {
    private let base = "https://ex.com/hls/"

    private func makeSession(input: URL, fetcher: ScriptedStreamFetcher) -> ValidationSession {
        ValidationSession(
            inputURL: input,
            config: SessionConfig(nonInteractive: true),
            fetcher: fetcher,
            id: "test",
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private let conformantMedia = """
    #EXTM3U
    #EXT-X-TARGETDURATION:6
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXTINF:6.0,
    seg0.ts
    #EXT-X-ENDLIST
    """



    // MARK: - Fatal initial-fetch failures

    @Test("records a delivery finding and fails when the master is unreachable")
    func unreachableMaster() async throws {
        let master = URL(string: base + "master.m3u8")!
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(master, reply: .transportError("could not connect to host"))

        let session = makeSession(input: master, fetcher: fetcher)
        await session.run()

        let state = await session.state
        let findings = await session.recordedFindings
        #expect(state == .failed)
        #expect(findings.contains { $0.ruleId == "TOOL.delivery" && $0.category == .delivery && $0.severity == .error })
    }

    @Test("records a delivery finding when the master body is not a playlist")
    func nonPlaylistMaster() async throws {
        let master = URL(string: base + "master.m3u8")!
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(master, body: "<html>not a playlist</html>")

        let session = makeSession(input: master, fetcher: fetcher)
        await session.run()

        let state = await session.state
        let findings = await session.recordedFindings
        #expect(state == .failed)
        #expect(findings.contains { $0.message.contains("not an M3U8 playlist") })
    }

    @Test("records a delivery finding for an HTTP error status")
    func httpErrorMaster() async throws {
        let master = URL(string: base + "master.m3u8")!
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(master, body: "", status: 503)

        let session = makeSession(input: master, fetcher: fetcher)
        await session.run()

        let findings = await session.recordedFindings
        #expect(findings.contains { $0.ruleId == "TOOL.delivery" && $0.message.contains("503") })
    }



    // MARK: - Non-fatal media failures

    @Test("continues after a media playlist 404, still completing the session")
    func mediaFailureContinues() async throws {
        let master = URL(string: base + "master.m3u8")!
        let masterText = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1280000,CODECS="avc1.4d401f",RESOLUTION=1280x720,AVERAGE-BANDWIDTH=1200000
        v720/index.m3u8
        """
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(master, body: masterText)
        fetcher.stub(URL(string: base + "v720/index.m3u8")!, body: "", status: 404)

        let session = makeSession(input: master, fetcher: fetcher)
        await session.run()

        let state = await session.state
        let findings = await session.recordedFindings
        #expect(state == .completed)
        #expect(findings.contains { $0.category == .delivery && $0.message.contains("404") })
    }



    // MARK: - Redirects and direct media input

    @Test("records the redirect chain on a fetch")
    func redirectChainRecorded() async {
        let url = URL(string: base + "master.m3u8")!
        let fetcher = ScriptedStreamFetcher()
        let hops = [
            RedirectHop(url: url, statusCode: 301, headers: ["Location": base + "v2/master.m3u8"]),
            RedirectHop(url: URL(string: base + "v2/master.m3u8")!, statusCode: 302, headers: [:]),
        ]
        fetcher.stub(url, reply: .redirect(finalURL: URL(string: base + "v2/master.m3u8")!, finalBody: conformantMedia, hops: hops))

        let result = await fetcher.fetch(url)

        #expect(result.metadata.redirectChain.count == 2)
        #expect(result.metadata.redirectChain.first?.statusCode == 301)
    }

    @Test("validates a media playlist supplied directly as input")
    func directMediaInput() async throws {
        let media = URL(string: base + "media.m3u8")!
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(media, body: conformantMedia)

        let session = makeSession(input: media, fetcher: fetcher)
        await session.run()

        let state = await session.state
        let kind = await session.classification
        #expect(state == .completed)
        #expect(kind == .vod)
    }
}

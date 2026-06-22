//
//  OneShotSessionTests.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
import ValistreamCore

@Suite("One-shot session")
struct OneShotSessionTests {
    private let base = "https://ex.com/hls/"

    private func makeSession(input: URL, fetcher: ScriptedStreamFetcher) -> ValidationSession {
        ValidationSession(
            inputURL: input,
            config: SessionConfig(nonInteractive: true),
            fetcher: fetcher,
            id: "test-session",
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }



    // MARK: - Happy path

    @Test("validates a conformant VOD stream with zero error/warning findings")
    func conformantVOD() async throws {
        let master = URL(string: base + "master.m3u8")!
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(master, body: Fixtures.conformantMaster)
        fetcher.stub(URL(string: base + "v720/index.m3u8")!, body: Fixtures.conformantMedia)
        fetcher.stub(URL(string: base + "audio/en.m3u8")!, body: Fixtures.conformantMedia)
        fetcher.stub(URL(string: base + "iframe/720.m3u8")!, body: Fixtures.conformantMedia)

        let session = makeSession(input: master, fetcher: fetcher)
        await session.run()

        let state = await session.state
        let kind = await session.classification
        let findings = await session.recordedFindings

        #expect(state == .completed)
        #expect(kind == .vod)
        #expect(findings.count(where: { $0.severity == .error }) == 0)
        #expect(findings.count(where: { $0.severity == .warning }) == 0)
        #expect(fetcher.fetchCount(for: master) == 1)
        #expect(fetcher.fetchCount(for: URL(string: base + "v720/index.m3u8")!) == 1)
    }



    // MARK: - Info findings

    @Test("emits an info finding for low-latency HLS tags")
    func lowLatencyInfoFinding() async throws {
        let media = URL(string: base + "ll.m3u8")!
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(media, body: Fixtures.lowLatencyMedia)

        let session = makeSession(input: media, fetcher: fetcher)
        await session.run()

        let findings = await session.recordedFindings
        #expect(findings.contains { $0.ruleId == "TOOL.low-latency" && $0.severity == .info })
    }

    @Test("emits an info finding for encrypted streams without decrypting")
    func encryptionInfoFinding() async throws {
        let media = URL(string: base + "enc.m3u8")!
        let fetcher = ScriptedStreamFetcher()
        fetcher.stub(media, body: Fixtures.encryptedMedia)

        let session = makeSession(input: media, fetcher: fetcher)
        await session.run()

        let findings = await session.recordedFindings
        #expect(findings.contains { $0.ruleId == "TOOL.encryption" && $0.severity == .info })
    }
}

// MARK: - Fixtures

private enum Fixtures {
    static let conformantMaster = """
    #EXTM3U
    #EXT-X-INDEPENDENT-SEGMENTS
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",NAME="English",LANGUAGE="en",DEFAULT=YES,AUTOSELECT=YES,URI="audio/en.m3u8"
    #EXT-X-STREAM-INF:BANDWIDTH=1280000,AVERAGE-BANDWIDTH=1100000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720,AUDIO="aud1"
    v720/index.m3u8
    #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=120000,RESOLUTION=1280x720,CODECS="avc1.4d401f",URI="iframe/720.m3u8"
    """

    static let conformantMedia = """
    #EXTM3U
    #EXT-X-VERSION:7
    #EXT-X-TARGETDURATION:6
    #EXT-X-MEDIA-SEQUENCE:0
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXTINF:6.0,
    seg0.ts
    #EXTINF:6.0,
    seg1.ts
    #EXT-X-ENDLIST
    """

    static let lowLatencyMedia = """
    #EXTM3U
    #EXT-X-TARGETDURATION:4
    #EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,PART-HOLD-BACK=1.0
    #EXT-X-PART-INF:PART-TARGET=0.33
    #EXTINF:4.0,
    seg0.ts
    #EXT-X-ENDLIST
    """

    static let encryptedMedia = """
    #EXTM3U
    #EXT-X-TARGETDURATION:6
    #EXT-X-KEY:METHOD=AES-128,URI="https://ex.com/key"
    #EXTINF:6.0,
    seg0.ts
    #EXT-X-ENDLIST
    """
}

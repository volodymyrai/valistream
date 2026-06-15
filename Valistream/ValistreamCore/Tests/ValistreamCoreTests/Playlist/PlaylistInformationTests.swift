//
//  PlaylistInformationTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite(.tags(.playlist))
struct PlaylistInformationTests {
    private let baseURL = URL(string: "https://example.com/hls/master.m3u8")!
    private let builder = PlaylistBuilder()
    private let tokenizer = M3U8Tokenizer()

    @Test("master information derives the required declared fields")
    func masterFields() throws {
        let playlist = build("""
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-INDEPENDENT-SEGMENTS
            #EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,KEYFORMAT="com.apple.streamingkeydelivery"
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",URI="audio/en.m3u8"
            #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",URI="subs/en.m3u8"
            #EXT-X-STREAM-INF:BANDWIDTH=1000000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720,FRAME-RATE=25.0
            video/720.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=3000000,CODECS="avc1.640028,mp4a.40.2",RESOLUTION=1920x1080,FRAME-RATE=50.0
            video/1080.m3u8
            #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=120000,RESOLUTION=1280x720,CODECS="avc1.4d401f",URI="iframe/720.m3u8"
            """)

        let information = PlaylistInformation.build(playlistID: "master", playlist: playlist)
        let master = try #require(information.master)

        #expect(information.kind == .master)
        #expect(master.hlsVersion == 7)
        #expect(master.independentSegments)
        #expect(master.variantCount == 2)
        #expect(master.uniqueMediaPlaylistCount == 2)
        #expect(master.renditionCountsByType == ["AUDIO": 1, "SUBTITLES": 1])
        #expect(master.iFrameStreamCount == 1)
        #expect(master.distinctResolutions == ["1280x720", "1920x1080"])
        #expect(master.distinctCodecs == ["avc1.4d401f", "avc1.640028", "mp4a.40.2"])
        #expect(master.minimumBandwidth == 1_000_000)
        #expect(master.maximumBandwidth == 3_000_000)
        #expect(master.minimumFrameRate == 25)
        #expect(master.maximumFrameRate == 50)
        #expect(master.sessionProtection == .drm(keyFormat: "com.apple.streamingkeydelivery"))
    }

    @Test("media information uses only the media playlist first snapshot")
    func mediaFields() throws {
        let playlist = build("""
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-TARGETDURATION:8
            #EXT-X-MEDIA-SEQUENCE:42
            #EXT-X-DISCONTINUITY-SEQUENCE:3
            #EXT-X-INDEPENDENT-SEGMENTS
            #EXT-X-KEY:METHOD=AES-128,URI="key.bin"
            #EXTINF:4.0,
            segment0.ts
            #EXT-X-DISCONTINUITY
            #EXT-X-BYTERANGE:1000@0
            #EXTINF:6.0,
            segment1.m4s
            #EXT-X-PROGRAM-DATE-TIME:2026-06-15T12:00:00.000Z
            #EXTINF:8.0,
            segment2.m4s
            #EXT-X-ENDLIST
            """)

        let information = PlaylistInformation.build(playlistID: "video-1", playlist: playlist, streamKind: .vod)
        let media = try #require(information.media)

        #expect(information.kind == .media)
        #expect(media.playlistType == "VOD")
        #expect(media.hlsVersion == 7)
        #expect(media.segmentCount == 3)
        #expect(media.totalListedDuration == 18)
        #expect(media.targetDuration == 8)
        #expect(media.medianSegmentDuration == 6)
        #expect(media.minimumSegmentDuration == 4)
        #expect(media.maximumSegmentDuration == 8)
        #expect(media.mediaSequence == 42)
        #expect(media.discontinuitySequence == 3)
        #expect(media.discontinuityCount == 1)
        #expect(media.endList)
        #expect(media.independentSegments)
        #expect(media.iFramesOnly == false)
        #expect(media.segmentFormats == ["m4s", "ts"])
        #expect(media.byteRangeUsed)
        #expect(media.programDateTimeAvailable)
        #expect(media.protection == .encryptedAES128)
    }

    @Test("missing declarations remain distinguishable")
    func missingValues() throws {
        let playlist = build("""
            #EXTM3U
            #EXTINF:6.0,
            segment
            """)

        let information = PlaylistInformation.build(playlistID: "media", playlist: playlist)
        let media = try #require(information.media)

        #expect(media.hlsVersion == nil)
        #expect(media.targetDuration == nil)
        #expect(media.segmentFormats.isEmpty)
        #expect(media.playlistType == "Unknown")
    }

    private func build(_ source: String) -> Playlist {
        builder.build(tokens: tokenizer.tokenize(source), baseURL: baseURL)
    }
}

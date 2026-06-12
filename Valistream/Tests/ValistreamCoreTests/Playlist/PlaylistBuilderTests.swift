//
//  PlaylistBuilderTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite("PlaylistBuilder", .tags(.playlist))
struct PlaylistBuilderTests {
    private let builder = PlaylistBuilder()
    private let tokenizer = M3U8Tokenizer()
    private let base = URL(string: "https://example.com/hls/master.m3u8")!



    // MARK: - Detection

    @Test("detects a master playlist from EXT-X-STREAM-INF")
    func detectsMaster() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
        v720/index.m3u8
        """
        let playlist = builder.build(tokens: tokenizer.tokenize(text), baseURL: base)

        let master = try #require(playlist.master)
        #expect(playlist.kind == .master)
        #expect(master.variants.count == 1)
    }

    @Test("detects a media playlist from EXTINF / EXT-X-TARGETDURATION")
    func detectsMedia() throws {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:10
        #EXTINF:6.0,
        seg10.ts
        #EXT-X-ENDLIST
        """
        let playlist = builder.build(tokens: tokenizer.tokenize(text), baseURL: base)

        let media = try #require(playlist.media)
        #expect(playlist.kind == .media)
        #expect(media.targetDuration == 6)
        #expect(media.mediaSequence == 10)
        #expect(media.segments.count == 1)
        #expect(media.hasEndList)
    }



    // MARK: - Attribute extraction

    @Test("extracts variant stream attributes")
    func extractsVariantAttributes() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1280000,AVERAGE-BANDWIDTH=1100000,RESOLUTION=1280x720,FRAME-RATE=29.970,CODECS="avc1.4d401f",AUDIO="aud1"
        v720/index.m3u8
        """
        let master = try #require(builder.build(tokens: tokenizer.tokenize(text), baseURL: base).master)
        let variant = try #require(master.variants.first)

        #expect(variant.bandwidth == 1_280_000)
        #expect(variant.averageBandwidth == 1_100_000)
        #expect(variant.resolution == Resolution(width: 1280, height: 720))
        #expect(variant.frameRate == 29.970)
        #expect(variant.codecs == ["avc1.4d401f"])
        #expect(variant.audioGroupID == "aud1")
    }

    @Test("extracts EXT-X-MEDIA renditions")
    func extractsRenditions() throws {
        let text = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",NAME="English",LANGUAGE="en",DEFAULT=YES,AUTOSELECT=YES,URI="audio/en.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=1280000,AUDIO="aud1"
        v720/index.m3u8
        """
        let master = try #require(builder.build(tokens: tokenizer.tokenize(text), baseURL: base).master)
        let rendition = try #require(master.renditions.first)

        #expect(rendition.type == "AUDIO")
        #expect(rendition.groupID == "aud1")
        #expect(rendition.name == "English")
        #expect(rendition.language == "en")
        #expect(rendition.isDefault)
    }

    @Test("extracts EXTINF duration and title")
    func extractsSegmentInfo() throws {
        let text = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXTINF:5.005,intro
        seg0.ts
        """
        let media = try #require(builder.build(tokens: tokenizer.tokenize(text), baseURL: base).media)
        let segment = try #require(media.segments.first)

        #expect(abs(segment.duration - 5.005) < 0.0001)
        #expect(segment.title == "intro")
    }



    // MARK: - URI resolution

    @Test("resolves relative variant URIs against the base URL")
    func resolvesRelativeURIs() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1280000
        v720/index.m3u8
        """
        let master = try #require(builder.build(tokens: tokenizer.tokenize(text), baseURL: base).master)

        #expect(master.variants.first?.uri == URL(string: "https://example.com/hls/v720/index.m3u8"))
    }

    @Test("keeps absolute URIs unchanged")
    func keepsAbsoluteURIs() throws {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1280000
        https://cdn.example.net/v720/index.m3u8
        """
        let master = try #require(builder.build(tokens: tokenizer.tokenize(text), baseURL: base).master)

        #expect(master.variants.first?.uri == URL(string: "https://cdn.example.net/v720/index.m3u8"))
    }
}

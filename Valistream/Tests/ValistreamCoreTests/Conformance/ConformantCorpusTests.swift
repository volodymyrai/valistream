//
//  ConformantCorpusTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite("Conformant corpus", .tags(.validation))
struct ConformantCorpusTests {
    private let allRules: [any ValidationRule] = [
        RFC8216MasterRules(),
        RFC8216MediaRules(),
        AppleAuthoringRules(),
    ]

    @Test("conformant master playlist produces no error or warning findings")
    func conformantMaster() {
        let found = violations(in: Corpus.master, rules: allRules, kind: .vod)

        #expect(found.count(where: { $0.severity == .error }) == 0)
        #expect(found.count(where: { $0.severity == .warning }) == 0)
    }

    @Test("conformant media playlists produce no error or warning findings", arguments: [
        Corpus.vodMedia, Corpus.iframeMedia,
    ])
    func conformantMedia(_ text: String) {
        let found = violations(in: text, rules: allRules, kind: .vod)

        #expect(found.count(where: { $0.severity == .error }) == 0)
        #expect(found.count(where: { $0.severity == .warning }) == 0)
    }
}

// MARK: - Corpus

private enum Corpus {
    static let master = """
    #EXTM3U
    #EXT-X-INDEPENDENT-SEGMENTS
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud1",NAME="English",LANGUAGE="en",DEFAULT=YES,AUTOSELECT=YES,URI="audio/en.m3u8"
    #EXT-X-STREAM-INF:BANDWIDTH=1280000,AVERAGE-BANDWIDTH=1100000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720,AUDIO="aud1"
    v720/index.m3u8
    #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=120000,RESOLUTION=1280x720,CODECS="avc1.4d401f",URI="iframe/720.m3u8"
    """

    static let vodMedia = """
    #EXTM3U
    #EXT-X-VERSION:7
    #EXT-X-TARGETDURATION:6
    #EXT-X-MEDIA-SEQUENCE:0
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXTINF:6.0,
    seg0.ts
    #EXTINF:5.0,
    seg1.ts
    #EXT-X-ENDLIST
    """

    static let iframeMedia = """
    #EXTM3U
    #EXT-X-VERSION:7
    #EXT-X-TARGETDURATION:6
    #EXT-X-I-FRAMES-ONLY
    #EXTINF:6.0,
    #EXT-X-BYTERANGE:1024@0
    seg0.ts
    #EXT-X-ENDLIST
    """
}

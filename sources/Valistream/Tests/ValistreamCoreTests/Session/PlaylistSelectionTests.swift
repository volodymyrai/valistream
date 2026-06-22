//
//  PlaylistSelectionTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite("PlaylistSelection", .tags(.session))
struct PlaylistSelectionTests {
    private let candidates: [PlaylistSelection.Candidate] = [
        .init(id: "v720", role: .variant, url: URL(string: "https://ex.com/v720/index.m3u8")!),
        .init(id: "v1080", role: .variant, url: URL(string: "https://ex.com/v1080/index.m3u8")!),
        .init(id: "aud-en", role: .audio, url: URL(string: "https://ex.com/audio/en.m3u8")!, groupID: "aud1", name: "English"),
        .init(id: "sub-no", role: .subtitles, url: URL(string: "https://ex.com/sub/no.m3u8")!, groupID: "subs", name: "Norsk"),
    ]

    @Test("nil patterns select every playlist")
    func nilPatternsSelectAll() {
        let resolved = PlaylistSelection.resolve(candidates, patterns: nil)

        #expect(resolved == candidates)
    }

    @Test("an empty pattern list selects every playlist")
    func emptyPatternsSelectAll() {
        #expect(PlaylistSelection.resolve(candidates, patterns: []) == candidates)
    }

    @Test("a pattern matches the playlist id")
    func matchesByID() {
        let resolved = PlaylistSelection.resolve(candidates, patterns: ["v720"])

        #expect(resolved.map(\.id) == ["v720"])
    }

    @Test("a pattern matches the rendition group id")
    func matchesByGroupID() {
        let resolved = PlaylistSelection.resolve(candidates, patterns: ["aud1"])

        #expect(resolved.map(\.id) == ["aud-en"])
    }

    @Test("a pattern matches the rendition name case-insensitively")
    func matchesByNameCaseInsensitively() {
        let resolved = PlaylistSelection.resolve(candidates, patterns: ["english"])

        #expect(resolved.map(\.id) == ["aud-en"])
    }

    @Test("a pattern matches a URL substring")
    func matchesByURLSubstring() {
        let resolved = PlaylistSelection.resolve(candidates, patterns: ["/sub/"])

        #expect(resolved.map(\.id) == ["sub-no"])
    }


    @Test(
        "a pattern matches by alias substring only, when no other field matches",
        arguments: ["1080p", "1080"]
    )
    func matchesByAliasSubstring(pattern: String) {
        let aliasOnlyCandidates: [PlaylistSelection.Candidate] = [
            .init(id: "variant-0", role: .variant, url: URL(string: "https://ex.com/abc123/index.m3u8")!, alias: "1080p_avc1"),
            .init(id: "variant-1", role: .variant, url: URL(string: "https://ex.com/def456/index.m3u8")!, alias: "720p_avc1"),
        ]

        let resolved = PlaylistSelection.resolve(aliasOnlyCandidates, patterns: [pattern])

        #expect(resolved.map(\.id) == ["variant-0"])
    }

    @Test("multiple patterns union their matches in discovery order")
    func multiplePatternsUnion() {
        let resolved = PlaylistSelection.resolve(candidates, patterns: ["v1080", "aud1"])

        #expect(resolved.map(\.id) == ["v1080", "aud-en"])
    }

    @Test("a pattern matching nothing yields an empty selection")
    func nonMatchingPatternYieldsEmpty() {
        #expect(PlaylistSelection.resolve(candidates, patterns: ["nope"]).isEmpty)
    }
}

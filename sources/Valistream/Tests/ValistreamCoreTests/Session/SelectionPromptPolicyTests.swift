//
//  SelectionPromptPolicyTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

@testable import ValistreamCore
import Foundation
import Testing

@Suite("SelectionPromptPolicy", .tags(.session))
struct SelectionPromptPolicyTests {

    // MARK: - Prompt condition (FR-024)

    @Test("--select + TTY shows the interactive prompt")
    func selectFlagOnTTYShowsPrompt() {
        #expect(SelectionPromptPolicy.from(isTTY: true, selectFlag: true, preselectPatterns: nil) == .prompt)
    }



    // MARK: - Skip conditions

    @Test("default (no flags) skips the prompt even on a TTY (FR-021)")
    func defaultNoFlagsSkipsOnTTY() {
        #expect(SelectionPromptPolicy.from(isTTY: true, selectFlag: false, preselectPatterns: nil) == .skip)
    }

    @Test("--preselect only skips the prompt on a TTY (FR-023)")
    func preselectOnlySkipsOnTTY() {
        #expect(SelectionPromptPolicy.from(isTTY: true, selectFlag: false, preselectPatterns: ["video"]) == .skip)
    }

    @Test("--select non-TTY falls back to all (FR-025) — policy returns .skip")
    func selectFlagNonTTYSkips() {
        #expect(SelectionPromptPolicy.from(isTTY: false, selectFlag: true, preselectPatterns: nil) == .skip)
    }

    @Test("default non-TTY skips the prompt (FR-021)")
    func defaultNonTTYSkips() {
        #expect(SelectionPromptPolicy.from(isTTY: false, selectFlag: false, preselectPatterns: nil) == .skip)
    }



    // MARK: - Mutual exclusion (FR-025)

    @Test("--select + --preselect together is a usage error")
    func selectAndPreselectIsMutuallyExclusive() {
        #expect(SelectionPromptPolicy.from(isTTY: true, selectFlag: true, preselectPatterns: ["video"]) == .usageError)
    }

    @Test("--select + --preselect usage error also fires on non-TTY")
    func selectAndPreselectUsageErrorOnNonTTY() {
        #expect(SelectionPromptPolicy.from(isTTY: false, selectFlag: true, preselectPatterns: ["video"]) == .usageError)
    }



    // MARK: - Default selection when skipping (pattern resolution)

    @Test("skip + nil patterns resolves to all candidates (documented default)")
    func skipWithNilPatternsSelectsAll() {
        let candidates = makeCandidates()
        let resolved = PlaylistSelection.resolve(candidates, patterns: nil)
        #expect(resolved == candidates)
    }

    @Test("skip + supplied patterns resolves to matched subset")
    func skipWithPatternsSelectsSubset() {
        let candidates = makeCandidates()
        let resolved = PlaylistSelection.resolve(candidates, patterns: ["v720"])
        #expect(resolved.map(\.id) == ["video-720p"])
    }



    // MARK: - Helpers

    private func makeCandidates() -> [PlaylistSelection.Candidate] {
        [
            .init(id: "video-720p",  role: .variant, url: URL(string: "https://ex.com/v720.m3u8")!),
            .init(id: "video-1080p", role: .variant, url: URL(string: "https://ex.com/v1080.m3u8")!),
            .init(id: "audio-en",    role: .audio,   url: URL(string: "https://ex.com/aud-en.m3u8")!),
        ]
    }
}

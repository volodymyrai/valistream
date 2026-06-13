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

    // MARK: - Skip conditions

    @Test("non-TTY skips the prompt regardless of other flags")
    func nonTTYSkips() {
        #expect(SelectionPromptPolicy.from(isTTY: false, nonInteractive: false, selectionPatterns: nil) == .skip)
    }

    @Test("--all / --non-interactive skips the prompt on a TTY")
    func nonInteractiveFlagSkips() {
        #expect(SelectionPromptPolicy.from(isTTY: true, nonInteractive: true, selectionPatterns: nil) == .skip)
    }

    @Test("--select supplied skips the prompt on a TTY")
    func selectionPatternSkips() {
        #expect(SelectionPromptPolicy.from(isTTY: true, nonInteractive: false, selectionPatterns: ["video"]) == .skip)
    }

    @Test("empty pattern list supplied skips the prompt")
    func emptyPatternListSkips() {
        #expect(SelectionPromptPolicy.from(isTTY: true, nonInteractive: false, selectionPatterns: []) == .skip)
    }



    // MARK: - Prompt condition

    @Test("interactive TTY with no flags shows the prompt")
    func interactiveTTYShowsPrompt() {
        #expect(SelectionPromptPolicy.from(isTTY: true, nonInteractive: false, selectionPatterns: nil) == .prompt)
    }



    // MARK: - Default selection when skipping

    @Test("skip + nil patterns resolves to all candidates (documented default)")
    func skipWithNilPatternsSelectsAll() {
        let candidates = makeCandidates()
        let resolved = PlaylistSelection.resolve(candidates, patterns: nil)
        #expect(resolved == candidates)
    }

    @Test("skip + supplied patterns resolves to matched subset")
    func skipWithPatternsSelectsSubset() {
        let candidates = makeCandidates()
        let resolved = PlaylistSelection.resolve(candidates, patterns: ["video"])
        #expect(resolved.map(\.id) == ["video-720p", "video-1080p"])
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

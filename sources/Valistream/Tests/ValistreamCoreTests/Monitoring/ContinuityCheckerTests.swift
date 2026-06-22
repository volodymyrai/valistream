//
//  ContinuityCheckerTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite("ContinuityChecker", .tags(.monitoring))
struct ContinuityCheckerTests {
    private let checker = ContinuityChecker()

    @Test("a healthy sliding-window advance reports no continuity findings")
    func healthyAdvanceIsClean() {
        let previous = media(mediaSequence: 10, segments: ["s10.ts", "s11.ts", "s12.ts"])
        let current = media(mediaSequence: 11, segments: ["s11.ts", "s12.ts", "s13.ts"])

        #expect(checker.check(previous: previous, current: current).isEmpty)
    }

    @Test("a regressing media sequence is an error")
    func mediaSequenceRegression() {
        let previous = media(mediaSequence: 10, segments: ["s10.ts", "s11.ts"])
        let current = media(mediaSequence: 8, segments: ["s8.ts", "s9.ts"])

        let violations = checker.check(previous: previous, current: current)

        #expect(violations.count == 1)
        #expect(violations.first?.ruleId == "TOOL.continuity.media-sequence")
        #expect(violations.first?.severity == .error)
    }

    @Test("retroactively mutating a retained segment is an error")
    func retainedSegmentMutation() {
        let previous = media(mediaSequence: 10, segments: ["s10.ts", "s11.ts", "s12.ts"])
        let current = media(mediaSequence: 10, segments: ["s10.ts", "MUTATED.ts", "s12.ts"])

        let violations = checker.check(previous: previous, current: current)

        #expect(violations.contains { $0.ruleId == "TOOL.continuity.segment-stability" && $0.severity == .error })
    }

    @Test("changing a retained segment's duration is an error")
    func retainedSegmentDurationChange() {
        let previous = media(mediaSequence: 10, segments: [("s10.ts", 6.0), ("s11.ts", 6.0)])
        let current = media(mediaSequence: 10, segments: [("s10.ts", 6.0), ("s11.ts", 4.0)])

        let violations = checker.check(previous: previous, current: current)

        #expect(violations.contains { $0.ruleId == "TOOL.continuity.segment-stability" })
    }

    @Test("advancing past the entire previous window is premature head removal")
    func prematureHeadRemoval() {
        let previous = media(mediaSequence: 10, segments: ["s10.ts", "s11.ts"])
        let current = media(mediaSequence: 14, segments: ["s14.ts", "s15.ts"])

        let violations = checker.check(previous: previous, current: current)

        #expect(violations.contains { $0.ruleId == "TOOL.continuity.head-removal" && $0.severity == .error })
    }

    @Test("a discontinuity inserted at the tail is reported as info, not an error")
    func discontinuityInsertionIsInfo() {
        let previous = media(mediaSequence: 10, segments: ["s10.ts", "s11.ts"])
        let current = mediaWithDiscontinuousTail(mediaSequence: 11)

        let violations = checker.check(previous: previous, current: current)

        #expect(violations.contains { $0.ruleId == "TOOL.continuity.discontinuity-inserted" && $0.severity == .info })
        #expect(violations.contains { $0.severity == .error } == false)
    }

    @Test("a regressing discontinuity sequence is an error")
    func discontinuitySequenceRegression() {
        let previous = media(mediaSequence: 10, discontinuitySequence: 3, segments: ["s10.ts"])
        let current = media(mediaSequence: 10, discontinuitySequence: 2, segments: ["s10.ts"])

        let violations = checker.check(previous: previous, current: current)

        #expect(violations.contains { $0.ruleId == "TOOL.continuity.discontinuity-sequence" })
    }
}

// MARK: - Factories

private extension ContinuityCheckerTests {
    func media(
        mediaSequence: Int,
        discontinuitySequence: Int = 0,
        segments names: [String]
    ) -> MediaPlaylist {
        media(mediaSequence: mediaSequence, discontinuitySequence: discontinuitySequence, segments: names.map { ($0, 6.0) })
    }

    func media(
        mediaSequence: Int,
        discontinuitySequence: Int = 0,
        segments entries: [(String, Double)]
    ) -> MediaPlaylist {
        let base = URL(string: "https://ex.com/media/")!
        let segments = entries.enumerated().map { index, entry in
            SegmentRef(
                uri: base.appending(path: entry.0),
                duration: entry.1,
                title: nil,
                byteRange: nil,
                hasDiscontinuity: false,
                programDateTime: nil,
                lineNumber: index + 1
            )
        }
        return MediaPlaylist(
            targetDuration: 6,
            mediaSequence: mediaSequence,
            discontinuitySequence: discontinuitySequence,
            segments: segments,
            hasEndList: false,
            playlistType: nil,
            isIFramesOnly: false,
            version: 7,
            hasIndependentSegments: false,
            hasEncryptionKeys: false
        )
    }

    /// A window that retained `s11.ts` and appended a new `s12.ts` carrying a discontinuity.
    func mediaWithDiscontinuousTail(mediaSequence: Int) -> MediaPlaylist {
        let base = URL(string: "https://ex.com/media/")!
        let segments = [
            SegmentRef(uri: base.appending(path: "s11.ts"), duration: 6, title: nil, byteRange: nil, hasDiscontinuity: false, programDateTime: nil, lineNumber: 1),
            SegmentRef(uri: base.appending(path: "s12.ts"), duration: 6, title: nil, byteRange: nil, hasDiscontinuity: true, programDateTime: nil, lineNumber: 2),
        ]
        return MediaPlaylist(
            targetDuration: 6,
            mediaSequence: mediaSequence,
            discontinuitySequence: 0,
            segments: segments,
            hasEndList: false,
            playlistType: nil,
            isIFramesOnly: false,
            version: 7,
            hasIndependentSegments: false,
            hasEncryptionKeys: false
        )
    }
}

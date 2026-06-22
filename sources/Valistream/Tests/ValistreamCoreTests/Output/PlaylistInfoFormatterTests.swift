//
//  PlaylistInfoFormatterTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite(.tags(.output))
struct PlaylistInfoFormatterTests {
    @Test("media field groups are ordered and surface-neutral")
    func mediaGroups() {
        let information = PlaylistInformation(
            playlistID: "video-1",
            kind: .media,
            master: nil,
            media: MediaInfo(
                playlistType: "VOD",
                hlsVersion: 7,
                segmentCount: 3,
                totalListedDuration: 18,
                targetDuration: 8,
                medianSegmentDuration: 6,
                minimumSegmentDuration: 4,
                maximumSegmentDuration: 8,
                mediaSequence: 42,
                discontinuitySequence: 3,
                discontinuityCount: 1,
                endList: true,
                independentSegments: true,
                iFramesOnly: false,
                segmentFormats: ["m4s", "ts"],
                byteRangeUsed: true,
                programDateTimeAvailable: true,
                protection: .encryptedAES128
            )
        )

        let groups = PlaylistInfoFormatter.groups(for: information)

        #expect(groups.map(\.title) == ["Identity", "Timing", "Sequence", "Features", "Protection"])
        #expect(groups.flatMap(\.fields).contains {
            $0.label == "Segment duration" && $0.value == "median 6 s, range 4-8 s"
        })
        #expect(groups.flatMap(\.fields).contains {
            $0.label == "Protection" && $0.value == "Encrypted (AES-128)"
        })
    }

    @Test("formatter distinguishes unknown and undeclared values")
    func missingValues() {
        let information = PlaylistInformation(
            playlistID: "media",
            kind: .media,
            master: nil,
            media: MediaInfo(
                playlistType: "Unknown",
                hlsVersion: nil,
                segmentCount: 0,
                totalListedDuration: 0,
                targetDuration: nil,
                medianSegmentDuration: nil,
                minimumSegmentDuration: nil,
                maximumSegmentDuration: nil,
                mediaSequence: 0,
                discontinuitySequence: 0,
                discontinuityCount: 0,
                endList: false,
                independentSegments: false,
                iFramesOnly: false,
                segmentFormats: [],
                byteRangeUsed: false,
                programDateTimeAvailable: false,
                protection: .none
            )
        )

        let fields = PlaylistInfoFormatter.groups(for: information).flatMap(\.fields)

        #expect(fields.first { $0.label == "HLS version" }?.value == "Not declared")
        #expect(fields.first { $0.label == "Target duration" }?.value == "Not declared")
        #expect(fields.first { $0.label == "Segment format" }?.value == "Unknown")
    }
}

//
//  PlaylistAliasTests.swift
//  ValistreamCoreTests
//

import Testing
@testable import ValistreamCore
import Foundation

@Suite(.tags(.session))
struct PlaylistAliasTests {
    // MARK: - Preferred IDs

    @Test("master uses the exact reserved ID")
    func masterUsesExactID() {
        var registry = AliasRegistry()

        let alias = registry.alias(for: url("master.m3u8"), role: .master)

        #expect(alias.alias == "master")
    }

    @Test(
        "video ID contains height and trimmed codecs",
        arguments: zip(
            [
                ["RESOLUTION": "1920x1080", "CODECS": "avc1.640028"],
                ["RESOLUTION": "1920x1080", "CODECS": "avc1.640028,mp4a.40.2"],
            ],
            ["1080p_avc1", "1080p_avc1-mp4a"]
        )
    )
    func videoID(attributes: [String: String], expected: String) {
        var registry = AliasRegistry()

        let alias = registry.alias(for: url(expected), role: .video, attributes: attributes)

        #expect(alias.alias == expected)
    }

    @Test("codec fields keep underscore reserved for the structural separator")
    func codecFieldsAreSanitized() {
        var registry = AliasRegistry()

        let alias = registry.alias(
            for: url("sanitized.m3u8"),
            role: .video,
            attributes: ["RESOLUTION": "1920x1080", "CODECS": "AVC_1.640028,MP4A+ALT.40.2"]
        )

        #expect(alias.alias == "1080p_avc-1-mp4a-alt")
        #expect(alias.alias.filter { $0 == "_" }.count == 1)
    }



    // MARK: - Fallback IDs

    @Test(
        "missing preferred attributes use role ordinals",
        arguments: zip(
            [AliasRole.video, .audio, .subtitles, .iframe, .unknown],
            ["video_1", "audio_1", "subs_1", "iframe_1", "playlist_1"]
        )
    )
    func missingAttributesUseRoleOrdinal(role: AliasRole, expected: String) {
        var registry = AliasRegistry()

        let alias = registry.alias(for: url(expected), role: role)

        #expect(alias.alias == expected)
    }

    @Test("role ordinal increments independently")
    func roleOrdinalIncrementsIndependently() {
        var registry = AliasRegistry()

        let firstVideo = registry.alias(for: url("video-1.m3u8"), role: .video)
        let audio = registry.alias(for: url("audio-1.m3u8"), role: .audio)
        let secondVideo = registry.alias(for: url("video-2.m3u8"), role: .video)

        #expect(firstVideo.alias == "video_1")
        #expect(audio.alias == "audio_1")
        #expect(secondVideo.alias == "video_2")
    }



    // MARK: - Uniqueness & stability

    @Test("residual collisions use deterministic numeric suffixes")
    func collisionsUseNumericSuffixes() {
        var registry = AliasRegistry()
        let attributes = ["RESOLUTION": "1920x1080", "CODECS": "avc1.640028"]

        let first = registry.alias(for: url("first.m3u8"), role: .video, attributes: attributes)
        let second = registry.alias(for: url("second.m3u8"), role: .video, attributes: attributes)
        let third = registry.alias(for: url("third.m3u8"), role: .video, attributes: attributes)

        #expect(first.alias == "1080p_avc1")
        #expect(second.alias == "1080p_avc1_2")
        #expect(third.alias == "1080p_avc1_3")
    }

    @Test("same URL keeps its first ID and metadata")
    func sameURLIsIdempotent() {
        var registry = AliasRegistry()
        let playlistURL = url("stable.m3u8")
        let firstAttributes = ["RESOLUTION": "1920x1080", "CODECS": "avc1.640028"]
        let changedAttributes = ["RESOLUTION": "1280x720", "CODECS": "hvc1.1.6.L93"]

        let first = registry.alias(for: playlistURL, role: .video, attributes: firstAttributes)
        let second = registry.alias(for: playlistURL, role: .video, attributes: changedAttributes)

        #expect(first == second)
        #expect(second.alias == "1080p_avc1")
        #expect(registry.all == [first])
    }

    @Test("same discovery order produces the same IDs across runs")
    func IDsAreDeterministicAcrossRuns() {
        let firstRun = makeAliases()
        let secondRun = makeAliases()

        #expect(firstRun == secondRun)
    }

    @Test("all IDs use the filesystem-safe charset")
    func IDsUseFilesystemSafeCharset() {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_-")

        for alias in makeAliases() {
            #expect(alias.allSatisfy { allowed.contains($0) })
        }
    }

    @Test("all returns aliases in registration order")
    func allPreservesRegistrationOrder() {
        var registry = AliasRegistry()
        let master = registry.alias(for: url("master.m3u8"), role: .master)
        let video = registry.alias(
            for: url("video.m3u8"),
            role: .video,
            attributes: ["RESOLUTION": "1280x720", "CODECS": "avc1.4d401f"]
        )

        #expect(registry.all == [master, video])
        #expect(registry.alias(for: video.url) == video)
        #expect(registry.alias(for: url("missing.m3u8")) == nil)
    }



    // MARK: - AliasRole bridge

    @Test("AliasRole maps every PlaylistRole case")
    func aliasRoleBridge() {
        #expect(AliasRole(from: .variant) == .video)
        #expect(AliasRole(from: .audio) == .audio)
        #expect(AliasRole(from: .subtitles) == .subtitles)
        #expect(AliasRole(from: .iframe) == .iframe)
    }



    // MARK: - Private

    private func makeAliases() -> [String] {
        var registry = AliasRegistry()
        registry.alias(for: url("master.m3u8"), role: .master)
        registry.alias(
            for: url("video-1.m3u8"),
            role: .video,
            attributes: ["RESOLUTION": "1920x1080", "CODECS": "avc1.640028,mp4a.40.2"]
        )
        registry.alias(
            for: url("video-2.m3u8"),
            role: .video,
            attributes: ["RESOLUTION": "1920x1080", "CODECS": "avc1.640028,mp4a.40.2"]
        )
        registry.alias(for: url("audio.m3u8"), role: .audio, attributes: ["LANGUAGE": "EN us"])

        return registry.all.map(\.alias)
    }

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: "/tmp/valistream-tests/\(path)")
    }
}

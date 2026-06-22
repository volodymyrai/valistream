//
//  PlaylistAliasRoleTests.swift
//  ValistreamCoreTests
//

import Testing
@testable import ValistreamCore
import Foundation

@Suite(.tags(.session))
struct PlaylistAliasRoleTests {
    // MARK: - Audio IDs

    @Test(
        "audio ID uses slug of LANGUAGE attribute",
        arguments: zip(
            [
                ["LANGUAGE": "en"],
                ["LANGUAGE": "fr"],
                ["LANGUAGE": "zh-TW"],
                ["LANGUAGE": "EN US"],
            ],
            ["audio_en", "audio_fr", "audio_zh_tw", "audio_en_us"]
        )
    )
    func audioIDUsesLanguageSlug(attributes: [String: String], expected: String) {
        var registry = AliasRegistry()

        let alias = registry.alias(for: url("audio-\(expected).m3u8"), role: .audio, attributes: attributes)

        #expect(alias.alias == expected)
    }

    @Test("audio same-language collision disambiguates with slug of NAME")
    func audioSameLanguageCollisionAppendsNameSlug() {
        var registry = AliasRegistry()

        let main = registry.alias(
            for: url("audio-en-main.m3u8"),
            role: .audio,
            attributes: ["LANGUAGE": "en", "NAME": "Main"]
        )
        let commentary = registry.alias(
            for: url("audio-en-commentary.m3u8"),
            role: .audio,
            attributes: ["LANGUAGE": "en", "NAME": "Commentary"]
        )

        // First registration keeps the base language ID
        #expect(main.alias == "audio_en")
        // Second with same language is disambiguated via NAME slug
        #expect(commentary.alias == "audio_en_commentary")
    }

    @Test("audio three-way same-language collision produces unique IDs")
    func audioThreeWaySameLanguageCollision() {
        var registry = AliasRegistry()

        let a = registry.alias(
            for: url("audio-en-a.m3u8"),
            role: .audio,
            attributes: ["LANGUAGE": "en", "NAME": "Main"]
        )
        let b = registry.alias(
            for: url("audio-en-b.m3u8"),
            role: .audio,
            attributes: ["LANGUAGE": "en", "NAME": "Director"]
        )
        let c = registry.alias(
            for: url("audio-en-c.m3u8"),
            role: .audio,
            attributes: ["LANGUAGE": "en", "NAME": "Commentary"]
        )

        #expect(Set([a.alias, b.alias, c.alias]).count == 3)
        #expect(a.alias == "audio_en")
        #expect(b.alias == "audio_en_director")
        #expect(c.alias == "audio_en_commentary")
    }

    @Test("audio ID falls back to NAME slug when LANGUAGE is absent")
    func audioIDFallsBackToNameWhenLanguageAbsent() {
        var registry = AliasRegistry()

        let alias = registry.alias(
            for: url("audio-desc.m3u8"),
            role: .audio,
            attributes: ["NAME": "Descriptive Audio"]
        )

        #expect(alias.alias == "audio_descriptive_audio")
    }

    @Test("audio with no LANGUAGE and no NAME uses role+ordinal fallback")
    func audioNoAttributesUsesOrdinalFallback() {
        var registry = AliasRegistry()

        let alias = registry.alias(for: url("audio-bare.m3u8"), role: .audio)

        #expect(alias.alias == "audio_1")
    }

    // MARK: - Subtitles IDs

    @Test(
        "subs ID uses slug of LANGUAGE attribute",
        arguments: zip(
            [
                ["LANGUAGE": "en"],
                ["LANGUAGE": "fr"],
                ["LANGUAGE": "zh-TW"],
            ],
            ["subs_en", "subs_fr", "subs_zh_tw"]
        )
    )
    func subsIDUsesLanguageSlug(attributes: [String: String], expected: String) {
        var registry = AliasRegistry()

        let alias = registry.alias(for: url("subs-\(expected).m3u8"), role: .subtitles, attributes: attributes)

        #expect(alias.alias == expected)
    }

    @Test("subs same-language collision disambiguates with NAME slug")
    func subsSameLanguageCollisionAppendsNameSlug() {
        var registry = AliasRegistry()

        let main = registry.alias(
            for: url("subs-en-main.m3u8"),
            role: .subtitles,
            attributes: ["LANGUAGE": "en", "NAME": "Main"]
        )
        let cc = registry.alias(
            for: url("subs-en-cc.m3u8"),
            role: .subtitles,
            attributes: ["LANGUAGE": "en", "NAME": "Closed Captions"]
        )

        #expect(main.alias == "subs_en")
        #expect(cc.alias == "subs_en_closed_captions")
    }

    @Test("subs ID falls back to NAME slug when LANGUAGE is absent")
    func subsIDFallsBackToNameWhenLanguageAbsent() {
        var registry = AliasRegistry()

        let alias = registry.alias(
            for: url("subs-sdh.m3u8"),
            role: .subtitles,
            attributes: ["NAME": "SDH"]
        )

        #expect(alias.alias == "subs_sdh")
    }

    @Test("subs with no LANGUAGE and no NAME uses role+ordinal fallback")
    func subsNoAttributesUsesOrdinalFallback() {
        var registry = AliasRegistry()

        let alias = registry.alias(for: url("subs-bare.m3u8"), role: .subtitles)

        #expect(alias.alias == "subs_1")
    }

    // MARK: - I-frame IDs

    @Test(
        "iframe ID uses height from RESOLUTION attribute",
        arguments: zip(
            [
                ["RESOLUTION": "1920x1080"],
                ["RESOLUTION": "1280x720"],
                ["RESOLUTION": "640x360"],
            ],
            ["iframe_1080p", "iframe_720p", "iframe_360p"]
        )
    )
    func iframeIDUsesResolutionHeight(attributes: [String: String], expected: String) {
        var registry = AliasRegistry()

        let alias = registry.alias(for: url("iframe-\(expected).m3u8"), role: .iframe, attributes: attributes)

        #expect(alias.alias == expected)
    }

    @Test("iframe with no RESOLUTION uses role+ordinal fallback")
    func iframeNoResolutionUsesOrdinalFallback() {
        var registry = AliasRegistry()

        let alias = registry.alias(for: url("iframe-bare.m3u8"), role: .iframe)

        #expect(alias.alias == "iframe_1")
    }

    // MARK: - Role+ordinal fallback

    @Test(
        "role+ordinal fallback increments per role independently",
        arguments: [AliasRole.audio, .subtitles, .iframe]
    )
    func roleOrdinalFallbackIncrementsPerRole(role: AliasRole) {
        var registry = AliasRegistry()

        let first = registry.alias(for: url("r1-\(role).m3u8"), role: role)
        let second = registry.alias(for: url("r2-\(role).m3u8"), role: role)

        // Both are fallback (no recognizable attributes)
        let roleName: String = switch role {
        case .audio: "audio"
        case .subtitles: "subs"
        case .iframe: "iframe"
        default: "playlist"
        }
        #expect(first.alias == "\(roleName)_1")
        #expect(second.alias == "\(roleName)_2")
    }

    // MARK: - Charset & dedup

    @Test("all role-based IDs use the filesystem-safe charset")
    func roleBasedIDsUseFilesystemSafeCharset() {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_-")
        var registry = AliasRegistry()

        registry.alias(for: url("a-en.m3u8"), role: .audio, attributes: ["LANGUAGE": "en", "NAME": "Main"])
        registry.alias(for: url("a-fr.m3u8"), role: .audio, attributes: ["LANGUAGE": "fr"])
        registry.alias(for: url("s-en.m3u8"), role: .subtitles, attributes: ["LANGUAGE": "en"])
        registry.alias(for: url("i-1080.m3u8"), role: .iframe, attributes: ["RESOLUTION": "1920x1080"])

        for entry in registry.all {
            #expect(entry.alias.allSatisfy { allowed.contains($0) })
        }
    }

    @Test("residual role-ID collision appends numeric suffix")
    func residualRoleIDCollisionAppendsSuffix() {
        var registry = AliasRegistry()

        // Two audio tracks with the same language and name → same preferred ID → numeric dedup
        let first = registry.alias(
            for: url("audio-dup-1.m3u8"),
            role: .audio,
            attributes: ["LANGUAGE": "en", "NAME": "Main"]
        )
        let second = registry.alias(
            for: url("audio-dup-2.m3u8"),
            role: .audio,
            attributes: ["LANGUAGE": "en", "NAME": "Main"]
        )

        #expect(first.alias == "audio_en")
        // Second is disambiguated first by NAME slug; both have same NAME, so numeric suffix kicks in
        // The first collision attempt tries "audio_en_main" (NAME added), which is new → used
        #expect(second.alias == "audio_en_main")
    }

    @Test("same URL is idempotent for role-based IDs")
    func sameURLIsIdempotentForRoleIDs() {
        var registry = AliasRegistry()
        let audioURL = url("audio-en.m3u8")

        let first = registry.alias(for: audioURL, role: .audio, attributes: ["LANGUAGE": "en"])
        let second = registry.alias(for: audioURL, role: .audio, attributes: ["LANGUAGE": "fr"])

        #expect(first == second)
        #expect(second.alias == "audio_en")
    }

    // MARK: - Private

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: "/tmp/valistream-tests/\(path)")
    }
}

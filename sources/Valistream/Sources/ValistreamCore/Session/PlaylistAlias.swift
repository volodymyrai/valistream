//
//  PlaylistAlias.swift
//  ValistreamCore
//

import Foundation

/// Role a playlist plays in a stream — drives alias derivation (FR-024–026).
public enum AliasRole: String, Sendable, Equatable, CaseIterable {
    case video
    case audio
    case subtitles
    case iframe
    case master
    case unknown
}

/// A short, stable, human-meaningful label standing in for a full playlist URL
/// throughout the human-readable report (FR-024–026).
public struct PlaylistAlias: Sendable, Equatable {
    public let alias: String
    public let url: URL
    public let role: AliasRole
    public let attributes: [String: String]

    public init(alias: String, url: URL, role: AliasRole, attributes: [String: String]) {
        self.alias = alias
        self.url = url
        self.role = role
        self.attributes = attributes
    }
}

/// Session-scoped owner of the `[URL: PlaylistAlias]` map.
///
/// Assigns aliases on first sight; guarantees stability (same URL → same alias) and uniqueness
/// within a session (deterministic dedup suffix on collision).
public struct AliasRegistry: Sendable {
    private var byURL: [URL: PlaylistAlias] = [:]
    private var usedAliases: Set<String> = []
    private var roleCounters: [AliasRole: Int] = [:]
    private var ordered: [PlaylistAlias] = []

    public init() {}

    /// Idempotent — the same `url` always returns the same alias for this registry instance.
    @discardableResult
    public mutating func alias(
        for url: URL,
        role: AliasRole,
        attributes: [String: String] = [:]
    ) -> PlaylistAlias {
        if let existing = byURL[url] { return existing }
        let base = preferredAlias(role: role, attributes: attributes) ?? fallbackAlias(role: role)
        // Try base first; on collision use name-based disambiguation before numeric suffix.
        let candidate: String
        if usedAliases.contains(base) {
            let disambiguated = nameDisambiguated(base: base, role: role, attributes: attributes)
            candidate = deduplicate(disambiguated)
        }
        else {
            candidate = base
        }
        usedAliases.insert(candidate)
        let entry = PlaylistAlias(alias: candidate, url: url, role: role, attributes: attributes)
        byURL[url] = entry
        ordered.append(entry)

        return entry
    }

    /// Returns the alias registered for `url`, or `nil` if not yet registered.
    public func alias(for url: URL) -> PlaylistAlias? {
        byURL[url]
    }

    /// All registered aliases in registration order.
    public var all: [PlaylistAlias] { ordered }



    // MARK: - Private

    private func preferredAlias(role: AliasRole, attributes: [String: String]) -> String? {
        switch role {
        case .master:
            "master"
        case .video:
            videoAlias(attributes: attributes)
        case .audio:
            audioOrSubsAlias(prefix: "audio", attributes: attributes)
        case .subtitles:
            audioOrSubsAlias(prefix: "subs", attributes: attributes)
        case .iframe:
            iframeAlias(attributes: attributes)
        case .unknown:
            nil
        }
    }

    private func videoAlias(attributes: [String: String]) -> String? {
        guard
            let resolution = attributes["RESOLUTION"],
            let codecs = attributes["CODECS"],
            let height = resolution
                .split(whereSeparator: { $0 == "x" || $0 == "X" })
                .last?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            height.isEmpty == false,
            height.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        let codecFields = codecs.split(separator: ",", omittingEmptySubsequences: false).map { codec in
            let fourCC = codec.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0]

            return slug(String(fourCC)).replacing("_", with: "-")
        }
        guard codecFields.allSatisfy({ $0.isEmpty == false }) else { return nil }

        return "\(height)p_\(codecFields.joined(separator: "-"))"
    }

    /// Derives `audio_<slug(LANGUAGE)>` or `subs_<slug(LANGUAGE)>`.
    /// When `LANGUAGE` is absent, falls back to `<prefix>_<slug(NAME)>`.
    /// Returns `nil` when neither attribute is present (triggers role+ordinal fallback).
    private func audioOrSubsAlias(prefix: String, attributes: [String: String]) -> String? {
        if let language = attributes["LANGUAGE"], language.isEmpty == false {
            let langSlug = slug(language)
            guard langSlug.isEmpty == false else { return nil }
            return "\(prefix)_\(langSlug)"
        }
        if let name = attributes["NAME"], name.isEmpty == false {
            let nameSlug = slug(name)
            guard nameSlug.isEmpty == false else { return nil }
            return "\(prefix)_\(nameSlug)"
        }
        return nil
    }

    /// Derives `iframe_<height>p` from `RESOLUTION`.
    /// Returns `nil` when `RESOLUTION` is absent (triggers role+ordinal fallback).
    private func iframeAlias(attributes: [String: String]) -> String? {
        guard
            let resolution = attributes["RESOLUTION"],
            let height = resolution
                .split(whereSeparator: { $0 == "x" || $0 == "X" })
                .last?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            height.isEmpty == false,
            height.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        return "iframe_\(height)p"
    }

    /// Returns a name-disambiguated candidate when the base preferred alias is already taken.
    /// For audio/subs: appends `_<slug(NAME)>` when NAME is present.
    /// For other roles: returns the base unchanged (numeric suffix path applies).
    private func nameDisambiguated(base: String, role: AliasRole, attributes: [String: String]) -> String {
        switch role {
        case .audio, .subtitles:
            if let name = attributes["NAME"], name.isEmpty == false {
                let nameSlug = slug(name)
                if nameSlug.isEmpty == false {
                    return "\(base)_\(nameSlug)"
                }
            }
            return base
        default:
            return base
        }
    }

    private mutating func fallbackAlias(role: AliasRole) -> String {
        let roleName = switch role {
        case .video: "video"
        case .audio: "audio"
        case .subtitles: "subs"
        case .iframe: "iframe"
        case .master: "master"
        case .unknown: "playlist"
        }
        let ordinal = roleCounters[role, default: 0] + 1
        roleCounters[role] = ordinal

        return "\(roleName)_\(ordinal)"
    }

    private func deduplicate(_ base: String) -> String {
        guard usedAliases.contains(base) else { return base }
        var suffix = 2
        while usedAliases.contains("\(base)_\(suffix)") {
            suffix += 1
        }

        return "\(base)_\(suffix)"
    }

    private func slug(_ value: String) -> String {
        var result = ""
        var pendingSeparator = false
        for scalar in value.lowercased().unicodeScalars {
            let scalarValue = scalar.value
            let isASCIIAlphanumeric = (UInt32(97)...UInt32(122)).contains(scalarValue)
                || (UInt32(48)...UInt32(57)).contains(scalarValue)
            if isASCIIAlphanumeric {
                if pendingSeparator, result.isEmpty == false {
                    result.append("_")
                }
                result.unicodeScalars.append(scalar)
                pendingSeparator = false
            }
            else if result.isEmpty == false {
                pendingSeparator = true
            }
        }

        return result
    }
}

// MARK: - PlaylistRole bridge

extension AliasRole {
    /// Maps a `PlaylistRole` (from HLS playlist metadata) to the corresponding `AliasRole`.
    public init(from role: PlaylistRole) {
        switch role {
        case .variant:   self = .video
        case .audio:     self = .audio
        case .subtitles: self = .subtitles
        case .iframe:    self = .iframe
        }
    }
}

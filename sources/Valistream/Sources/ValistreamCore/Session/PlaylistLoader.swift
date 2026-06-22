//
//  PlaylistLoader.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// The role a media playlist plays within a master (matches the report schema's `role`).
public enum PlaylistRole: String, Sendable, Equatable, Codable {
    case variant
    case audio
    case subtitles
    case iframe
}

/// A reference to a media playlist discovered in a master, before it is fetched.
public struct PlaylistReference: Sendable, Equatable {
    public let url: URL
    public let role: PlaylistRole
    public let groupID: String?
    public let name: String?

    public init(url: URL, role: PlaylistRole, groupID: String? = nil, name: String? = nil) {
        self.url = url
        self.role = role
        self.groupID = groupID
        self.name = name
    }
}

/// The outcome of fetching and parsing one playlist resource.
public struct LoadedPlaylist: Sendable {
    public let url: URL
    public let role: PlaylistRole?
    public let result: FetchResult
    public let tokens: [M3U8Token]
    public let playlist: Playlist?
    public let deliveryViolations: [RuleViolation]
}

/// Fetches and parses playlists, converting delivery problems into `delivery` findings so the
/// session can keep going instead of aborting (FR-004, FR-014).
public struct PlaylistLoader: Sendable {
    // MARK: - Lets & Vars

    private let fetcher: any StreamFetching
    private let tokenizer = M3U8Tokenizer()
    private let builder = PlaylistBuilder()



    // MARK: - Lifecycle

    public init(fetcher: any StreamFetching) {
        self.fetcher = fetcher
    }



    // MARK: - Public

    /// Fetches and parses a single playlist, emitting delivery violations on failure.
    public func load(_ url: URL, role: PlaylistRole? = nil) async -> LoadedPlaylist {
        let result = await fetcher.fetch(url)

        switch result.outcome {
        case .transportError(let description):
            return failure(url: url, role: role, result: result, violation: RuleViolation(
                ruleId: "TOOL.delivery",
                source: .tool,
                severity: .error,
                category: .delivery,
                message: "Failed to fetch playlist: \(description).",
                context: ["outcome": .string("transportError")]
            ))
        case .httpError(let status):
            return failure(url: url, role: role, result: result, violation: RuleViolation(
                ruleId: "TOOL.delivery",
                source: .tool,
                severity: .error,
                category: .delivery,
                message: "Playlist request returned HTTP status \(status).",
                context: ["httpStatus": .int(status)]
            ))
        case .success:
            return parseSuccess(url: url, role: role, result: result)
        }
    }

    /// Enumerates the media playlists referenced by a master (variants, renditions, I-frame streams).
    public func mediaReferences(in master: MasterPlaylist) -> [PlaylistReference] {
        var references: [PlaylistReference] = []
        var seen: Set<URL> = []

        func add(_ reference: PlaylistReference) {
            guard seen.insert(reference.url).inserted else { return }
            references.append(reference)
        }

        for variant in master.variants {
            add(PlaylistReference(url: variant.uri, role: .variant))
        }
        for rendition in master.renditions {
            guard let uri = rendition.uri else { continue }
            let role: PlaylistRole = rendition.type == "SUBTITLES" ? .subtitles : .audio
            add(PlaylistReference(url: uri, role: role, groupID: rendition.groupID, name: rendition.name))
        }
        for iframe in master.iFrameStreams {
            add(PlaylistReference(url: iframe.uri, role: .iframe))
        }
        return references
    }



    // MARK: - Private

    private func parseSuccess(url: URL, role: PlaylistRole?, result: FetchResult) -> LoadedPlaylist {
        guard let body = result.bodyText, Self.looksLikePlaylist(body) else {
            let violation = RuleViolation(
                ruleId: "TOOL.delivery",
                source: .tool,
                severity: .error,
                category: .delivery,
                message: "Response body is not an M3U8 playlist (missing #EXTM3U).",
                context: ["outcome": .string("notAPlaylist")]
            )
            return LoadedPlaylist(
                url: url,
                role: role,
                result: result,
                tokens: [],
                playlist: nil,
                deliveryViolations: [violation]
            )
        }
        let tokens = tokenizer.tokenize(body)
        let playlist = builder.build(tokens: tokens, baseURL: result.url)
        return LoadedPlaylist(
            url: url,
            role: role,
            result: result,
            tokens: tokens,
            playlist: playlist,
            deliveryViolations: []
        )
    }

    private func failure(url: URL, role: PlaylistRole?, result: FetchResult, violation: RuleViolation) -> LoadedPlaylist {
        LoadedPlaylist(url: url, role: role, result: result, tokens: [], playlist: nil, deliveryViolations: [violation])
    }

    private static func looksLikePlaylist(_ body: String) -> Bool {
        body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first { !$0.allSatisfy(\.isWhitespace) }?
            .trimmingCharacters(in: .whitespaces)
            .hasPrefix("#EXTM3U") ?? false
    }
}

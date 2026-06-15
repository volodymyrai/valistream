//
//  PlaylistBuilder.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Builds a structured ``Playlist`` from a lossless token stream, resolving relative URIs.
///
/// Detection follows FR-002: the presence of `#EXT-X-STREAM-INF` or `#EXT-X-I-FRAME-STREAM-INF`
/// marks a master playlist; otherwise the playlist is treated as a media playlist. Parsing is
/// lenient — unrecognized or malformed content is ignored here and surfaced by validation rules.
public struct PlaylistBuilder: Sendable {
    // MARK: - Lifecycle

    public init() {}



    // MARK: - Public

    /// Builds a structured playlist from tokens, resolving URIs against `baseURL`.
    public func build(tokens: [M3U8Token], baseURL: URL) -> Playlist {
        var state = BuildState()
        for token in tokens {
            guard case .tag(let name, let attributes) = token.kind else {
                if case .uri(let raw) = token.kind {
                    state.consumeURI(raw, lineNumber: token.lineNumber, baseURL: baseURL)
                }
                continue
            }
            state.consumeTag(name: name, attributes: attributes, lineNumber: token.lineNumber, baseURL: baseURL)
        }
        return state.makePlaylist()
    }
}

// MARK: - BuildState

private extension PlaylistBuilder {
    /// Accumulates parser state across the token stream until a complete playlist can be produced.
    struct BuildState {
        var variants: [VariantStream] = []
        var iFrameStreams: [IFrameStream] = []
        var renditions: [Rendition] = []
        var segments: [SegmentRef] = []

        var version: Int?
        var hasIndependentSegments = false
        var targetDuration: Double?
        var mediaSequence = 0
        var discontinuitySequence = 0
        var playlistType: String?
        var isIFramesOnly = false
        var hasEndList = false
        var hasEncryptionKeys = false
        var keyMethod: String?
        var keyFormat: String?
        var sessionKeyMethod: String?
        var sessionKeyFormat: String?

        var sawStreamInf = false
        var sawIFrameStreamInf = false

        var pendingStreamInf: (attributes: AttributeList, lineNumber: Int)?
        var pendingDuration: Double?
        var pendingTitle: String?
        var pendingByteRange: ByteRange?
        var pendingDiscontinuity = false
        var pendingProgramDateTime: String?

        mutating func consumeTag(name: String, attributes: String?, lineNumber: Int, baseURL: URL) {
            switch name {
            case "#EXT-X-VERSION":
                version = attributes.flatMap { Int($0) }
            case "#EXT-X-INDEPENDENT-SEGMENTS":
                hasIndependentSegments = true
            case "#EXT-X-TARGETDURATION":
                targetDuration = attributes.flatMap { Double($0) }
            case "#EXT-X-MEDIA-SEQUENCE":
                mediaSequence = attributes.flatMap { Int($0) } ?? 0
            case "#EXT-X-DISCONTINUITY-SEQUENCE":
                discontinuitySequence = attributes.flatMap { Int($0) } ?? 0
            case "#EXT-X-PLAYLIST-TYPE":
                playlistType = attributes
            case "#EXT-X-I-FRAMES-ONLY":
                isIFramesOnly = true
            case "#EXT-X-ENDLIST":
                hasEndList = true
            case "#EXT-X-KEY":
                if let attributes {
                    let key = AttributeList(parsing: attributes)
                    keyMethod = key["METHOD"]
                    keyFormat = key["KEYFORMAT"]
                }
                if let keyMethod, keyMethod != "NONE" {
                    hasEncryptionKeys = true
                }
            case "#EXT-X-SESSION-KEY":
                if let attributes {
                    let key = AttributeList(parsing: attributes)
                    sessionKeyMethod = key["METHOD"]
                    sessionKeyFormat = key["KEYFORMAT"]
                }
            case "#EXT-X-STREAM-INF":
                sawStreamInf = true
                pendingStreamInf = (AttributeList(parsing: attributes ?? ""), lineNumber)
            case "#EXT-X-I-FRAME-STREAM-INF":
                sawIFrameStreamInf = true
                consumeIFrameStreamInf(attributes ?? "", lineNumber: lineNumber, baseURL: baseURL)
            case "#EXT-X-MEDIA":
                consumeRendition(attributes ?? "", lineNumber: lineNumber, baseURL: baseURL)
            case "#EXTINF":
                consumeExtInf(attributes ?? "")
            case "#EXT-X-BYTERANGE":
                pendingByteRange = attributes.flatMap { ByteRange(parsing: $0) }
            case "#EXT-X-DISCONTINUITY":
                pendingDiscontinuity = true
            case "#EXT-X-PROGRAM-DATE-TIME":
                pendingProgramDateTime = attributes
            default:
                break
            }
        }

        mutating func consumeURI(_ raw: String, lineNumber: Int, baseURL: URL) {
            guard let url = resolve(raw, baseURL: baseURL) else { return }
            if let pending = pendingStreamInf {
                variants.append(VariantStream(uri: url, attributes: pending.attributes, lineNumber: pending.lineNumber))
                pendingStreamInf = nil
            }
            else {
                appendSegment(uri: url, lineNumber: lineNumber)
            }
        }

        private mutating func consumeExtInf(_ raw: String) {
            let parts = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            pendingDuration = parts.first.flatMap { Double($0) }
            let title = parts.count > 1 ? String(parts[1]) : ""
            pendingTitle = title.isEmpty ? nil : title
        }

        private mutating func appendSegment(uri: URL, lineNumber: Int) {
            segments.append(SegmentRef(
                uri: uri,
                duration: pendingDuration ?? 0,
                title: pendingTitle,
                byteRange: pendingByteRange,
                hasDiscontinuity: pendingDiscontinuity,
                programDateTime: pendingProgramDateTime,
                lineNumber: lineNumber
            ))
            pendingDuration = nil
            pendingTitle = nil
            pendingByteRange = nil
            pendingDiscontinuity = false
            pendingProgramDateTime = nil
        }

        private mutating func consumeRendition(_ raw: String, lineNumber: Int, baseURL: URL) {
            let attributes = AttributeList(parsing: raw)
            let uri = attributes["URI"].flatMap { resolve($0, baseURL: baseURL) }
            renditions.append(Rendition(attributes: attributes, resolvedURI: uri, lineNumber: lineNumber))
        }

        private mutating func consumeIFrameStreamInf(_ raw: String, lineNumber: Int, baseURL: URL) {
            let attributes = AttributeList(parsing: raw)
            guard let uri = attributes["URI"].flatMap({ resolve($0, baseURL: baseURL) }) else { return }
            iFrameStreams.append(IFrameStream(uri: uri, attributes: attributes, lineNumber: lineNumber))
        }

        private func resolve(_ raw: String, baseURL: URL) -> URL? {
            URL(string: raw, relativeTo: baseURL)?.absoluteURL
        }

        func makePlaylist() -> Playlist {
            let isMaster = sawStreamInf || sawIFrameStreamInf || (!renditions.isEmpty && segments.isEmpty)
            if isMaster {
                return .master(MasterPlaylist(
                    variants: variants,
                    iFrameStreams: iFrameStreams,
                    renditions: renditions,
                    version: version,
                    hasIndependentSegments: hasIndependentSegments,
                    sessionKeyMethod: sessionKeyMethod,
                    sessionKeyFormat: sessionKeyFormat
                ))
            }
            return .media(MediaPlaylist(
                targetDuration: targetDuration,
                mediaSequence: mediaSequence,
                discontinuitySequence: discontinuitySequence,
                segments: segments,
                hasEndList: hasEndList,
                playlistType: playlistType,
                isIFramesOnly: isIFramesOnly,
                version: version,
                hasIndependentSegments: hasIndependentSegments,
                hasEncryptionKeys: hasEncryptionKeys,
                keyMethod: keyMethod,
                keyFormat: keyFormat
            ))
        }
    }
}

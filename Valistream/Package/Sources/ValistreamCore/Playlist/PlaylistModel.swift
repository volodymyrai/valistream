//
//  PlaylistModel.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// A structured M3U8 playlist, either a master (multivariant) or a media playlist.
///
/// The structured model is built leniently over the lossless token stream (``M3U8Tokenizer``):
/// it extracts what it recognizes and never rejects malformed input, leaving anomalies for the
/// validation rules to report (FR-002, research §2).
public enum Playlist: Sendable, Equatable {
    case master(MasterPlaylist)
    case media(MediaPlaylist)

    /// Whether this is a master or media playlist.
    public var kind: PlaylistKind {
        switch self {
        case .master: .master
        case .media: .media
        }
    }

    /// The master playlist, or `nil` if this is a media playlist.
    public var master: MasterPlaylist? {
        if case .master(let master) = self { return master }
        return nil
    }

    /// The media playlist, or `nil` if this is a master playlist.
    public var media: MediaPlaylist? {
        if case .media(let media) = self { return media }
        return nil
    }
}

/// Distinguishes a master (multivariant) playlist from a media playlist.
public enum PlaylistKind: String, Sendable, Equatable, Codable {
    case master
    case media
}

/// A pixel resolution declared by `RESOLUTION=<w>x<h>`.
public struct Resolution: Sendable, Equatable, Codable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Parses the `<w>x<h>` attribute form, returning `nil` when malformed.
    public init?(parsing raw: String) {
        let parts = raw.split(separator: "x", maxSplits: 1)
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else {
            return nil
        }
        self.width = width
        self.height = height
    }
}

/// A `#EXT-X-STREAM-INF` variant declaration plus the URI line that follows it.
public struct VariantStream: Sendable, Equatable {
    public let uri: URL
    public let attributes: AttributeList
    public let lineNumber: Int

    public var bandwidth: Int? { attributes["BANDWIDTH"].flatMap(Int.init) }
    public var averageBandwidth: Int? { attributes["AVERAGE-BANDWIDTH"].flatMap(Int.init) }
    public var resolution: Resolution? { attributes["RESOLUTION"].flatMap(Resolution.init(parsing:)) }
    public var frameRate: Double? { attributes["FRAME-RATE"].flatMap(Double.init) }
    public var codecs: [String] {
        attributes["CODECS"].map { $0.split(separator: ",").map(String.init) } ?? []
    }
    public var audioGroupID: String? { attributes["AUDIO"] }
    public var videoGroupID: String? { attributes["VIDEO"] }
    public var subtitlesGroupID: String? { attributes["SUBTITLES"] }
    public var closedCaptionsGroupID: String? { attributes["CLOSED-CAPTIONS"] }

    public init(uri: URL, attributes: AttributeList, lineNumber: Int) {
        self.uri = uri
        self.attributes = attributes
        self.lineNumber = lineNumber
    }
}

/// A `#EXT-X-I-FRAME-STREAM-INF` declaration.
public struct IFrameStream: Sendable, Equatable {
    public let uri: URL
    public let attributes: AttributeList
    public let lineNumber: Int

    public var bandwidth: Int? { attributes["BANDWIDTH"].flatMap(Int.init) }
    public var resolution: Resolution? { attributes["RESOLUTION"].flatMap(Resolution.init(parsing:)) }
    public var codecs: [String] {
        attributes["CODECS"].map { $0.split(separator: ",").map(String.init) } ?? []
    }

    public init(uri: URL, attributes: AttributeList, lineNumber: Int) {
        self.uri = uri
        self.attributes = attributes
        self.lineNumber = lineNumber
    }
}

/// A `#EXT-X-MEDIA` rendition group member.
public struct Rendition: Sendable, Equatable {
    public let attributes: AttributeList
    public let resolvedURI: URL?
    public let lineNumber: Int

    public var type: String? { attributes["TYPE"] }
    public var groupID: String? { attributes["GROUP-ID"] }
    public var name: String? { attributes["NAME"] }
    public var language: String? { attributes["LANGUAGE"] }
    public var uri: URL? { resolvedURI }
    public var isDefault: Bool { attributes["DEFAULT"] == "YES" }
    public var isAutoselect: Bool { attributes["AUTOSELECT"] == "YES" }
    public var isForced: Bool { attributes["FORCED"] == "YES" }
    public var instreamID: String? { attributes["INSTREAM-ID"] }
    public var characteristics: String? { attributes["CHARACTERISTICS"] }

    public init(attributes: AttributeList, resolvedURI: URL?, lineNumber: Int) {
        self.attributes = attributes
        self.resolvedURI = resolvedURI
        self.lineNumber = lineNumber
    }
}

/// A byte range from `#EXT-X-BYTERANGE:<length>[@<offset>]`.
public struct ByteRange: Sendable, Equatable {
    public let length: Int
    public let offset: Int?

    public init(length: Int, offset: Int?) {
        self.length = length
        self.offset = offset
    }

    public init?(parsing raw: String) {
        let parts = raw.split(separator: "@", maxSplits: 1)
        guard let length = Int(parts[0]) else { return nil }
        self.length = length
        self.offset = parts.count == 2 ? Int(parts[1]) : nil
    }
}

/// A media segment reference (`#EXTINF` + URI line) with its decorating tags.
public struct SegmentRef: Sendable, Equatable {
    public let uri: URL
    public let duration: Double
    public let title: String?
    public let byteRange: ByteRange?
    public let hasDiscontinuity: Bool
    public let programDateTime: String?
    public let lineNumber: Int

    public init(
        uri: URL,
        duration: Double,
        title: String?,
        byteRange: ByteRange?,
        hasDiscontinuity: Bool,
        programDateTime: String?,
        lineNumber: Int
    ) {
        self.uri = uri
        self.duration = duration
        self.title = title
        self.byteRange = byteRange
        self.hasDiscontinuity = hasDiscontinuity
        self.programDateTime = programDateTime
        self.lineNumber = lineNumber
    }
}

/// A master (multivariant) playlist.
public struct MasterPlaylist: Sendable, Equatable {
    public let variants: [VariantStream]
    public let iFrameStreams: [IFrameStream]
    public let renditions: [Rendition]
    public let version: Int?
    public let hasIndependentSegments: Bool

    public init(
        variants: [VariantStream],
        iFrameStreams: [IFrameStream],
        renditions: [Rendition],
        version: Int?,
        hasIndependentSegments: Bool
    ) {
        self.variants = variants
        self.iFrameStreams = iFrameStreams
        self.renditions = renditions
        self.version = version
        self.hasIndependentSegments = hasIndependentSegments
    }
}

/// A media playlist (a list of segments).
public struct MediaPlaylist: Sendable, Equatable {
    public let targetDuration: Double?
    public let mediaSequence: Int
    public let discontinuitySequence: Int
    public let segments: [SegmentRef]
    public let hasEndList: Bool
    public let playlistType: String?
    public let isIFramesOnly: Bool
    public let version: Int?
    public let hasIndependentSegments: Bool
    public let hasEncryptionKeys: Bool

    public init(
        targetDuration: Double?,
        mediaSequence: Int,
        discontinuitySequence: Int,
        segments: [SegmentRef],
        hasEndList: Bool,
        playlistType: String?,
        isIFramesOnly: Bool,
        version: Int?,
        hasIndependentSegments: Bool,
        hasEncryptionKeys: Bool
    ) {
        self.targetDuration = targetDuration
        self.mediaSequence = mediaSequence
        self.discontinuitySequence = discontinuitySequence
        self.segments = segments
        self.hasEndList = hasEndList
        self.playlistType = playlistType
        self.isIFramesOnly = isIFramesOnly
        self.version = version
        self.hasIndependentSegments = hasIndependentSegments
        self.hasEncryptionKeys = hasEncryptionKeys
    }
}

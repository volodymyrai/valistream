//
//  PlaylistInformation.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation

/// A one-time engineering summary of a loaded playlist.
public struct PlaylistInformation: Sendable, Equatable {
    /// The playlist summary kind.
    public enum Kind: String, Sendable, Equatable {
        case master
        case media
    }

    public let playlistID: String
    public let kind: Kind
    public let master: MasterInfo?
    public let media: MediaInfo?

    /// Creates a playlist information value.
    public init(
        playlistID: String,
        kind: Kind,
        master: MasterInfo?,
        media: MediaInfo?
    ) {
        self.playlistID = playlistID
        self.kind = kind
        self.master = master
        self.media = media
    }

    /// Builds a one-time summary from the first loaded playlist snapshot.
    public static func build(
        playlistID: String,
        playlist: Playlist,
        streamKind: StreamKind? = nil
    ) -> PlaylistInformation {
        switch playlist {
        case .master(let playlist):
            let bandwidths = playlist.variants.compactMap(\.bandwidth)
            let frameRates = playlist.variants.compactMap(\.frameRate)
            let resolutions = Set(playlist.variants.compactMap { variant in
                variant.resolution.map { "\($0.width)x\($0.height)" }
            }).sorted(by: resolutionAscending)
            let codecs = Set(playlist.variants.flatMap(\.codecs)).sorted()
            let renditionCounts = Dictionary(grouping: playlist.renditions.compactMap(\.type), by: { $0 })
                .mapValues(\.count)

            return PlaylistInformation(
                playlistID: playlistID,
                kind: .master,
                master: MasterInfo(
                    hlsVersion: playlist.version,
                    independentSegments: playlist.hasIndependentSegments,
                    variantCount: playlist.variants.count,
                    uniqueMediaPlaylistCount: Set(playlist.variants.map(\.uri)).count,
                    renditionCountsByType: renditionCounts,
                    iFrameStreamCount: playlist.iFrameStreams.count,
                    distinctResolutions: resolutions,
                    distinctCodecs: codecs,
                    minimumBandwidth: bandwidths.min(),
                    maximumBandwidth: bandwidths.max(),
                    minimumFrameRate: frameRates.min(),
                    maximumFrameRate: frameRates.max(),
                    sessionProtection: PlaylistProtection.classify(
                        method: playlist.sessionKeyMethod,
                        keyFormat: playlist.sessionKeyFormat
                    )
                ),
                media: nil
            )

        case .media(let playlist):
            let durations = playlist.segments.map(\.duration).sorted()
            let formats = Set(playlist.segments.compactMap { segment in
                let pathExtension = segment.uri.pathExtension.lowercased()
                return pathExtension.isEmpty ? nil : pathExtension
            }).sorted()

            return PlaylistInformation(
                playlistID: playlistID,
                kind: .media,
                master: nil,
                media: MediaInfo(
                    playlistType: mediaType(playlist: playlist, streamKind: streamKind),
                    hlsVersion: playlist.version,
                    segmentCount: playlist.segments.count,
                    totalListedDuration: durations.reduce(0, +),
                    targetDuration: playlist.targetDuration,
                    medianSegmentDuration: median(durations),
                    minimumSegmentDuration: durations.min(),
                    maximumSegmentDuration: durations.max(),
                    mediaSequence: playlist.mediaSequence,
                    discontinuitySequence: playlist.discontinuitySequence,
                    discontinuityCount: playlist.segments.count(where: \.hasDiscontinuity),
                    endList: playlist.hasEndList,
                    independentSegments: playlist.hasIndependentSegments,
                    iFramesOnly: playlist.isIFramesOnly,
                    segmentFormats: formats,
                    byteRangeUsed: playlist.segments.contains { $0.byteRange != nil },
                    programDateTimeAvailable: playlist.segments.contains { $0.programDateTime != nil },
                    protection: PlaylistProtection.classify(
                        method: playlist.keyMethod,
                        keyFormat: playlist.keyFormat
                    )
                )
            )
        }
    }

    private static func mediaType(playlist: MediaPlaylist, streamKind: StreamKind?) -> String {
        if let playlistType = playlist.playlistType?.uppercased() {
            return playlistType
        }
        if let streamKind {
            return streamKind.rawValue.uppercased()
        }
        if playlist.hasEndList {
            return "VOD"
        }

        return "Unknown"
    }

    private static func median(_ values: [Double]) -> Double? {
        guard values.isEmpty == false else { return nil }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }

        return values[middle]
    }

    private static func resolutionAscending(_ lhs: String, _ rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: "x").compactMap { Int($0) }
        let rhsParts = rhs.split(separator: "x").compactMap { Int($0) }

        return (lhsParts.last ?? 0, lhsParts.first ?? 0) < (rhsParts.last ?? 0, rhsParts.first ?? 0)
    }
}

/// Master-playlist fields shown in human-readable output.
public struct MasterInfo: Sendable, Equatable {
    public let hlsVersion: Int?
    public let independentSegments: Bool
    public let variantCount: Int
    public let uniqueMediaPlaylistCount: Int
    public let renditionCountsByType: [String: Int]
    public let iFrameStreamCount: Int
    public let distinctResolutions: [String]
    public let distinctCodecs: [String]
    public let minimumBandwidth: Int?
    public let maximumBandwidth: Int?
    public let minimumFrameRate: Double?
    public let maximumFrameRate: Double?
    public let sessionProtection: Protection

    /// Creates a master-playlist summary.
    public init(
        hlsVersion: Int?,
        independentSegments: Bool,
        variantCount: Int,
        uniqueMediaPlaylistCount: Int,
        renditionCountsByType: [String: Int],
        iFrameStreamCount: Int,
        distinctResolutions: [String],
        distinctCodecs: [String],
        minimumBandwidth: Int?,
        maximumBandwidth: Int?,
        minimumFrameRate: Double?,
        maximumFrameRate: Double?,
        sessionProtection: Protection
    ) {
        self.hlsVersion = hlsVersion
        self.independentSegments = independentSegments
        self.variantCount = variantCount
        self.uniqueMediaPlaylistCount = uniqueMediaPlaylistCount
        self.renditionCountsByType = renditionCountsByType
        self.iFrameStreamCount = iFrameStreamCount
        self.distinctResolutions = distinctResolutions
        self.distinctCodecs = distinctCodecs
        self.minimumBandwidth = minimumBandwidth
        self.maximumBandwidth = maximumBandwidth
        self.minimumFrameRate = minimumFrameRate
        self.maximumFrameRate = maximumFrameRate
        self.sessionProtection = sessionProtection
    }
}

/// Media-playlist fields shown in human-readable output.
public struct MediaInfo: Sendable, Equatable {
    public let playlistType: String
    public let hlsVersion: Int?
    public let segmentCount: Int
    public let totalListedDuration: Double
    public let targetDuration: Double?
    public let medianSegmentDuration: Double?
    public let minimumSegmentDuration: Double?
    public let maximumSegmentDuration: Double?
    public let mediaSequence: Int
    public let discontinuitySequence: Int
    public let discontinuityCount: Int
    public let endList: Bool
    public let independentSegments: Bool
    public let iFramesOnly: Bool
    public let segmentFormats: [String]
    public let byteRangeUsed: Bool
    public let programDateTimeAvailable: Bool
    public let protection: Protection

    /// Creates a media-playlist summary.
    public init(
        playlistType: String,
        hlsVersion: Int?,
        segmentCount: Int,
        totalListedDuration: Double,
        targetDuration: Double?,
        medianSegmentDuration: Double?,
        minimumSegmentDuration: Double?,
        maximumSegmentDuration: Double?,
        mediaSequence: Int,
        discontinuitySequence: Int,
        discontinuityCount: Int,
        endList: Bool,
        independentSegments: Bool,
        iFramesOnly: Bool,
        segmentFormats: [String],
        byteRangeUsed: Bool,
        programDateTimeAvailable: Bool,
        protection: Protection
    ) {
        self.playlistType = playlistType
        self.hlsVersion = hlsVersion
        self.segmentCount = segmentCount
        self.totalListedDuration = totalListedDuration
        self.targetDuration = targetDuration
        self.medianSegmentDuration = medianSegmentDuration
        self.minimumSegmentDuration = minimumSegmentDuration
        self.maximumSegmentDuration = maximumSegmentDuration
        self.mediaSequence = mediaSequence
        self.discontinuitySequence = discontinuitySequence
        self.discontinuityCount = discontinuityCount
        self.endList = endList
        self.independentSegments = independentSegments
        self.iFramesOnly = iFramesOnly
        self.segmentFormats = segmentFormats
        self.byteRangeUsed = byteRangeUsed
        self.programDateTimeAvailable = programDateTimeAvailable
        self.protection = protection
    }
}

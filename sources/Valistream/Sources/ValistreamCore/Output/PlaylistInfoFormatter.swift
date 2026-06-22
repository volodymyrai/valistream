//
//  PlaylistInfoFormatter.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation

/// One label and value in a surface-neutral playlist information block.
public struct PlaylistInfoField: Sendable, Equatable {
    public let label: String
    public let value: String

    /// Creates a playlist information field.
    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// A coherent group of adjacent playlist information fields.
public struct PlaylistInfoFieldGroup: Sendable, Equatable {
    public let title: String
    public let fields: [PlaylistInfoField]

    /// Creates a playlist information field group.
    public init(title: String, fields: [PlaylistInfoField]) {
        self.title = title
        self.fields = fields
    }
}

/// Produces the shared playlist information content used by terminal and report renderers.
public enum PlaylistInfoFormatter {
    /// Returns ordered field groups for a playlist information value.
    ///
    /// Used by the terminal status renderer (`StatusRenderer`). The markdown report renderer uses
    /// `reportHeaderFields(for:)` / `reportTimingFields(for:)` instead.
    public static func groups(for information: PlaylistInformation) -> [PlaylistInfoFieldGroup] {
        switch information.kind {
        case .master:
            information.master.map { masterGroups(playlistID: information.playlistID, info: $0) } ?? []
        case .media:
            information.media.map { mediaGroups(playlistID: information.playlistID, info: $0) } ?? []
        }
    }

    private static func masterGroups(playlistID: String, info: MasterInfo) -> [PlaylistInfoFieldGroup] {
        [
            PlaylistInfoFieldGroup(title: "Identity", fields: [
                field("Playlist ID", playlistID),
                field("Type", "Master"),
                field("HLS version", declared(info.hlsVersion)),
            ]),
            PlaylistInfoFieldGroup(title: "Structure", fields: [
                field("Independent segments", yesNo(info.independentSegments)),
                field("Variants", String(info.variantCount)),
                field("Media playlists", String(info.uniqueMediaPlaylistCount)),
                field("Renditions", renditionCounts(info.renditionCountsByType)),
                field("I-frame streams", String(info.iFrameStreamCount)),
            ]),
            PlaylistInfoFieldGroup(title: "Variant declarations", fields: [
                field("Resolutions", listed(info.distinctResolutions)),
                field("Codecs", listed(info.distinctCodecs)),
                field("Bandwidth", range(info.minimumBandwidth, info.maximumBandwidth)),
                field("Frame rate", range(info.minimumFrameRate, info.maximumFrameRate)),
            ]),
            PlaylistInfoFieldGroup(title: "Protection", fields: [
                field("Session protection", info.sessionProtection.description),
            ]),
        ]
    }

    private static func mediaGroups(playlistID: String, info: MediaInfo) -> [PlaylistInfoFieldGroup] {
        [
            PlaylistInfoFieldGroup(title: "Identity", fields: [
                field("Playlist ID", playlistID),
                field("Type", info.playlistType),
                field("HLS version", declared(info.hlsVersion)),
            ]),
            PlaylistInfoFieldGroup(title: "Timing", fields: [
                field("Segments", String(info.segmentCount)),
                field("Total duration", seconds(info.totalListedDuration)),
                field("Target duration", info.targetDuration.map(seconds) ?? "Not declared"),
                field("Segment duration", segmentDuration(info)),
            ]),
            PlaylistInfoFieldGroup(title: "Sequence", fields: [
                field("Media sequence", String(info.mediaSequence)),
                field("Discontinuity sequence", String(info.discontinuitySequence)),
                field("Discontinuities", String(info.discontinuityCount)),
            ]),
            PlaylistInfoFieldGroup(title: "Features", fields: [
                field("End list", yesNo(info.endList)),
                field("Independent segments", yesNo(info.independentSegments)),
                field("I-frames only", yesNo(info.iFramesOnly)),
                field("Segment format", listed(info.segmentFormats)),
                field("Byte ranges", yesNo(info.byteRangeUsed)),
                field("Program date time", yesNo(info.programDateTimeAvailable)),
            ]),
            PlaylistInfoFieldGroup(title: "Protection", fields: [
                field("Protection", info.protection.description),
            ]),
        ]
    }

    /// Returns flat report-header bullets for a playlist information value (master or media),
    /// excluding the playlist ID (the caller renders that in the block heading instead).
    public static func reportHeaderFields(for information: PlaylistInformation?) -> [PlaylistInfoField] {
        guard let information else { return [] }
        switch information.kind {
        case .master:
            return information.master.map(masterHeaderFields) ?? []
        case .media:
            return information.media.map(mediaHeaderFields) ?? []
        }
    }

    /// Returns the merged Timing+Sequence bullets for a media playlist, or `nil` for master
    /// playlists (which have no per-segment timing to report).
    public static func reportTimingFields(for information: PlaylistInformation?) -> [PlaylistInfoField]? {
        guard let information, information.kind == .media else { return nil }
        return information.media.map(mediaTimingFields)
    }

    private static func masterHeaderFields(_ info: MasterInfo) -> [PlaylistInfoField] {
        [
            field("Type", "Master"),
            field("HLS version", declared(info.hlsVersion)),
            field("Independent segments", yesNo(info.independentSegments)),
            field("Variants", String(info.variantCount)),
            field("Media playlists", String(info.uniqueMediaPlaylistCount)),
            field("Renditions", renditionCounts(info.renditionCountsByType)),
            field("I-frame streams", String(info.iFrameStreamCount)),
            field("Resolutions", listed(info.distinctResolutions)),
            field("Codecs", listed(info.distinctCodecs)),
            field("Bandwidth", range(info.minimumBandwidth, info.maximumBandwidth)),
            field("Frame rate", range(info.minimumFrameRate, info.maximumFrameRate)),
            field("Session protection", info.sessionProtection.description),
        ]
    }

    private static func mediaHeaderFields(_ info: MediaInfo) -> [PlaylistInfoField] {
        [
            field("Type", info.playlistType),
            field("HLS version", declared(info.hlsVersion)),
            field("End list", yesNo(info.endList)),
            field("Independent segments", yesNo(info.independentSegments)),
            field("I-frames only", yesNo(info.iFramesOnly)),
            field("Segment format", listed(info.segmentFormats)),
            field("Byte ranges", yesNo(info.byteRangeUsed)),
            field("Program date time", yesNo(info.programDateTimeAvailable)),
            field("Protection", info.protection.description),
        ]
    }

    private static func mediaTimingFields(_ info: MediaInfo) -> [PlaylistInfoField] {
        [
            field("Segments", String(info.segmentCount)),
            field("Total duration", seconds(info.totalListedDuration)),
            field("Target duration", info.targetDuration.map(seconds) ?? "Not declared"),
            field("Segment duration", segmentDuration(info)),
            field("Media sequence", String(info.mediaSequence)),
            field("Discontinuity sequence", String(info.discontinuitySequence)),
            field("Discontinuities", String(info.discontinuityCount)),
        ]
    }

    private static func field(_ label: String, _ value: String) -> PlaylistInfoField {
        PlaylistInfoField(label: label, value: value)
    }

    private static func declared(_ value: Int?) -> String {
        value.map(String.init) ?? "Not declared"
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private static func listed(_ values: [String]) -> String {
        values.isEmpty ? "Unknown" : values.joined(separator: ", ")
    }

    private static func renditionCounts(_ counts: [String: Int]) -> String {
        guard counts.isEmpty == false else { return "None" }
        return counts.keys.sorted().map { "\($0.lowercased()) \(counts[$0] ?? 0)" }.joined(separator: ", ")
    }

    private static func range<T: Comparable & CustomStringConvertible>(_ minimum: T?, _ maximum: T?) -> String {
        guard let minimum, let maximum else { return "Not declared" }
        return minimum == maximum ? minimum.description : "\(minimum)-\(maximum)"
    }

    private static func segmentDuration(_ info: MediaInfo) -> String {
        guard let median = info.medianSegmentDuration,
              let minimum = info.minimumSegmentDuration,
              let maximum = info.maximumSegmentDuration else {
            return "Unknown"
        }

        return "median \(number(median)) s, range \(number(minimum))-\(number(maximum)) s"
    }

    private static func seconds(_ value: Double) -> String {
        "\(number(value)) s"
    }

    private static func number(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .precision(.fractionLength(0...3))
        )
    }
}

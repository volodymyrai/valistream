//
//  SessionArchive.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Writes session artifacts to disk: verbatim playlist bodies and JSON metadata sidecars
/// (data-model.md Archive Layout, research §10).
///
/// Every store call is actor-isolated so concurrent monitoring tasks write without races.
/// The session folder is created on init; subsequent stores add content incrementally so
/// a crash or abort leaves everything written so far intact.
public actor SessionArchive {
    // MARK: - Nested types

    /// One entry in the artifact index: request id, final URL, and relative body/meta paths.
    public struct IndexEntry: Sendable, Equatable {
        public let requestId: String
        public let url: URL
        public let bodyPath: String
        public let metaPath: String

        public init(requestId: String, url: URL, bodyPath: String, metaPath: String) {
            self.requestId = requestId
            self.url = url
            self.bodyPath = bodyPath
            self.metaPath = metaPath
        }
    }



    // MARK: - Lets & Vars

    /// The created session folder — stable after init, accessible without actor isolation.
    public nonisolated let sessionFolder: URL

    /// Accumulated request index; grows as artifacts are stored.
    public private(set) var artifactIndex: [IndexEntry] = []

    private var requestCounter = 0
    private var refreshCounts: [String: Int] = [:]

    private static let metaEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            try container.encode(ReportTimestampFormatter.format(date, timeZone: .gmt))
        }
        return encoder
    }()

    static let metaDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let str = try container.decode(String.self)
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fmt.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(str)")
        }
        return decoder
    }()



    // MARK: - Lifecycle

    public init(sessionID: String, outputDir: URL) throws {
        self.sessionFolder = outputDir.appending(path: sessionID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
    }



    // MARK: - Public

    /// Archives one playlist fetch: writes the verbatim body and a JSON sidecar.
    ///
    /// Body at `playlists/<playlistID>/NNNNNN.m3u8`; sidecar at
    /// `playlists/<playlistID>/NNNNNN.meta.json`. Returns the populated `ArtifactRecord` whose
    /// `bodyPath` is relative to the session folder.
    /// Archives one playlist fetch using a self-identifying snapshot label.
    ///
    /// Body and sidecar paths use `playlists/<playlistID>/<playlistID>_<index>` and remain relative
    /// to the session folder in the returned record and artifact index.
    /// - Parameter requestURL: The URL the playlist was requested under. Used as the artifact index
    ///   join key so findings (keyed on the requested URL) resolve even when the fetch was redirected.
    ///   Defaults to `result.url` (the redirected final URL) when not supplied.
    @discardableResult
    public func store(result: FetchResult, requestURL: URL? = nil, playlistID: String) throws -> ArtifactRecord {
        requestCounter += 1
        let requestId = "r\(requestCounter)"
        let refreshIndex = refreshCounts[playlistID, default: 0]
        refreshCounts[playlistID] = refreshIndex + 1
        let snapshot = SnapshotID.label(id: playlistID, index: refreshIndex)
        let playlistDir = sessionFolder.appending(path: "playlists/\(playlistID)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: playlistDir, withIntermediateDirectories: true)
        let bodyRelPath = "playlists/\(playlistID)/\(snapshot).m3u8"
        let metaRelPath = "playlists/\(playlistID)/\(snapshot).meta.json"
        try result.body.write(to: sessionFolder.appending(path: bodyRelPath))
        let record = ArtifactRecord(requestId: requestId, bodyPath: bodyRelPath, result: result)
        let metaData = try SessionArchive.metaEncoder.encode(record)
        try metaData.write(to: sessionFolder.appending(path: metaRelPath))
        artifactIndex.append(IndexEntry(
            requestId: requestId,
            url: requestURL ?? result.url,
            bodyPath: bodyRelPath,
            metaPath: metaRelPath
        ))

        return record
    }


    /// Atomically replaces `url` with `data` using a temp-file + `FileManager.replaceItemAt`.
    ///
    /// Concurrent readers see either the previous complete file or the new complete file — never
    /// a partially written document (FR-022).
    public nonisolated func writeAtomically(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: tmp)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}

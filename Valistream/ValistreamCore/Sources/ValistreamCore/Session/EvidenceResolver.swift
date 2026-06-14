//
//  EvidenceResolver.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

import Foundation

/// Archived playlist bodies that provide evidence for a finding.
public enum EvidenceReference: Sendable, Equatable {
    /// One archived body for a single-snapshot finding.
    case single(path: String)

    /// Consecutive archived bodies for a continuity finding.
    ///
    /// A `nil` path identifies the missing side of a partially captured pair.
    case pair(older: String?, newer: String?)

    /// The playlist ID whose producing fetch did not capture a body.
    case unavailable(id: String)

    /// The archived paths that are available for inspection.
    public var availablePaths: [String] {
        switch self {
        case .single(let path):
            [path]
        case .pair(let older, let newer):
            [older, newer].compactMap { $0 }
        case .unavailable:
            []
        }
    }
}


public extension EvidenceReference {
    /// Returns the terminal message for a finding using this evidence reference.
    func terminalMessage(for finding: Finding) -> String {
        let refreshIndex = max(finding.refreshIndex ?? 0, 0)
        switch self {
        case .single(let path):
            let snapshot = URL(filePath: path).deletingPathExtension().lastPathComponent

            return "\(snapshot) \(finding.message) · evidence: \(path)"
        case .pair(let older, let newer):
            let id = evidenceID(from: older ?? newer) ?? "playlist"
            var references = [older, newer].compactMap { $0 }
            if older == nil {
                references.append("older snapshot unavailable")
            }
            if newer == nil {
                references.append("newer snapshot unavailable")
            }

            return "\(id) discontinuity \(finding.message) · evidence: \(references.joined(separator: ", "))"
        case .unavailable(let id):
            let snapshot = SnapshotID.label(id: id, index: refreshIndex)

            return "\(snapshot) — no body captured for \(id)"
        }
    }



    // MARK: - Private

    private func evidenceID(from path: String?) -> String? {
        guard let path else { return nil }

        return SnapshotID.parse(URL(filePath: path).deletingPathExtension().lastPathComponent)?.id
    }
}

/// Resolves findings to captured playlist bodies without changing the report schema.
public struct EvidenceResolver: Sendable {
    /// Creates an evidence resolver.
    public init() {}

    /// Resolves a finding by joining its resource URL and refresh index to the artifact index.
    ///
    /// - Parameters:
    ///   - finding: The finding that needs archived evidence.
    ///   - aliases: The session's presentation ID registry.
    ///   - artifactIndex: The archive entries captured for the session.
    ///   - fallbackID: The deterministic ID used when neither registry nor archive can identify the playlist.
    /// - Returns: The available evidence path or paths, or an unavailable reference naming the playlist ID.
    public func resolve(
        _ finding: Finding,
        aliases: AliasRegistry,
        artifactIndex: [SessionArchive.IndexEntry],
        fallbackID: String = "master"
    ) -> EvidenceReference {
        let entries = artifactIndex.filter { $0.url == finding.resource }
        let id = aliases.alias(for: finding.resource)?.alias
            ?? entries.lazy.compactMap { playlistID(from: $0.bodyPath) }.first
            ?? fallbackID
        let refreshIndex = max(finding.refreshIndex ?? 0, 0)
        if finding.category == .continuity {
            let older = refreshIndex > 0 ? bodyPath(at: refreshIndex - 1, in: entries) : nil
            let newer = bodyPath(at: refreshIndex, in: entries)
            if older == nil, newer == nil {
                return .unavailable(id: id)
            }

            return .pair(older: older, newer: newer)
        }
        guard let path = bodyPath(at: refreshIndex, in: entries) else {
            return .unavailable(id: id)
        }

        return .single(path: path)
    }



    // MARK: - Private

    private func bodyPath(at index: Int, in entries: [SessionArchive.IndexEntry]) -> String? {
        entries.first { entry in
            guard let parsed = SnapshotID.parse(snapshotLabel(from: entry.bodyPath)) else { return false }

            return parsed.index == index
        }?.bodyPath
    }

    private func playlistID(from path: String) -> String? {
        SnapshotID.parse(snapshotLabel(from: path))?.id
    }

    private func snapshotLabel(from path: String) -> String {
        URL(filePath: path).deletingPathExtension().lastPathComponent
    }
}

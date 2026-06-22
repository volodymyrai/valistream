//
//  PlaylistSelection.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Resolves which discovered media playlists a session monitors (FR-018).
///
/// Selection is driven non-interactively by `--select` patterns (matched against a playlist's id,
/// group id, name, or URL) or `--all`; on an interactive terminal the CLI presents a checklist
/// instead (research §7). This type holds the pure resolution used by both paths and by
/// non-interactive runs, so the matching logic is testable without a terminal.
public struct PlaylistSelection: Sendable {
    // MARK: - Nested types

    /// A media playlist that may be selected for monitoring.
    public struct Candidate: Sendable, Equatable, Identifiable {
        public let id: String
        public let role: PlaylistRole
        public let url: URL
        public let groupID: String?
        public let name: String?
        public let alias: String?

        public init(id: String, role: PlaylistRole, url: URL, groupID: String? = nil, name: String? = nil, alias: String? = nil) {
            self.id = id
            self.role = role
            self.url = url
            self.groupID = groupID
            self.name = name
            self.alias = alias
        }

        /// Whether any of the searchable fields contains `pattern` (case- and diacritic-insensitive).
        func matches(_ pattern: String) -> Bool {
            let fields = [id, groupID, name, alias, url.absoluteString].compactMap { $0 }
            return fields.contains { $0.localizedStandardContains(pattern) }
        }
    }



    // MARK: - Public

    /// Resolves the candidates to monitor.
    ///
    /// `nil` patterns (the default, and the `--all` case) select every candidate; a non-`nil`
    /// pattern list keeps the candidates matching at least one pattern, preserving discovery order.
    /// An empty result means every playlist was deselected — the caller short-circuits to finishing
    /// with a note (data-model.md empty-selection edge case).
    public static func resolve(_ candidates: [Candidate], patterns: [String]?) -> [Candidate] {
        guard let patterns, patterns.isEmpty == false else {
            return candidates
        }
        return candidates.filter { candidate in
            patterns.contains { candidate.matches($0) }
        }
    }

    /// Builds the monitor candidates for a stream: one per discovered media reference, or a single
    /// direct-media candidate when the input is itself a media playlist (no master). Returns empty
    /// when there is neither — e.g. a master that referenced no usable media playlists.
    public static func candidates(references: [PlaylistReference], directMediaURL: URL?, aliasFor: (URL) -> String? = { _ in nil }) -> [Candidate] {
        guard references.isEmpty == false else {
            guard let directMediaURL else { return [] }
            return [Candidate(id: "media", role: .variant, url: directMediaURL, alias: aliasFor(directMediaURL))]
        }
        return references.enumerated().map { index, reference in
            Candidate(
                id: "\(reference.role.rawValue)-\(index)",
                role: reference.role,
                url: reference.url,
                groupID: reference.groupID,
                name: reference.name,
                alias: aliasFor(reference.url)
            )
        }
    }
}

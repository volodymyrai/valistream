//
//  PromptberrySelection.swift
//  Valistream
//
//  Created by Volodymyr Akimenko on 13/06/2026.
//

import ValistreamCore
import Foundation
import Promptberry

struct PromptberrySelection {

    // MARK: - Lets & Vars

    let candidates: [PlaylistSelection.Candidate]



    // MARK: - Internal

    func run() -> [PlaylistSelection.Candidate] {
        guard !candidates.isEmpty else { return [] }

        let options = candidates.map { SelectOption(value: $0.id, label: label($0)) }

        do {
            let selectedIDs = try Promptberry.multiselect(
                "Select playlists to monitor:",
                options: options,
                initialValues: Set(candidates.map(\.id)),
                required: false
            )
            return candidates.filter { selectedIDs.contains($0.id) }
        } catch {
            Promptberry.cancel("Playlist selection cancelled.")
            Foundation.exit(0)
        }
    }



    // MARK: - Private

    private func label(_ c: PlaylistSelection.Candidate) -> String {
        let detail = c.name ?? c.url.lastPathComponent
        return "\(c.id) (\(c.role.rawValue)) — \(detail)"
    }
}

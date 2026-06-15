//
//  PlaylistLifecycleEvent.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation

/// A playlist availability or roster transition recorded at occurrence time.
public struct PlaylistLifecycleEvent: Sendable, Equatable {
    /// The supported playlist lifecycle transitions.
    public enum Kind: String, CaseIterable, Sendable, Equatable {
        case unavailable
        case recovered
        case added
        case removed
        case identityChanged
    }

    public let playlistID: String
    public let at: Date
    public let kind: Kind

    /// Creates a playlist lifecycle event.
    public init(playlistID: String, at: Date, kind: Kind) {
        self.playlistID = playlistID
        self.at = at
        self.kind = kind
    }
}

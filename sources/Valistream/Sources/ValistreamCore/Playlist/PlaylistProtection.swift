//
//  PlaylistProtection.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation

/// A human-readable classification of declared playlist protection.
public enum Protection: Sendable, Equatable, CustomStringConvertible {
    case none
    case encryptedAES128
    case drm(keyFormat: String)

    /// The required human-readable protection vocabulary.
    public var description: String {
        switch self {
        case .none:
            "None"
        case .encryptedAES128:
            "Encrypted (AES-128)"
        case .drm(let keyFormat):
            "DRM (\(keyFormat))"
        }
    }
}

/// Classifies HLS key declarations without changing validation behavior.
public enum PlaylistProtection {
    /// Returns the protection represented by a key method and optional key format.
    public static func classify(method: String?, keyFormat: String?) -> Protection {
        guard let method = method?.uppercased(), method != "NONE" else { return .none }
        let normalizedFormat = keyFormat?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesIdentityFormat = normalizedFormat == nil || normalizedFormat?.lowercased() == "identity"

        if method == "AES-128", usesIdentityFormat {
            return .encryptedAES128
        }

        return .drm(keyFormat: normalizedFormat ?? method)
    }
}

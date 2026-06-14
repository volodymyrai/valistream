//
//  SnapshotID.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 14/06/2026.
//

/// A namespace for formatting and parsing playlist snapshot identifiers.
public enum SnapshotID {
    /// Returns the snapshot label for a playlist ID and zero-based refresh index.
    public static func label(id: String, index: Int) -> String {
        "\(id)_\(index)"
    }

    /// Parses a snapshot label into its playlist ID and zero-based refresh index.
    public static func parse(_ label: String) -> (id: String, index: Int)? {
        guard let separator = label.lastIndex(of: "_") else { return nil }
        let id = label[..<separator]
        let indexStart = label.index(after: separator)
        let indexText = label[indexStart...]
        guard id.isEmpty == false, let index = Int(indexText), index >= 0 else { return nil }

        return (String(id), index)
    }
}

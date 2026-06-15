//
//  PresentationRole.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

/// A terminal-safe ANSI style from the standard 8/16-color palette.
public enum TerminalANSIStyle: Sendable, Equatable {
    case bold
    case red
    case yellow
    case green
    case cyan
    case dim
}

/// The semantic purpose of human-readable terminal text.
public enum PresentationRole: CaseIterable, Sendable, Equatable {
    case heading
    case identifier
    case success
    case progress
    case metadata
    case warning
    case error
    case evidencePath
    case summary

    /// The restrained terminal style associated with this role.
    public var ansiStyle: TerminalANSIStyle {
        switch self {
        case .heading, .summary:
            .bold
        case .identifier, .evidencePath:
            .cyan
        case .success:
            .green
        case .progress, .metadata:
            .dim
        case .warning:
            .yellow
        case .error:
            .red
        }
    }

    /// A plain-text description that preserves the role when styling is unavailable.
    public var plainTextMeaning: String {
        switch self {
        case .heading: "heading"
        case .identifier: "identifier"
        case .success: "successful outcome"
        case .progress: "progress"
        case .metadata: "secondary detail"
        case .warning: "warning"
        case .error: "error"
        case .evidencePath: "evidence path"
        case .summary: "summary"
        }
    }
}

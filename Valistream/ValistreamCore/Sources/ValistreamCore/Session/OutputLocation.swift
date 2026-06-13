//
//  OutputLocation.swift
//  ValistreamCore
//

import Foundation

/// Resolves the absolute per-session output folder and validates writability before any fetch
/// (US3: FR-016, FR-018, FR-019, FR-020).
public struct OutputLocation: Sendable {
    /// Absolute base directory (the parent of all session subfolders).
    public let baseDirectory: URL

    /// Absolute per-session folder: `baseDirectory/<sessionID>`.
    public let sessionFolder: URL

    /// The platform default base — `~/.valistream/sessions/` on macOS.
    public static func defaultBase() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".valistream/sessions", directoryHint: .isDirectory)
    }

    /// Resolves the absolute base, creates it if needed, verifies it is writable, and returns
    /// an `OutputLocation` with `sessionFolder = base/<sessionID>`.
    ///
    /// - Parameter outputDir: Base directory. `nil` → `defaultBase()`. Relative paths are resolved
    ///   against the current working directory (FR-020).
    /// - Parameter sessionID: Unique session identifier; becomes the subfolder name.
    /// - Throws: `OutputLocationError` when the base cannot be created or written to (FR-019).
    public static func resolve(
        outputDir: URL?,
        sessionID: String,
        fileManager: FileManager = .default
    ) throws -> OutputLocation {
        var base = outputDir ?? defaultBase()

        // Resolve relative paths against CWD (FR-020).
        if !base.path.hasPrefix("/") {
            base = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
                .appending(path: base.path, directoryHint: .isDirectory)
        }
        base = base.standardizedFileURL

        // Create base directory if it does not exist.
        do {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            throw OutputLocationError(
                description: "Cannot create output directory '\(base.path(percentEncoded: false))': \(error.localizedDescription)"
            )
        }

        // Writability pre-flight: attempt a throw-away write (FR-019).
        let probe = base.appending(path: ".valistream-check-\(UUID().uuidString)")
        do {
            try Data().write(to: probe)
            try fileManager.removeItem(at: probe)
        } catch {
            throw OutputLocationError(
                description: "Output directory '\(base.path(percentEncoded: false))' is not writable: \(error.localizedDescription)"
            )
        }

        return OutputLocation(
            baseDirectory: base,
            sessionFolder: base.appending(path: sessionID, directoryHint: .isDirectory)
        )
    }

    private init(baseDirectory: URL, sessionFolder: URL) {
        self.baseDirectory = baseDirectory
        self.sessionFolder = sessionFolder
    }
}

/// Thrown when output directory resolution or writability pre-flight fails (FR-019).
public struct OutputLocationError: Error, Sendable, CustomStringConvertible {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

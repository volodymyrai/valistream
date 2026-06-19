//
//  FindingsLog.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Appends findings to a `findings.jsonl` file as the session produces them (research §10).
///
/// Each call writes one complete JSON line and flushes to the file handle so every finding
/// is durable even if the process is interrupted mid-session. Safe to call from a single
/// serialised context (e.g. within a `ValidationSession` actor).
public final class FindingsLog {
    // MARK: - Lets & Vars

    private let fileHandle: FileHandle



    // MARK: - Lifecycle

    public init(folder: URL) throws {
        let url = folder.appending(path: "findings.jsonl")
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: url)
    }

    deinit {
        try? fileHandle.close()
    }



    // MARK: - Public

    /// Appends one finding as a JSON line, terminated by `\n`.
    public func append(_ finding: Finding) throws {
        var data = try Finding.jsonEncoder.encode(finding)
        data.append(0x0A)  // '\n'
        try fileHandle.write(contentsOf: data)
    }
}

//
//  OutputRecorder.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import os

/// Thread-safe output sink for terminal renderer integration tests.
final class OutputRecorder: @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    var standardOutput: String {
        storage.withLock(\.standardOutput)
    }

    var standardError: String {
        storage.withLock(\.standardError)
    }

    func writeStandardOutput(_ text: String) {
        storage.withLock { $0.standardOutput += text }
    }

    func writeStandardError(_ text: String) {
        storage.withLock { $0.standardError += text }
    }

    private struct Storage {
        var standardOutput = ""
        var standardError = ""
    }
}

//
//  DiskSpaceWatcher.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// Queries available disk space on the session volume and classifies it against archive thresholds
/// (research §11: warn < 5 GB, stop < 500 MB).
///
/// Inject a custom `capacityProvider` in tests to exercise threshold logic without real filesystem
/// calls.
public struct DiskSpaceWatcher: Sendable {
    // MARK: - Nested types

    /// The result of a disk-space check.
    public enum CheckResult: Sendable, Equatable {
        /// Available space is sufficient (> 5 GB).
        case ok
        /// Space is low (≤ 5 GB but > 500 MB); callers should emit a warning finding.
        case low(availableBytes: Int)
        /// Space is critically low (≤ 500 MB); callers should stop archiving.
        case critical(availableBytes: Int)
    }

    private static let warnThreshold = 5 * 1_073_741_824     // 5 GiB
    private static let stopThreshold = 500 * 1_048_576        // 500 MiB



    // MARK: - Lets & Vars

    private let capacityProvider: @Sendable () throws -> Int



    // MARK: - Lifecycle

    /// Queries `volumeAvailableCapacityForImportantUsage` on the given URL's volume.
    public init(volumeURL: URL) {
        self.init {
            let values = try volumeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return Int(values.volumeAvailableCapacityForImportantUsage ?? 0)
        }
    }

    /// Init with an injected capacity provider for deterministic testing.
    public init(capacityProvider: @escaping @Sendable () throws -> Int) {
        self.capacityProvider = capacityProvider
    }



    // MARK: - Public

    /// Queries available capacity and returns the matching threshold result.
    public func check() throws -> CheckResult {
        let available = try capacityProvider()
        if available <= Self.stopThreshold {
            return .critical(availableBytes: available)
        }
        if available <= Self.warnThreshold {
            return .low(availableBytes: available)
        }
        return .ok
    }
}

//
//  DiskSpaceWatcherTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite(.tags(.archive))
struct DiskSpaceWatcherTests {
    // MARK: - ok

    @Test("returns ok when available space is well above the 5 GB threshold")
    func okWhenPlentiful() throws {
        let watcher = DiskSpaceWatcher { 10 * 1_073_741_824 }  // 10 GiB
        #expect(try watcher.check() == .ok)
    }

    @Test("returns ok when available is exactly one byte above 5 GB threshold")
    func okAtThresholdBoundary() throws {
        let watcher = DiskSpaceWatcher { 5 * 1_073_741_824 + 1 }
        #expect(try watcher.check() == .ok)
    }



    // MARK: - low

    @Test("returns low when available is exactly the 5 GB threshold")
    func lowAtExactThreshold() throws {
        let watcher = DiskSpaceWatcher { 5 * 1_073_741_824 }
        if case .low(let bytes) = try watcher.check() {
            #expect(bytes == 5 * 1_073_741_824)
        }
        else {
            Issue.record("expected .low")
        }
    }

    @Test("returns low for 2 GB available")
    func lowAt2GB() throws {
        let bytes = 2 * 1_073_741_824
        let watcher = DiskSpaceWatcher { bytes }
        if case .low(let available) = try watcher.check() {
            #expect(available == bytes)
        }
        else {
            Issue.record("expected .low")
        }
    }

    @Test("returns low when available is exactly one byte above the 500 MB stop threshold")
    func lowJustAboveStopThreshold() throws {
        let watcher = DiskSpaceWatcher { 500 * 1_048_576 + 1 }
        if case .low = try watcher.check() { }
        else { Issue.record("expected .low") }
    }



    // MARK: - critical

    @Test("returns critical when available is exactly the 500 MB threshold")
    func criticalAtExactThreshold() throws {
        let bytes = 500 * 1_048_576
        let watcher = DiskSpaceWatcher { bytes }
        if case .critical(let available) = try watcher.check() {
            #expect(available == bytes)
        }
        else {
            Issue.record("expected .critical")
        }
    }

    @Test("returns critical for 100 MB available")
    func criticalAt100MB() throws {
        let bytes = 100 * 1_048_576
        let watcher = DiskSpaceWatcher { bytes }
        if case .critical(let available) = try watcher.check() {
            #expect(available == bytes)
        }
        else {
            Issue.record("expected .critical")
        }
    }

    @Test("returns critical for zero bytes available")
    func criticalAtZero() throws {
        let watcher = DiskSpaceWatcher { 0 }
        if case .critical = try watcher.check() { }
        else { Issue.record("expected .critical") }
    }



    // MARK: - error propagation

    @Test("propagates error from capacity provider")
    func propagatesProviderError() {
        struct ProviderError: Error {}
        let watcher = DiskSpaceWatcher { throw ProviderError() }
        #expect(throws: ProviderError.self) {
            _ = try watcher.check()
        }
    }
}

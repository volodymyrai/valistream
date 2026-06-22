//
//  SessionConfigTests.swift
//  ValistreamCoreTests
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite("SessionConfig", .tags(.session), .timeLimit(.minutes(1)))
struct SessionConfigTests {

    @Test("default outputDir is nil so OutputLocation applies the platform default base")
    func defaultOutputDirIsNil() {
        // Regression guard: a leaked literal "./valistream-sessions" default here once forced
        // artifacts into the working directory instead of ~/.valistream/sessions/.
        #expect(SessionConfig().outputDir == nil)
    }

    @Test("explicit outputDir is preserved")
    func explicitOutputDirPreserved() {
        let dir = URL(fileURLWithPath: "/tmp/custom-sessions", isDirectory: true)
        #expect(SessionConfig(outputDir: dir).outputDir == dir)
    }
}

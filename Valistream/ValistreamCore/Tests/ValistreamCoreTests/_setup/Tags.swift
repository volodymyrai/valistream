//
//  Tags.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Testing

/// Area tags for `ValistreamCore` unit suites.
///
/// Baseline tags (`edgeCase`, `slow`) plus one area tag per source module, per `unit-testing.md` §13.
/// Apply at least one area tag on every suite.
///
/// Example:
/// ```swift
/// @Suite(.tags(.playlist))
/// struct M3U8TokenizerTests { }
/// ```
extension Tag {
    @Tag static var edgeCase: Self
    @Tag static var slow: Self
    @Tag static var playlist: Self
    @Tag static var validation: Self
    @Tag static var monitoring: Self
    @Tag static var networking: Self
    @Tag static var archive: Self
    @Tag static var segment: Self
    @Tag static var output: Self
    @Tag static var session: Self
}

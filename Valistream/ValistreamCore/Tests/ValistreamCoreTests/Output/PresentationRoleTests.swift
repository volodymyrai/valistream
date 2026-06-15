//
//  PresentationRoleTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite(.tags(.output))
struct PresentationRoleTests {
    @Test(
        "roles map to the restrained terminal palette",
        arguments: [
            (PresentationRole.heading, TerminalANSIStyle.bold),
            (.identifier, .cyan),
            (.success, .green),
            (.progress, .dim),
            (.metadata, .dim),
            (.warning, .yellow),
            (.error, .red),
            (.evidencePath, .cyan),
            (.summary, .bold),
        ]
    )
    func roleMapsToANSIStyle(role: PresentationRole, expected: TerminalANSIStyle) {
        #expect(role.ansiStyle == expected)
    }

    @Test("every presentation role has a plain-text meaning")
    func rolesHavePlainTextMeaning() {
        for role in PresentationRole.allCases {
            #expect(role.plainTextMeaning.isEmpty == false)
        }
    }
}

//
//  PlaylistProtectionTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite(.tags(.playlist))
struct PlaylistProtectionTests {
    struct ClassificationCase: CustomTestStringConvertible {
        let method: String?
        let keyFormat: String?
        let expected: Protection

        var testDescription: String {
            "\(method ?? "nil") / \(keyFormat ?? "nil")"
        }
    }

    @Test("classifies declared key metadata", arguments: [
        ClassificationCase(method: nil, keyFormat: nil, expected: .none),
        ClassificationCase(method: "NONE", keyFormat: nil, expected: .none),
        ClassificationCase(method: "AES-128", keyFormat: nil, expected: .encryptedAES128),
        ClassificationCase(method: "AES-128", keyFormat: "identity", expected: .encryptedAES128),
        ClassificationCase(
            method: "SAMPLE-AES",
            keyFormat: "com.apple.streamingkeydelivery",
            expected: .drm(keyFormat: "com.apple.streamingkeydelivery")
        ),
        ClassificationCase(method: "SAMPLE-AES", keyFormat: nil, expected: .drm(keyFormat: "SAMPLE-AES")),
    ])
    func classifies(_ classification: ClassificationCase) {
        let result = PlaylistProtection.classify(
            method: classification.method,
            keyFormat: classification.keyFormat
        )

        #expect(result == classification.expected)
    }

    @Test("protection values use the required display vocabulary", arguments: [
        (Protection.none, "None"),
        (.encryptedAES128, "Encrypted (AES-128)"),
        (.drm(keyFormat: "com.widevine"), "DRM (com.widevine)"),
    ])
    func displayVocabulary(protection: Protection, expected: String) {
        #expect(protection.description == expected)
    }
}

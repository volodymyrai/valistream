//
//  PlaylistLifecycleEventTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 15/06/2026.
//

import Foundation
import Testing
@testable import ValistreamCore

@Suite(.tags(.session))
struct PlaylistLifecycleEventTests {
    @Test("each lifecycle kind carries playlist identity and occurrence time", arguments: PlaylistLifecycleEvent.Kind.allCases)
    func carriesIdentityAndTime(kind: PlaylistLifecycleEvent.Kind) {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let event = PlaylistLifecycleEvent(playlistID: "video-1", at: date, kind: kind)

        #expect(event.playlistID == "video-1")
        #expect(event.at == date)
        #expect(event.kind == kind)
    }
}

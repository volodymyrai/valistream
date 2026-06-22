//
//  ScriptedStreamFetcher.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import os
import ValistreamCore

/// An in-process ``StreamFetching`` stub that plays scripted responses, so integration tests can
/// exercise the full session engine deterministically with no sockets (research §8).
///
/// Stubs may be fixed (the same reply every fetch) or a timeline keyed to a ``ManualClock`` — the
/// fetch returns the latest timeline entry whose offset has elapsed, modelling a live sliding
/// window advanced by the test clock. Every requested URL is logged for assertions.
///
/// Example:
/// ```swift
/// let fetcher = ScriptedStreamFetcher()
/// fetcher.stub(masterURL, body: masterPlaylistText)
/// let result = await fetcher.fetch(masterURL)
/// ```
final class ScriptedStreamFetcher: StreamFetching, @unchecked Sendable {
    // MARK: - Nested types

    /// A scripted reply for a URL.
    enum Reply {
        case body(String, status: Int = 200)
        case data(Data, status: Int = 200)
        case redirect(finalURL: URL, finalBody: String, hops: [RedirectHop])
        case transportError(String)
    }

    /// One step of a time-varying timeline.
    struct TimelineEntry {
        let at: Duration
        let reply: Reply

        init(at: Duration, reply: Reply) {
            self.at = at
            self.reply = reply
        }
    }

    private struct State {
        var fixed: [URL: Reply] = [:]
        var timelines: [URL: [TimelineEntry]] = [:]
        var requestLog: [URL] = []
    }



    // MARK: - Lets & Vars

    private let clock: ManualClock?

    private let state = OSAllocatedUnfairLock(initialState: State())

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)



    // MARK: - Lifecycle

    init(clock: ManualClock? = nil) {
        self.clock = clock
    }



    // MARK: - Internal

    /// Stubs a fixed playlist-text reply for a URL.
    func stub(_ url: URL, body: String, status: Int = 200) {
        state.withLock { $0.fixed[url] = .body(body, status: status) }
    }

    /// Stubs a fixed reply for a URL.
    func stub(_ url: URL, reply: Reply) {
        state.withLock { $0.fixed[url] = reply }
    }

    /// Stubs a time-varying timeline for a URL, consulted against the injected ``ManualClock``.
    func timeline(_ url: URL, _ entries: [TimelineEntry]) {
        state.withLock { $0.timelines[url] = entries.sorted { $0.at < $1.at } }
    }

    /// Every URL fetched so far, in order.
    var requestedURLs: [URL] {
        state.withLock { $0.requestLog }
    }

    /// The number of times a specific URL was fetched.
    func fetchCount(for url: URL) -> Int {
        state.withLock { $0.requestLog.count { $0 == url } }
    }

    func fetch(_ url: URL) async -> FetchResult {
        let elapsed = clock.map { Self.seconds($0.now.offset) } ?? 0
        let reply: Reply = state.withLock { state in
            state.requestLog.append(url)
            if let timeline = state.timelines[url], !timeline.isEmpty {
                let current = timeline.last { Self.seconds($0.at) <= elapsed } ?? timeline[0]
                return current.reply
            }
            return state.fixed[url] ?? .body("", status: 404)
        }
        return makeResult(url: url, reply: reply, elapsed: elapsed)
    }



    // MARK: - Private

    private func makeResult(url: URL, reply: Reply, elapsed: Double) -> FetchResult {
        let started = epoch.addingTimeInterval(elapsed)
        let ended = started.addingTimeInterval(0.01)

        func metadata(status: Int?, headers: [String: String], redirects: [RedirectHop]) -> ResponseMetadata {
            ResponseMetadata(
                requestHeaders: ["User-Agent": "valistream-test"],
                requestStartedAt: started,
                responseEndedAt: ended,
                remoteAddress: "203.0.113.10",
                remotePort: 443,
                httpStatus: status,
                responseHeaders: headers,
                negotiatedProtocol: "h2",
                redirectChain: redirects
            )
        }

        switch reply {
        case .body(let text, let status):
            let data = Data(text.utf8)
            let outcome: FetchOutcome = (200..<400).contains(status) ? .success : .httpError(status: status)
            return FetchResult(
                url: url,
                body: data,
                metadata: metadata(status: status, headers: ["Content-Type": "application/vnd.apple.mpegurl"], redirects: []),
                outcome: outcome
            )
        case .data(let data, let status):
            let outcome: FetchOutcome = (200..<400).contains(status) ? .success : .httpError(status: status)
            return FetchResult(url: url, body: data, metadata: metadata(status: status, headers: [:], redirects: []), outcome: outcome)
        case .redirect(let finalURL, let finalBody, let hops):
            // Model the real fetcher: FetchResult.url is the redirected final URL, not the requested URL.
            return FetchResult(
                url: finalURL,
                body: Data(finalBody.utf8),
                metadata: metadata(status: 200, headers: ["Content-Type": "application/vnd.apple.mpegurl"], redirects: hops),
                outcome: .success
            )
        case .transportError(let description):
            return FetchResult(
                url: url,
                body: Data(),
                metadata: metadata(status: nil, headers: [:], redirects: []),
                outcome: .transportError(description: description)
            )
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

//
//  URLSessionStreamFetcher.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation
import os

/// Production ``StreamFetching`` backed by a single `URLSession`.
///
/// Captures per-request metadata required by FR-011 from `URLSessionTaskMetrics` (remote IP/port,
/// fetch timings, negotiated protocol) and records every redirect hop. HTTP caching is disabled so
/// the tool observes origin behavior, not cache behavior (research §3).
public final class URLSessionStreamFetcher: StreamFetching {
    // MARK: - Lets & Vars

    private let session: URLSession



    // MARK: - Lifecycle

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: configuration)
    }



    // MARK: - Public

    public func fetch(_ url: URL) async -> FetchResult {
        let delegate = MetricsCapturingDelegate()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let requestHeaders = request.allHTTPHeaderFields ?? [:]
        let startedAt = Date()

        do {
            let (data, response) = try await session.data(for: request, delegate: delegate)
            let captured = delegate.snapshot()
            let http = response as? HTTPURLResponse
            let status = http?.statusCode
            let metadata = ResponseMetadata(
                requestHeaders: requestHeaders,
                requestStartedAt: captured.fetchStart ?? startedAt,
                responseEndedAt: captured.responseEnd ?? Date(),
                remoteAddress: captured.remoteAddress,
                remotePort: captured.remotePort,
                httpStatus: status,
                responseHeaders: Self.headerDictionary(http?.allHeaderFields),
                negotiatedProtocol: captured.negotiatedProtocol,
                redirectChain: captured.redirects
            )
            let outcome: FetchOutcome = (status.map { (200..<400).contains($0) } ?? false)
                ? .success
                : .httpError(status: status ?? -1)
            return FetchResult(url: response.url ?? url, body: data, metadata: metadata, outcome: outcome)
        }
        catch {
            let captured = delegate.snapshot()
            let metadata = ResponseMetadata(
                requestHeaders: requestHeaders,
                requestStartedAt: startedAt,
                responseEndedAt: Date(),
                remoteAddress: captured.remoteAddress,
                remotePort: captured.remotePort,
                httpStatus: nil,
                responseHeaders: [:],
                negotiatedProtocol: captured.negotiatedProtocol,
                redirectChain: captured.redirects
            )
            return FetchResult(
                url: url,
                body: Data(),
                metadata: metadata,
                outcome: .transportError(description: error.localizedDescription)
            )
        }
    }



    // MARK: - Private

    static func headerDictionary(_ headers: [AnyHashable: Any]?) -> [String: String] {
        guard let headers else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in headers {
            if let key = key as? String, let value = value as? String {
                result[key] = value
            }
        }
        return result
    }
}

// MARK: - MetricsCapturingDelegate

/// Per-task delegate that accumulates redirect hops and transaction metrics.
///
/// All mutable state lives behind an `OSAllocatedUnfairLock`, so the type is genuinely thread-safe
/// despite the `@unchecked Sendable` (the only sanctioned use: a type with internal locking).
private final class MetricsCapturingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    struct Captured {
        var redirects: [RedirectHop] = []
        var remoteAddress: String?
        var remotePort: Int?
        var negotiatedProtocol: String?
        var fetchStart: Date?
        var responseEnd: Date?
    }

    private let state = OSAllocatedUnfairLock(initialState: Captured())

    func snapshot() -> Captured {
        state.withLock { $0 }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let hop = RedirectHop(
            url: response.url ?? request.url ?? task.originalRequest?.url ?? URL(string: "about:blank")!,
            statusCode: response.statusCode,
            headers: URLSessionStreamFetcher.headerDictionary(response.allHeaderFields)
        )
        state.withLock { $0.redirects.append(hop) }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last else { return }
        state.withLock { captured in
            captured.remoteAddress = transaction.remoteAddress
            captured.remotePort = transaction.remotePort
            captured.negotiatedProtocol = transaction.networkProtocolName
            captured.fetchStart = transaction.fetchStartDate
            captured.responseEnd = transaction.responseEndDate
        }
    }
}

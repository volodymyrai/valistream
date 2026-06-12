//
//  StreamFetching.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Foundation

/// The transport seam the session engine fetches through.
///
/// Production uses ``URLSessionStreamFetcher``; integration tests inject a scripted in-process stub
/// (research §8). A fetch never throws for network-level failures — every attempt yields a
/// ``FetchResult`` whose ``FetchResult/outcome`` records success, an HTTP error, or a transport
/// error, so the session can convert failures to `delivery` findings and archive every attempt
/// (FR-004, FR-010, FR-014).
public protocol StreamFetching: Sendable {
    /// Fetches a resource, capturing full request/response metadata.
    func fetch(_ url: URL) async -> FetchResult
}

/// The classification of a fetch attempt's result (FR-014).
public enum FetchOutcome: Sendable, Equatable {
    case success
    case httpError(status: Int)
    case transportError(description: String)
}

/// One redirect hop recorded during a fetch (FR-011, edge case "redirects").
public struct RedirectHop: Sendable, Equatable, Codable {
    public let url: URL
    public let statusCode: Int
    public let headers: [String: String]

    public init(url: URL, statusCode: Int, headers: [String: String]) {
        self.url = url
        self.statusCode = statusCode
        self.headers = headers
    }
}

/// Request and response metadata captured for one fetch, independent of where the body is stored.
public struct ResponseMetadata: Sendable, Equatable {
    public let requestHeaders: [String: String]
    public let requestStartedAt: Date
    public let responseEndedAt: Date
    public let remoteAddress: String?
    public let remotePort: Int?
    public let httpStatus: Int?
    public let responseHeaders: [String: String]
    public let negotiatedProtocol: String?
    public let redirectChain: [RedirectHop]

    public init(
        requestHeaders: [String: String],
        requestStartedAt: Date,
        responseEndedAt: Date,
        remoteAddress: String?,
        remotePort: Int?,
        httpStatus: Int?,
        responseHeaders: [String: String],
        negotiatedProtocol: String?,
        redirectChain: [RedirectHop]
    ) {
        self.requestHeaders = requestHeaders
        self.requestStartedAt = requestStartedAt
        self.responseEndedAt = responseEndedAt
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
        self.httpStatus = httpStatus
        self.responseHeaders = responseHeaders
        self.negotiatedProtocol = negotiatedProtocol
        self.redirectChain = redirectChain
    }
}

/// The result of a single fetch attempt: the body bytes plus full metadata and an outcome.
public struct FetchResult: Sendable, Equatable {
    /// The final URL after any redirects.
    public let url: URL
    public let method: String
    public let body: Data
    public let metadata: ResponseMetadata
    public let outcome: FetchOutcome

    public init(
        url: URL,
        method: String = "GET",
        body: Data,
        metadata: ResponseMetadata,
        outcome: FetchOutcome
    ) {
        self.url = url
        self.method = method
        self.body = body
        self.metadata = metadata
        self.outcome = outcome
    }

    /// The body decoded as UTF-8 text (playlists are text), or `nil` if not decodable.
    public var bodyText: String? {
        String(data: body, encoding: .utf8)
    }
}

/// A stored copy of one downloaded resource's metadata — the `.meta.json` sidecar (FR-011).
///
/// The archive builds this from a ``FetchResult`` once the body has been written, assigning the
/// `bodyPath` relative to the session folder.
public struct ArtifactRecord: Sendable, Equatable, Codable {
    public let requestId: String
    public let url: URL
    public let method: String
    public let requestHeaders: [String: String]
    public let requestStartedAt: Date
    public let responseEndedAt: Date
    public let remoteAddress: String?
    public let remotePort: Int?
    public let httpStatus: Int?
    public let responseHeaders: [String: String]
    public let negotiatedProtocol: String?
    public let redirectChain: [RedirectHop]
    public let bodyPath: String
    public let bodyBytes: Int
    public let outcome: String

    public init(requestId: String, bodyPath: String, result: FetchResult) {
        self.requestId = requestId
        self.url = result.url
        self.method = result.method
        self.requestHeaders = result.metadata.requestHeaders
        self.requestStartedAt = result.metadata.requestStartedAt
        self.responseEndedAt = result.metadata.responseEndedAt
        self.remoteAddress = result.metadata.remoteAddress
        self.remotePort = result.metadata.remotePort
        self.httpStatus = result.metadata.httpStatus
        self.responseHeaders = result.metadata.responseHeaders
        self.negotiatedProtocol = result.metadata.negotiatedProtocol
        self.redirectChain = result.metadata.redirectChain
        self.bodyPath = bodyPath
        self.bodyBytes = result.body.count
        self.outcome = Self.describe(result.outcome)
    }

    private static func describe(_ outcome: FetchOutcome) -> String {
        switch outcome {
        case .success: "success"
        case .httpError(let status): "httpError(\(status))"
        case .transportError(let description): "transportError(\(description))"
        }
    }
}

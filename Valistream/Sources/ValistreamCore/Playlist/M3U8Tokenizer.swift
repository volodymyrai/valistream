//
//  M3U8Tokenizer.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

/// A single classified line of an M3U8 playlist, retaining its source position and verbatim text.
///
/// The tokenizer is deliberately lossless: unknown, duplicate, and malformed tags survive as
/// ordinary `tag` events so the validation engine can report exactly what appeared and where
/// (FR-008). Interpretation is the playlist builder's and rules' job, never the tokenizer's.
public struct M3U8Token: Equatable, Sendable {
    // MARK: - Nested types

    /// The classification of a playlist line.
    public enum Kind: Equatable, Sendable {
        /// An `#EXT…` tag. `attributes` is the verbatim text following the first colon, or `nil`
        /// when the tag carries no value (e.g. `#EXTM3U`).
        case tag(name: String, attributes: String?)
        /// A resource URI line (any non-blank line that does not begin with `#`).
        case uri(String)
        /// A `#` comment that is not an `#EXT` tag. The associated value is the text after `#`.
        case comment(String)
        /// A blank or whitespace-only line.
        case blank
    }



    // MARK: - Lets & Vars

    /// 1-based line number within the source playlist.
    public let lineNumber: Int

    /// The source line verbatim, with any trailing carriage return removed.
    public let rawLine: String

    /// The classification of this line.
    public let kind: Kind



    // MARK: - Lifecycle

    public init(lineNumber: Int, rawLine: String, kind: Kind) {
        self.lineNumber = lineNumber
        self.rawLine = rawLine
        self.kind = kind
    }
}

/// Splits raw M3U8 text into an ordered, lossless stream of ``M3U8Token`` values.
public struct M3U8Tokenizer: Sendable {
    // MARK: - Lifecycle

    public init() {}



    // MARK: - Public

    /// Tokenizes playlist text, preserving line order, 1-based line numbers, and raw line content.
    ///
    /// - Parameter text: The full playlist body as received.
    /// - Returns: One token per line. A trailing newline does not yield a phantom blank token.
    public func tokenize(_ text: String) -> [M3U8Token] {
        // Normalize CRLF/CR to LF so line splitting and raw text are independent of line-ending style.
        let normalized = text.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
        var lines = normalized.split(separator: "\n" as Character, omittingEmptySubsequences: false)
            .map(String.init)
        // A trailing newline produces a final empty element that is not a real line.
        if lines.count > 1, lines.last == "" {
            lines.removeLast()
        }

        return lines.enumerated().map { offset, line in
            M3U8Token(lineNumber: offset + 1, rawLine: line, kind: Self.classify(line))
        }
    }



    // MARK: - Private

    private static func classify(_ line: String) -> M3U8Token.Kind {
        if line.allSatisfy(\.isWhitespace) {
            return .blank
        }
        guard line.hasPrefix("#") else {
            return .uri(line)
        }
        guard line.hasPrefix("#EXT") else {
            return .comment(String(line.dropFirst()))
        }
        if let colon = line.firstIndex(of: ":") {
            let name = String(line[line.startIndex..<colon])
            let attributes = String(line[line.index(after: colon)...])
            return .tag(name: name, attributes: attributes)
        }
        return .tag(name: line, attributes: nil)
    }
}

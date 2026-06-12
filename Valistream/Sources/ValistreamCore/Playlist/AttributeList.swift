//
//  AttributeList.swift
//  ValistreamCore
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

/// An ordered parse of an M3U8 attribute list (RFC 8216 §4.2), e.g. the body of an
/// `#EXT-X-STREAM-INF` tag.
///
/// Parsing is lossless and order-preserving: attributes keep their declared order, duplicate names
/// are retained and reported (`duplicateNames`), and quoting is recorded so rules can validate that
/// values which must be quoted strings actually were.
public struct AttributeList: Equatable, Sendable {
    // MARK: - Nested types

    /// A single `NAME=VALUE` attribute.
    public struct Attribute: Equatable, Sendable {
        /// The attribute name, exactly as written (uppercase by convention, not enforced here).
        public let name: String

        /// The attribute value with surrounding quotes removed for quoted strings.
        public let value: String

        /// Whether the source value was a quoted string (`"…"`).
        public let isQuoted: Bool

        public init(name: String, value: String, isQuoted: Bool) {
            self.name = name
            self.value = value
            self.isQuoted = isQuoted
        }
    }



    // MARK: - Lets & Vars

    /// All attributes in declared order, including duplicates.
    public let attributes: [Attribute]



    // MARK: - Lifecycle

    /// Parses an attribute-list string, honoring quoted values that may contain commas.
    ///
    /// - Parameter raw: The attribute-list portion of a tag (the text after the tag's colon).
    public init(parsing raw: String) {
        self.attributes = Self.parse(raw)
    }



    // MARK: - Public

    /// The value of the first attribute with the given name, or `nil` if absent.
    public subscript(_ name: String) -> String? {
        attributes.first { $0.name == name }?.value
    }

    /// Names that appear more than once, in first-seen order.
    public var duplicateNames: [String] {
        var seen: Set<String> = []
        var counts: [String: Int] = [:]
        var order: [String] = []
        for attribute in attributes {
            counts[attribute.name, default: 0] += 1
            if seen.insert(attribute.name).inserted {
                order.append(attribute.name)
            }
        }
        return order.filter { (counts[$0] ?? 0) > 1 }
    }



    // MARK: - Private

    private static func parse(_ raw: String) -> [Attribute] {
        let segments = splitTopLevel(raw)
        return segments.compactMap { segment in
            guard let equals = segment.firstIndex(of: "=") else { return nil }
            let name = String(segment[segment.startIndex..<equals])
            let rawValue = String(segment[segment.index(after: equals)...])
            let isQuoted = rawValue.count >= 2 && rawValue.hasPrefix("\"") && rawValue.hasSuffix("\"")
            let value = isQuoted ? String(rawValue.dropFirst().dropLast()) : rawValue
            return Attribute(name: name, value: value, isQuoted: isQuoted)
        }
    }

    /// Splits on commas that are not inside a quoted string.
    private static func splitTopLevel(_ raw: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var insideQuotes = false
        for character in raw {
            switch character {
            case "\"":
                insideQuotes.toggle()
                current.append(character)
            case "," where !insideQuotes:
                segments.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }
}

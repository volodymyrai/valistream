//
//  M3U8TokenizerTests.swift
//  ValistreamCoreTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

import Testing
@testable import ValistreamCore

@Suite("M3U8Tokenizer", .tags(.playlist))
struct M3U8TokenizerTests {
    private let tokenizer = M3U8Tokenizer()



    // MARK: - Line fidelity

    @Test("assigns 1-based line numbers and preserves raw lines")
    func preservesLineNumbersAndRawText() {
        let tokens = tokenizer.tokenize("#EXTM3U\n#EXT-X-VERSION:7\nhttp://e/x.ts\n")

        #expect(tokens.count == 3)
        #expect(tokens.map(\.lineNumber) == [1, 2, 3])
        #expect(tokens.map(\.rawLine) == ["#EXTM3U", "#EXT-X-VERSION:7", "http://e/x.ts"])
    }

    @Test("strips CR from CRLF line endings in raw text")
    func handlesCRLF() {
        let tokens = tokenizer.tokenize("#EXTM3U\r\nhttp://e/x.ts\r\n")

        #expect(tokens.map(\.rawLine) == ["#EXTM3U", "http://e/x.ts"])
    }

    @Test("does not emit a phantom blank token for a trailing newline")
    func noPhantomTrailingBlank() {
        let tokens = tokenizer.tokenize("#EXTM3U\n")

        #expect(tokens.count == 1)
        #expect(tokens[0].kind == .tag(name: "#EXTM3U", attributes: nil))
    }

    @Test("preserves interior blank lines as blank tokens")
    func preservesBlankLines() {
        let tokens = tokenizer.tokenize("#EXTM3U\n\nhttp://e/x.ts\n")

        #expect(tokens.count == 3)
        #expect(tokens[1].kind == .blank)
    }



    // MARK: - Classification

    @Test("classifies tag with no value as tag with nil attributes")
    func classifiesValuelessTag() {
        let tokens = tokenizer.tokenize("#EXTM3U")

        #expect(tokens[0].kind == .tag(name: "#EXTM3U", attributes: nil))
    }

    @Test("classifies tag value verbatim after the first colon")
    func classifiesTagWithValue() {
        let tokens = tokenizer.tokenize("#EXTINF:4.0,Title: with colon")

        #expect(tokens[0].kind == .tag(name: "#EXTINF", attributes: "4.0,Title: with colon"))
    }

    @Test("classifies URI lines")
    func classifiesURI() {
        let tokens = tokenizer.tokenize("segment_0001.ts")

        #expect(tokens[0].kind == .uri("segment_0001.ts"))
    }

    @Test("classifies non-EXT comments")
    func classifiesComment() {
        let tokens = tokenizer.tokenize("# a human comment")

        #expect(tokens[0].kind == .comment(" a human comment"))
    }

    @Test("preserves unknown and malformed tags as tag events")
    func preservesAnomalousTags() {
        let tokens = tokenizer.tokenize("#EXT-X-FUTURE-TAG:value\n#EXT-X-")

        #expect(tokens[0].kind == .tag(name: "#EXT-X-FUTURE-TAG", attributes: "value"))
        #expect(tokens[1].kind == .tag(name: "#EXT-X-", attributes: nil))
    }

    @Test("preserves duplicate tags as separate token events")
    func preservesDuplicateTags() {
        let tokens = tokenizer.tokenize("#EXT-X-VERSION:3\n#EXT-X-VERSION:7")

        #expect(tokens.count == 2)
        #expect(tokens.allSatisfy { token in
            if case .tag(let name, _) = token.kind { return name == "#EXT-X-VERSION" }
            return false
        })
    }



    // MARK: - Attribute-list grammar

    @Test("parses comma-separated attributes preserving order")
    func parsesAttributeOrder() {
        let list = AttributeList(parsing: "BANDWIDTH=1280000,CODECS=\"avc1.4d401f\"")

        #expect(list.attributes.map(\.name) == ["BANDWIDTH", "CODECS"])
        #expect(list["BANDWIDTH"] == "1280000")
        #expect(list["CODECS"] == "avc1.4d401f")
    }

    @Test("does not split on commas inside quoted values")
    func respectsQuotedCommas() {
        let list = AttributeList(parsing: "CODECS=\"avc1.4d401f,mp4a.40.2\",RESOLUTION=1280x720")

        #expect(list["CODECS"] == "avc1.4d401f,mp4a.40.2")
        #expect(list["RESOLUTION"] == "1280x720")
    }

    @Test("records whether each value was quoted")
    func tracksQuoting() {
        let list = AttributeList(parsing: "NAME=\"English\",DEFAULT=YES")

        let name = list.attributes.first { $0.name == "NAME" }
        let def = list.attributes.first { $0.name == "DEFAULT" }
        #expect(name?.isQuoted == true)
        #expect(def?.isQuoted == false)
    }

    @Test("flags duplicate attribute keys")
    func flagsDuplicateKeys() {
        let list = AttributeList(parsing: "TYPE=AUDIO,TYPE=VIDEO")

        #expect(list.duplicateNames == ["TYPE"])
        #expect(list["TYPE"] == "AUDIO")
    }
}

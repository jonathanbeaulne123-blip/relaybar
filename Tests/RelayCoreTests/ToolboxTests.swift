import XCTest
@testable import RelayCore

final class ToolboxTests: XCTestCase {

    private func run(_ tool: ToolboxTool, _ input: String) throws -> String {
        try ToolboxPolicy.apply(tool, to: input).text
    }

    // MARK: - SHA-256

    func testSHA256KnownVectors() {
        XCTAssertEqual(SHA256Digest.hexDigest(Array("".utf8)),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Digest.hexDigest(Array("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256Digest.hexDigest(Array("The quick brown fox jumps over the lazy dog".utf8)),
                       "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")
    }

    func testSHA256HandlesEveryPaddingBoundary() {
        // 55, 56 and 64 bytes exercise the two-block padding cases.
        let cases: [(Int, String)] = [
            (55, "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"),
            (56, "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"),
            (64, "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb")
        ]
        for (count, expected) in cases {
            XCTAssertEqual(SHA256Digest.hexDigest([UInt8](repeating: 0x61, count: count)), expected, "\(count) bytes")
        }
    }

    func testSHA256ToolWritesTheDigestOfTheClipboardText() throws {
        let out = try run(.sha256, "abc")
        XCTAssertEqual(out, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: - Line tools

    func testLineTools() throws {
        XCTAssertEqual(try run(.trimLines, "  a  \n\tb\t"), "a\nb")
        XCTAssertEqual(try run(.sortLines, "b\nA\nc"), "A\nb\nc")
        XCTAssertEqual(try run(.dedupeLines, "a\nb\na\nb"), "a\nb")
        XCTAssertEqual(try run(.dropBlankLines, "a\n\n   \nb"), "a\nb")
    }

    func testDedupeKeepsFirstOccurrenceAndIsCaseSensitive() throws {
        XCTAssertEqual(try run(.dedupeLines, "First\nfirst\nFirst"), "First\nfirst")
    }

    // MARK: - Case and style

    func testCaseTools() throws {
        XCTAssertEqual(try run(.uppercase, "aBc"), "ABC")
        XCTAssertEqual(try run(.lowercase, "aBc"), "abc")
        XCTAssertEqual(try run(.titleCase, "hello wide world"), "Hello Wide World")
        XCTAssertEqual(try run(.slugify, "  Hello, Wide  World!  "), "hello-wide-world")
        XCTAssertEqual(try run(.slugify, "Already-a-Slug"), "already-a-slug")
        XCTAssertEqual(try run(.slugify, "!!!"), "")
    }

    // MARK: - Encoding

    func testBase64RoundTrip() throws {
        let encoded = try run(.base64Encode, "hello world")
        XCTAssertEqual(encoded, "aGVsbG8gd29ybGQ=")
        XCTAssertEqual(try run(.base64Decode, encoded), "hello world")
    }

    func testBase64DecodeAcceptsMissingPaddingAndRefusesGarbage() throws {
        XCTAssertEqual(try run(.base64Decode, "aGVsbG8"), "hello")
        XCTAssertThrowsError(try run(.base64Decode, "not base64!!"))
    }

    func testURLEncodingRoundTripAndBrokenEscapeRefusal() throws {
        let encoded = try run(.urlEncode, "a b&c=d/e")
        XCTAssertEqual(encoded, "a%20b%26c%3Dd%2Fe")
        XCTAssertEqual(try run(.urlDecode, encoded), "a b&c=d/e")
        XCTAssertThrowsError(try run(.urlDecode, "bad%2"))
    }

    // MARK: - JSON

    func testJSONPrettyAndMinify() throws {
        let compact = #"{"b":1,"a":[1,2]}"#
        let pretty = try run(.jsonPretty, compact)
        XCTAssertTrue(pretty.contains("\n"))
        XCTAssertTrue(pretty.contains("\"a\""))
        let minified = try run(.jsonMinify, pretty)
        XCTAssertFalse(minified.contains("\n"))
        let roundTripped = try JSONSerialization.jsonObject(with: Data(minified.utf8))
        let expected = try JSONSerialization.jsonObject(with: Data(compact.utf8))
        XCTAssertEqual(roundTripped as? NSDictionary, expected as? NSDictionary)
    }

    func testInvalidJSONIsRefusedWithoutChangingAnything() {
        XCTAssertThrowsError(try run(.jsonPretty, "{not json")) { error in
            XCTAssertTrue(error.localizedDescription.contains("not valid JSON"))
        }
        XCTAssertThrowsError(try run(.jsonMinify, "plain text"))
    }

    // MARK: - Numbers and time

    func testSumAndAverage() throws {
        XCTAssertEqual(try run(.sumNumbers, "1\n2.5\n-3"), "0.5")
        XCTAssertEqual(try run(.sumNumbers, "10 20 30"), "60")
        XCTAssertEqual(try run(.averageNumbers, "1\n2\n3"), "2")
        XCTAssertEqual(try run(.averageNumbers, "1\n2"), "1.5")
    }

    func testNumbersWithNoDigitsAreRefused() {
        XCTAssertThrowsError(try run(.sumNumbers, "no numbers here"))
        XCTAssertThrowsError(try run(.averageNumbers, ""))
    }

    func testEpochToISOAcceptsSecondsAndMilliseconds() throws {
        XCTAssertEqual(try run(.epochToISO, "0"), "1970-01-01T00:00:00Z")
        XCTAssertEqual(try run(.epochToISO, "1700000000"), "2023-11-14T22:13:20Z")
        XCTAssertEqual(try run(.epochToISO, "1700000000000"), "2023-11-14T22:13:20Z")
        XCTAssertThrowsError(try run(.epochToISO, "not a timestamp"))
    }

    func testISOToEpochRoundTrips() throws {
        XCTAssertEqual(try run(.isoToEpoch, "1970-01-01T00:00:00Z"), "0")
        XCTAssertEqual(try run(.isoToEpoch, "2023-11-14T22:13:20Z"), "1700000000")
        XCTAssertEqual(try run(.isoToEpoch, "2023-11-14T22:13:20.000Z"), "1700000000")
        XCTAssertThrowsError(try run(.isoToEpoch, "yesterday"))
    }

    func testUUIDIsRandomV4() throws {
        let first = try run(.uuidV4, "")
        let second = try run(.uuidV4, "")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.count, 36)
        XCTAssertEqual(Array(first)[14], "4")
    }

    // MARK: - Policy

    func testGeneratorWorksWithAnEmptyClipboardButTransformsRefuse() throws {
        XCTAssertNoThrow(try ToolboxPolicy.apply(.uuidV4, to: ""))
        XCTAssertThrowsError(try ToolboxPolicy.apply(.uppercase, to: ""))
        XCTAssertThrowsError(try ToolboxPolicy.apply(.sortLines, to: ""))
    }

    func testOversizedInputIsRefusedRatherThanPartiallyTransformed() {
        let huge = String(repeating: "x", count: ToolboxPolicy.maximumInput + 1)
        XCTAssertThrowsError(try ToolboxPolicy.apply(.uppercase, to: huge)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Nothing was changed"))
        }
    }

    func testEveryToolIsReachableAndPagesCoverAllOfThemExactlyOnce() {
        let pages = ToolboxPolicy.pageCount
        XCTAssertEqual(pages, 5)
        let collected = (0..<pages).flatMap { ToolboxPolicy.tools(on: $0) }
        XCTAssertEqual(collected, ToolboxTool.allCases)
        XCTAssertTrue(ToolboxPolicy.tools(on: pages).isEmpty)
        XCTAssertTrue(ToolboxPolicy.tools(on: -1).isEmpty)
    }

    func testEachToolCarriesAUniqueIdTitleAndHelp() {
        XCTAssertEqual(Set(ToolboxTool.allCases.map(\.rawValue)).count, ToolboxTool.allCases.count)
        for tool in ToolboxTool.allCases {
            XCTAssertFalse(tool.title.isEmpty)
            XCTAssertFalse(tool.help.isEmpty)
            XCTAssertEqual(ToolboxPolicy.tool(withID: tool.rawValue), tool)
            XCTAssertTrue(tool.page >= 0 && tool.page < ToolboxPolicy.pageCount)
        }
    }

    func testSummariesDescribeWhatHappened() throws {
        let result = try ToolboxPolicy.apply(.uppercase, to: "abc")
        XCTAssertTrue(result.summary.contains("Upper-cased"))
        XCTAssertEqual(result.text, "ABC")
        let unchanged = try ToolboxPolicy.apply(.uppercase, to: "ABC")
        XCTAssertTrue(unchanged.summary.contains("no change needed"))
    }

    func testRoundedNumbersAreFormattedWithoutNoise() {
        XCTAssertEqual(ToolboxPolicy.formatted(3), "3")
        XCTAssertEqual(ToolboxPolicy.formatted(1.5), "1.5")
        XCTAssertEqual(ToolboxPolicy.formatted(-2.25), "-2.25")
    }
}

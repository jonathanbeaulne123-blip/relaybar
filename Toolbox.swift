import Foundation

// Toolbox: local, dependency-free text and data transforms.
//
// Every tool takes the clipboard text you copied and hands back transformed
// text. No shell, no network, no files, no browser involvement, no permissions.
// SHA-256 is implemented here so the engine stays portable and identical on
// every platform RelayBar's core is tested on.

public enum ToolboxTool: String, Codable, CaseIterable, Equatable {
    // Lines
    case trimLines, sortLines, dedupeLines, dropBlankLines
    // Case and style
    case uppercase, lowercase, titleCase, slugify
    // Encoding
    case base64Encode, base64Decode, urlEncode, urlDecode
    // Data
    case jsonPretty, jsonMinify, sha256, uuidV4
    // Numbers and time
    case sumNumbers, averageNumbers, epochToISO, isoToEpoch

    public var title: String {
        switch self {
        case .trimLines: return "Trim"
        case .sortLines: return "Sort A→Z"
        case .dedupeLines: return "Dedupe"
        case .dropBlankLines: return "Drop blanks"
        case .uppercase: return "UPPER"
        case .lowercase: return "lower"
        case .titleCase: return "Title Case"
        case .slugify: return "slug-case"
        case .base64Encode: return "Base64 →"
        case .base64Decode: return "→ Base64"
        case .urlEncode: return "URL encode"
        case .urlDecode: return "URL decode"
        case .jsonPretty: return "JSON pretty"
        case .jsonMinify: return "JSON min"
        case .sha256: return "SHA-256"
        case .uuidV4: return "UUID"
        case .sumNumbers: return "Sum"
        case .averageNumbers: return "Average"
        case .epochToISO: return "Epoch → ISO"
        case .isoToEpoch: return "ISO → Epoch"
        }
    }

    public var help: String {
        switch self {
        case .trimLines: return "Trim whitespace from the start and end of every clipboard line."
        case .sortLines: return "Sort clipboard lines A→Z, case-insensitively."
        case .dedupeLines: return "Remove repeated clipboard lines, keeping the first occurrence."
        case .dropBlankLines: return "Remove empty and whitespace-only lines."
        case .uppercase: return "Convert the clipboard text to upper case."
        case .lowercase: return "Convert the clipboard text to lower case."
        case .titleCase: return "Capitalize the first letter of each word."
        case .slugify: return "Turn the clipboard text into a lowercase hyphenated slug."
        case .base64Encode: return "Encode the clipboard text as Base64."
        case .base64Decode: return "Decode Base64 from the clipboard. Refuses invalid input."
        case .urlEncode: return "Percent-encode the clipboard text as a URL component."
        case .urlDecode: return "Decode percent escapes in the clipboard text."
        case .jsonPretty: return "Pretty-print JSON from the clipboard. Refuses invalid JSON."
        case .jsonMinify: return "Minify JSON from the clipboard. Refuses invalid JSON."
        case .sha256: return "Replace the clipboard with the SHA-256 hex digest of its text."
        case .uuidV4: return "Generate a new random UUID v4 onto the clipboard."
        case .sumNumbers: return "Add every number found in the clipboard text."
        case .averageNumbers: return "Average every number found in the clipboard text."
        case .epochToISO: return "Convert a Unix timestamp from the clipboard to an ISO-8601 UTC date."
        case .isoToEpoch: return "Convert an ISO-8601 date from the clipboard to a Unix timestamp."
        }
    }

    /// A generator needs nothing from the clipboard. The others refuse to run
    /// on empty input rather than writing a meaningless result.
    public var usesClipboardInput: Bool { self != .uuidV4 }

    public var page: Int {
        let order = ToolboxTool.allCases
        guard let index = order.firstIndex(of: self) else { return 0 }
        return index / ToolboxPolicy.pageSize
    }
}

public struct ToolboxResult: Equatable {
    public var text: String
    /// A short factual line for the status area. Never claims more than the
    /// transform actually did.
    public var summary: String
    public init(text: String, summary: String) {
        self.text = text; self.summary = summary
    }
}

public enum ToolboxPolicy {
    public static let pageSize = 4
    public static let maximumInput = 200_000
    public static let maximumOutput = 200_000
    /// How many clipboard values can be restored with Undo.
    public static let undoDepth = 12

    public static var pageCount: Int {
        max(1, (ToolboxTool.allCases.count + pageSize - 1) / pageSize)
    }

    public static func tools(on page: Int) -> [ToolboxTool] {
        guard page >= 0, page < pageCount else { return [] }
        return Array(ToolboxTool.allCases.dropFirst(page * pageSize).prefix(pageSize))
    }

    public static func tool(withID id: String) -> ToolboxTool? { ToolboxTool(rawValue: id) }

    /// Applies one tool. Deterministic, offline and total: any refusal is an
    /// explicit error the UI can show, never a partial write.
    public static func apply(_ tool: ToolboxTool, to input: String) throws -> ToolboxResult {
        guard input.count <= maximumInput else {
            throw RelayError.invalid("The clipboard text exceeds \(maximumInput) characters. Nothing was changed.")
        }
        if tool.usesClipboardInput, input.isEmpty {
            throw RelayError.invalid("Copy the text you want to transform first; the clipboard is empty.")
        }
        let result: ToolboxResult
        switch tool {
        case .trimLines:
            result = transform(input, verb: "Trimmed") { $0.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n") }
        case .sortLines:
            result = transform(input, verb: "Sorted") { $0.components(separatedBy: "\n").sorted { $0.lowercased() < $1.lowercased() }.joined(separator: "\n") }
        case .dedupeLines:
            result = transform(input, verb: "Removed repeats") { text in
                var seen = Set<String>()
                return text.components(separatedBy: "\n").filter { seen.insert($0).inserted }.joined(separator: "\n")
            }
        case .dropBlankLines:
            result = transform(input, verb: "Removed blank lines") { $0.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n") }
        case .uppercase:
            result = transform(input, verb: "Upper-cased") { $0.uppercased() }
        case .lowercase:
            result = transform(input, verb: "Lower-cased") { $0.lowercased() }
        case .titleCase:
            result = transform(input, verb: "Title-cased") { Self.titleCased($0) }
        case .slugify:
            result = transform(input, verb: "Slugified") { Self.slug($0) }
        case .base64Encode:
            result = transform(input, verb: "Base64 encoded") { Data($0.utf8).base64EncodedString() }
        case .base64Decode:
            let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let padded = text.count % 4 == 0 ? text : text + String(repeating: "=", count: 4 - text.count % 4)
            guard let data = Data(base64Encoded: padded), let decoded = String(data: data, encoding: .utf8) else {
                throw RelayError.invalid("The clipboard is not valid UTF-8 Base64. Nothing was changed.")
            }
            result = ToolboxResult(text: decoded, summary: "Base64 decoded")
        case .urlEncode:
            result = transform(input, verb: "URL encoded") { text in
                var allowed = CharacterSet.alphanumerics
                allowed.insert(charactersIn: "-._~")
                return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
            }
        case .urlDecode:
            guard let decoded = input.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
                throw RelayError.invalid("The clipboard contains a broken percent escape. Nothing was changed.")
            }
            result = ToolboxResult(text: decoded, summary: "URL decoded")
        case .jsonPretty:
            result = try Self.reformatJSON(input, pretty: true)
        case .jsonMinify:
            result = try Self.reformatJSON(input, pretty: false)
        case .sha256:
            let digest = SHA256Digest.hexDigest(Array(input.utf8))
            result = ToolboxResult(text: digest, summary: "SHA-256 of \(input.utf8.count) bytes")
        case .uuidV4:
            result = ToolboxResult(text: UUID().uuidString.lowercased(), summary: "Generated a random UUID v4")
        case .sumNumbers:
            let numbers = Self.numbers(in: input)
            guard !numbers.isEmpty else { throw RelayError.invalid("No numbers were found in the clipboard text. Nothing was changed.") }
            let total = numbers.reduce(0, +)
            result = ToolboxResult(text: Self.formatted(total), summary: "Added \(numbers.count) number\(numbers.count == 1 ? "" : "s")")
        case .averageNumbers:
            let numbers = Self.numbers(in: input)
            guard !numbers.isEmpty else { throw RelayError.invalid("No numbers were found in the clipboard text. Nothing was changed.") }
            let average = numbers.reduce(0, +) / Double(numbers.count)
            result = ToolboxResult(text: Self.formatted(average), summary: "Averaged \(numbers.count) number\(numbers.count == 1 ? "" : "s")")
        case .epochToISO:
            let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let raw = Double(text), raw.isFinite else {
                throw RelayError.invalid("The clipboard does not contain a Unix timestamp. Nothing was changed.")
            }
            // Milliseconds are accepted only when the value cannot be seconds.
            let seconds = raw >= 100_000_000_000 ? raw / 1000 : raw
            let date = Date(timeIntervalSince1970: seconds)
            guard abs(seconds) < 300_000_000_000 else {
                throw RelayError.invalid("That timestamp is outside the range RelayBar will convert. Nothing was changed.")
            }
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.formatOptions = [.withInternetDateTime]
            result = ToolboxResult(text: formatter.string(from: date), summary: "Converted \(raw >= 100_000_000_000 ? "milliseconds" : "seconds") to UTC")
        case .isoToEpoch:
            let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let date = Self.parseISODate(text) else {
                throw RelayError.invalid("The clipboard does not contain an ISO-8601 date. Nothing was changed.")
            }
            result = ToolboxResult(text: String(Int(date.timeIntervalSince1970.rounded())), summary: "Converted UTC date to Unix seconds")
        }
        guard result.text.count <= maximumOutput else {
            throw RelayError.invalid("The result exceeds \(maximumOutput) characters. Nothing was changed.")
        }
        return result
    }

    // MARK: - Helpers

    private static func transform(_ input: String, verb: String, _ body: (String) -> String) -> ToolboxResult {
        let output = body(input)
        let changed = output == input
        return ToolboxResult(text: output, summary: changed ? "\(verb) · no change needed" : "\(verb) · \(input.count) → \(output.count) characters")
    }

    private static func titleCased(_ text: String) -> String {
        text.components(separatedBy: " ").map { word -> String in
            guard let first = word.first else { return word }
            return String(first).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    private static func slug(_ text: String) -> String {
        var result = ""
        var pendingDash = false
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingDash, !result.isEmpty { result.append("-") }
                pendingDash = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        return result
    }

    private static func reformatJSON(_ input: String, pretty: Bool) throws -> ToolboxResult {
        guard let data = input.data(using: .utf8) else {
            throw RelayError.invalid("The clipboard is not UTF-8 JSON. Nothing was changed.")
        }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw RelayError.invalid("The clipboard is not valid JSON. Nothing was changed.") }
        let options: JSONSerialization.WritingOptions = pretty
            ? [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
            : [.withoutEscapingSlashes]
        guard let encoded = try? JSONSerialization.data(withJSONObject: object, options: options),
              let text = String(data: encoded, encoding: .utf8) else {
            throw RelayError.invalid("This JSON could not be rewritten. Nothing was changed.")
        }
        return ToolboxResult(text: text, summary: pretty ? "Pretty-printed JSON" : "Minified JSON")
    }

    static func numbers(in text: String) -> [Double] {
        var numbers: [Double] = []
        var current = ""
        for character in text {
            if character.isNumber || character == "." || character == "-" || character == "+" {
                current.append(character)
            } else {
                if let value = Double(current), value.isFinite { numbers.append(value) }
                current = ""
            }
        }
        if let value = Double(current), value.isFinite { numbers.append(value) }
        return numbers
    }

    static func formatted(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int(value)) }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func parseISODate(_ text: String) -> Date? {
        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = internet.date(from: text) { return date }
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

/// Dependency-free SHA-256 (FIPS 180-4). Kept in the portable core so the
/// digest is identical everywhere the engine is tested. Named distinctly from
/// CryptoKit's SHA256, which the screenshot shelf uses.
enum SHA256Digest {
    private static let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func hexDigest(_ bytes: [UInt8]) -> String {
        digest(bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func digest(_ bytes: [UInt8]) -> [UInt8] {
        var hash: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                              0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var message = bytes
        let bitLength = UInt64(bytes.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }
        var schedule = [UInt32](repeating: 0, count: 64)
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            for index in 0..<16 {
                let base = chunkStart + index * 4
                schedule[index] = (UInt32(message[base]) << 24) | (UInt32(message[base + 1]) << 16)
                    | (UInt32(message[base + 2]) << 8) | UInt32(message[base + 3])
            }
            for index in 16..<64 {
                let s0 = rotateRight(schedule[index - 15], 7) ^ rotateRight(schedule[index - 15], 18) ^ (schedule[index - 15] >> 3)
                let s1 = rotateRight(schedule[index - 2], 17) ^ rotateRight(schedule[index - 2], 19) ^ (schedule[index - 2] >> 10)
                schedule[index] = schedule[index - 16] &+ s0 &+ schedule[index - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, h) = (hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7])
            for index in 0..<64 {
                let s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
                let choice = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ choice &+ constants[index] &+ schedule[index]
                let s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ majority
                h = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            hash[0] = hash[0] &+ a; hash[1] = hash[1] &+ b; hash[2] = hash[2] &+ c; hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e; hash[5] = hash[5] &+ f; hash[6] = hash[6] &+ g; hash[7] = hash[7] &+ h
        }
        return hash.flatMap { word in
            [UInt8((word >> 24) & 0xff), UInt8((word >> 16) & 0xff), UInt8((word >> 8) & 0xff), UInt8(word & 0xff)]
        }
    }

    private static func rotateRight(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}

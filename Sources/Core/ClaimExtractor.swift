import Foundation

/// The outcome of reviewing text. `claims` never includes a statement RelayBar
/// could not see; the counts below are what make the receipt honest about its
/// own blind spots.
public struct ClaimExtraction: Equatable {
    public let claims: [Claim]
    /// Non-code statements examined that produced no claim. These are NOT
    /// covered by the receipt and are reported to the user verbatim.
    public let unmatchedSentenceCount: Int
    /// Lines inside fenced code blocks. Excluded on purpose: they are usually
    /// commands or source, not assertions about the project.
    public let excludedCodeFenceLines: Int
    /// True when the source was too large, or the claim cap was reached. The
    /// remaining statements are counted as unmatched rather than dropped.
    public let truncated: Bool
    public let oversized: Bool

    public var isEmpty: Bool { claims.isEmpty }
}

/// Deterministic, local claim extraction.
///
/// There is no model here and no network: a fixed pattern bank decides what is
/// a claim. Everything the bank does not recognize is *counted and reported*,
/// never silently asserted. The extractor is deliberately conservative — a
/// false "not checkable" costs a footnote, while a false "verified" would
/// corrupt the one thing this feature exists to protect. Where a sentence is
/// genuinely ambiguous (for example it asserts both presence and absence), the
/// extractor emits no claim rather than guessing.
public enum ClaimExtractor {
    // MARK: Entry point

    public static func extract(from text: String, source: ClaimSource) -> ClaimExtraction {
        guard text.utf8.count <= LedgerPolicy.maxSourceBytes else {
            return ClaimExtraction(claims: [], unmatchedSentenceCount: 0, excludedCodeFenceLines: 0, truncated: true, oversized: true)
        }
        var claims: [Claim] = []
        var seen = Set<String>()
        var unmatched = 0
        var fencedLines = 0
        var truncated = false

        for statement in statements(in: text, fencedLineCount: &fencedLines) {
            let matches = match(statement, source: source)
            guard !matches.isEmpty else { unmatched += 1; continue }
            for candidate in matches {
                let key = LedgerPolicy.comparisonKey(candidate.text) + "#" + candidate.kind.rawValue
                guard seen.insert(key).inserted else { continue }
                guard claims.count < LedgerPolicy.maxClaims else {
                    // Remaining statements are not covered by the receipt. Say so.
                    truncated = true; unmatched += 1; continue
                }
                claims.append(candidate)
            }
            if claims.count >= LedgerPolicy.maxClaims { truncated = true }
        }

        return ClaimExtraction(claims: claims, unmatchedSentenceCount: unmatched,
                              excludedCodeFenceLines: fencedLines, truncated: truncated, oversized: false)
    }

    // MARK: Statement segmentation

    /// Fenced code blocks are excluded; each remaining line is split into
    /// sentences on terminal punctuation *followed by whitespace or end of
    /// line*, so `Reality.swift` and `v1.0.1` are never split mid-token.
    static func statements(in text: String, fencedLineCount: inout Int) -> [String] {
        var result: [String] = []
        var inFence = false
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle(); fencedLineCount += 1; continue
            }
            if inFence { fencedLineCount += 1; continue }
            let cleaned = stripMarkdownPrefix(trimmed)
            guard !cleaned.isEmpty else { continue }
            for sentence in splitSentences(cleaned) {
                let candidate = sentence.trimmingCharacters(in: .whitespaces)
                guard !candidate.isEmpty, candidate.contains(where: { $0.isLetter }) else { continue }
                result.append(candidate)
            }
        }
        return result
    }

    private static func stripMarkdownPrefix(_ line: String) -> String {
        var working = Substring(line)
        // Markers and their following spaces are stripped together, so
        // "- [x] …" and "> 1. …" reach the matcher as plain statements.
        while let first = working.first, "#>*-+• ".contains(first) { working = working.dropFirst() }
        if working.hasPrefix("[ ]") { working = working.dropFirst(3) }
        else if working.hasPrefix("[x]") || working.hasPrefix("[X]") { working = working.dropFirst(3) }
        // Ordered list markers: "1. " / "2) "
        let digits = working.prefix(while: { $0.isNumber })
        if !digits.isEmpty, digits.count <= 3, let next = working.dropFirst(digits.count).first, next == "." || next == ")" {
            working = working.dropFirst(digits.count + 1)
        }
        return working.trimmingCharacters(in: .whitespaces)
    }

    private static func splitSentences(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(line)
        for (index, character) in characters.enumerated() {
            current.append(character)
            guard character == "." || character == "!" || character == "?" else { continue }
            let nextIsBoundary = index + 1 >= characters.count || characters[index + 1] == " " || characters[index + 1] == "\t"
            guard nextIsBoundary else { continue }
            result.append(current); current = ""
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { result.append(current) }
        return result
    }

    // MARK: Classification

    /// All claims a statement supports. A mixed sentence ("the tests pass but
    /// the build fails") yields two claims — each answering for its own clause —
    /// rather than one silent omission, and "the tests pass but the build
    /// fails" is never read as a failing test run.
    ///
    /// Classification reads a display-safe projection of the statement: control
    /// and bidirectional-override characters are removed first, so a trailing
    /// U+202E cannot hide a claim from the pattern bank. The text stored on
    /// every claim is the sentence as written, verbatim.
    public static func match(_ sentence: String, source: ClaimSource = .draft) -> [Claim] {
        guard sentence.count <= LedgerPolicy.maxClaimCharacters else { return [] }
        let statement = LedgerPolicy.displayText(sentence, limit: LedgerPolicy.maxClaimCharacters)
        let wordCount = statement.split(whereSeparator: { $0.isWhitespace }).count
        guard wordCount >= 3, statement.count >= LedgerPolicy.minSentenceCharacters else { return [] }

        var results: [Claim] = []
        var seen = Set<String>()
        func add(_ claim: Claim) {
            guard seen.insert(claim.kind.rawValue + "#" + claim.polarity.rawValue).inserted else { return }
            results.append(claim)
        }

        // A question asserts nothing that can be settled.
        if statement.contains("?") {
            add(Claim(text: sentence, kind: .notFalsifiable, source: source,
                      strategy: .impossible("This is a question, not a claim about the project.")))
            return results
        }
        // Hedged, proposed, or opinionated text is recorded but never "settled".
        if contains(Pattern.hedging, statement) {
            add(Claim(text: sentence, kind: .notFalsifiable, source: source,
                      strategy: .impossible("This is a proposal, hedge, or opinion. Nothing local can confirm or refute it.")))
            return results
        }

        // Command rules are collected rather than short-circuited: one sentence
        // can assert that the tests pass *and* that the build fails.
        commandClaims(statement, verbatim: sentence, source: source).forEach(add)
        if results.isEmpty, let claim = gitClaim(statement, verbatim: sentence, source: source) { add(claim) }
        if results.isEmpty, let claim = referenceClaim(statement, verbatim: sentence, source: source) { add(claim) }
        if results.isEmpty, let claim = locationClaim(statement, verbatim: sentence, source: source) { add(claim) }
        if results.isEmpty, let claim = fileClaim(statement, verbatim: sentence, source: source) { add(claim) }
        if results.isEmpty, let claim = definitionClaim(statement, verbatim: sentence, source: source) { add(claim) }
        if results.isEmpty, contains(Pattern.assertionVerb, statement), contains(Pattern.concrete, statement) {
            add(Claim(text: sentence, kind: .assertion, source: source,
                      strategy: .impossible("RelayBar has no local probe for this statement. It is reported as uncheckable, not as true.")))
        }
        // Otherwise the statement is unrecognized and counted as unmatched upstream.
        return results
    }

    /// Tests, build, and lint claims map onto a declared command. Polarity is
    /// preserved so "the tests do not pass" is never silently inverted.
    private static func commandClaims(_ statement: String, verbatim: String, source: ClaimSource) -> [Claim] {
        Rules.commands.compactMap { rule in
            guard contains(rule.subject, statement) else { return nil }
            guard let polarity = outcomePolarity(rule, in: statement) else { return nil }
            return Claim(text: verbatim, kind: rule.kind, polarity: polarity, source: source,
                         strategy: .execute(rule.kind.verifyCommandKind!))
        }
    }

    /// The outcome phrase that decides polarity is the one nearest the subject.
    /// A whole-sentence search would let "fails" in the second half of "the
    /// tests pass but the build fails" refute the first half.
    private static func outcomePolarity(_ rule: CommandRule, in statement: String) -> ClaimPolarity? {
        let subjects = ranges(rule.subject, in: statement)
        guard !subjects.isEmpty else { return nil }
        var best: (range: NSRange, polarity: ClaimPolarity, distance: Int)?
        for (pattern, polarity) in [(rule.positive, ClaimPolarity.affirmative), (rule.negativeOutcome, ClaimPolarity.negative)] {
            for range in ranges(pattern, in: statement) {
                let distance = subjects.map { gap($0, range) }.min() ?? Int.max
                let isCloser = best == nil || distance < best!.distance
                    || (distance == best!.distance && range.location < best!.range.location)
                if isCloser { best = (range, polarity, distance) }
            }
        }
        guard let chosen = best else { return nil }
        // "no lint warnings" and "not broken" assert health, while "the tests do
        // not pass" asserts its absence. Only a negation wrapping the phrase that
        // decided the polarity can flip it.
        if chosen.polarity == .negative, isBenignlyNegated(chosen.range, in: statement) { return .affirmative }
        return chosen.polarity
    }

    /// True when a "no warnings" / "not broken" phrase contains the outcome
    /// phrase that would otherwise be read as a failure.
    private static func isBenignlyNegated(_ range: NSRange, in statement: String) -> Bool {
        ranges(Pattern.benignNegation, in: statement).contains { $0.intersection(range) != nil }
    }

    private static func gitClaim(_ statement: String, verbatim: String, source: ClaimSource) -> Claim? {
        guard contains(Pattern.gitSubject, statement) else { return nil }
        let clean = contains(Pattern.gitClean, statement)
        let dirty = contains(Pattern.gitDirty, statement)
        // Ambiguous statements produce no claim rather than a coin flip.
        guard clean != dirty else { return nil }
        let expectation: GitFactExpectation = clean ? .clean : .dirty
        return Claim(text: verbatim, kind: .gitFact, source: source, strategy: .observe(.gitFact(expectation)))
    }

    private static func referenceClaim(_ statement: String, verbatim: String, source: ClaimSource) -> Claim? {
        guard let expectation = referenceExpectation(statement) else { return nil }
        guard let name = symbolName(in: statement) else {
            return Claim(text: verbatim, kind: .referenceCount, source: source,
                         strategy: .impossible("The statement is about references but names no symbol RelayBar can scan for."))
        }
        return Claim(text: verbatim, kind: .referenceCount, source: source,
                     strategy: .observe(.referenceCount(name: name, expected: expectation)))
    }

    private static func referenceExpectation(_ sentence: String) -> ReferenceExpectation? {
        if let count = capturedCount(Pattern.countExact, sentence) { return .exactly(min(count, 500)) }
        if contains(Pattern.countZero, sentence) { return .zero }
        if contains(Pattern.countNonZero, sentence) { return .atLeastOne }
        return nil
    }

    private static func locationClaim(_ statement: String, verbatim: String, source: ClaimSource) -> Claim? {
        guard let line = capturedInt(Pattern.lineNumber, statement) else { return nil }
        guard let path = fileToken(in: statement) else { return nil }
        let needle = quotedNeedle(in: statement) ?? capturedIdentifier(Pattern.definesNeedle, statement) ?? ""
        return Claim(text: verbatim, kind: .lineContains, source: source,
                     strategy: .observe(.lineContains(path: path, line: max(1, line), needle: needle)))
    }

    private static func fileClaim(_ statement: String, verbatim: String, source: ClaimSource) -> Claim? {
        let positive = contains(Pattern.existencePositive, statement)
        let negative = contains(Pattern.existenceNegative, statement)
        // Neither phrase, or both: no claim. "there is no doubt the file exists"
        // must not become a checkable assertion of absence, and "does not exist"
        // must not read as presence.
        guard positive != negative else { return nil }
        guard let path = fileToken(in: statement) else { return nil }
        return Claim(text: verbatim, kind: .fileExists, polarity: positive ? .affirmative : .negative,
                     source: source, strategy: .observe(.fileExists(path: path)))
    }

    private static func definitionClaim(_ statement: String, verbatim: String, source: ClaimSource) -> Claim? {
        let negativeName = capturedIdentifier(Pattern.definedNegative, statement)
        let name = negativeName ?? capturedIdentifier(Pattern.declarationKeyword, statement) ?? capturedIdentifier(Pattern.definedPositive, statement)
        guard let symbol = name else { return nil }
        return Claim(text: verbatim, kind: .symbolDefined, polarity: negativeName == nil ? .affirmative : .negative,
                     source: source, strategy: .observe(.symbolDefined(name: symbol)))
    }

    // MARK: Token helpers

    /// A path-looking token with an allowlisted source extension. Version
    /// numbers and ordinary words with periods are rejected by the allowlist.
    public static func fileToken(in sentence: String) -> String? {
        guard let match = firstMatch(Pattern.fileToken, sentence) else { return nil }
        guard let raw = group(0, in: match, of: sentence) else { return nil }
        let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: "`\"'()[],;:"))
        guard !token.isEmpty, token.count <= LedgerPolicy.maxPathCharacters else { return nil }
        return token
    }

    private static func quotedNeedle(in sentence: String) -> String? {
        guard let match = firstMatch(Pattern.quoted, sentence) else { return nil }
        guard let value = group(1, in: match, of: sentence) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return nil }
        if firstMatch(Pattern.fileToken, trimmed) != nil { return nil }
        return trimmed
    }

    private static func symbolName(in sentence: String) -> String? {
        // A backticked name is an explicit reference to code: always trusted.
        if let match = firstMatch(Pattern.backticked, sentence), let name = sanitizedSymbol(group(1, in: match, of: sentence)) {
            return name
        }
        // An unmarked capture is only trusted when it reads like code. Otherwise
        // "no other callers of the helper" would scan for a symbol named
        // "helper" and report a confident, meaningless verdict.
        for pattern in Pattern.namedSymbols {
            if let match = firstMatch(pattern, sentence),
               let name = sanitizedSymbol(group(1, in: match, of: sentence)),
               isCodeLike(name, in: sentence) {
                return name
            }
        }
        return nil
    }

    static func isCodeLike(_ name: String, in sentence: String) -> Bool {
        if name.contains("_") { return true }
        if name.contains(where: { $0.isNumber }) { return true }
        if name.dropFirst().contains(where: { $0.isUppercase }) { return true }
        return appearsCallable(name, in: sentence)
    }

    /// True when the name is followed by an opening parenthesis somewhere in the
    /// statement, without building a pattern from the name.
    private static func appearsCallable(_ name: String, in sentence: String) -> Bool {
        var searchStart = sentence.startIndex
        while let found = sentence.range(of: name, range: searchStart..<sentence.endIndex) {
            var index = found.upperBound
            while index < sentence.endIndex, sentence[index] == " " { index = sentence.index(after: index) }
            if index < sentence.endIndex, sentence[index] == "(" { return true }
            searchStart = found.upperBound
        }
        return false
    }

    /// Symbol names are compared literally, never used as a pattern. The
    /// sanitizer also drops ordinary English words the patterns can capture.
    public static func sanitizedSymbol(_ candidate: String?) -> String? {
        guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        guard !candidate.isEmpty, candidate.count <= LedgerPolicy.maxSymbolCharacters else { return nil }
        guard candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }), candidate.contains(where: { $0.isLetter }) else { return nil }
        guard !Pattern.symbolStopwords.contains(candidate.lowercased()) else { return nil }
        return candidate
    }

    private static func capturedIdentifier(_ pattern: NSRegularExpression, _ sentence: String) -> String? {
        guard let match = firstMatch(pattern, sentence) else { return nil }
        return sanitizedSymbol(group(1, in: match, of: sentence))
    }

    private static func capturedInt(_ pattern: NSRegularExpression, _ sentence: String) -> Int? {
        capturedCount(pattern, sentence)
    }

    private static func capturedCount(_ pattern: NSRegularExpression, _ sentence: String) -> Int? {
        guard let match = firstMatch(pattern, sentence), let raw = group(1, in: match, of: sentence) else { return nil }
        if let value = Int(raw) { return value }
        switch raw.lowercased() {
        case "one": return 1
        case "two": return 2
        case "three": return 3
        case "four": return 4
        case "five": return 5
        default: return nil
        }
    }

    static func contains(_ pattern: NSRegularExpression, _ sentence: String) -> Bool {
        firstMatch(pattern, sentence) != nil
    }

    /// NSRegularExpression requires an explicit search range; the whole string
    /// is the only range this feature ever needs.
    static func firstMatch(_ pattern: NSRegularExpression, _ text: String) -> NSTextCheckingResult? {
        pattern.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text))
    }

    /// Every match range, for the cases where position matters rather than
    /// presence (deciding which outcome phrase belongs to which subject).
    static func ranges(_ pattern: NSRegularExpression, in text: String) -> [NSRange] {
        pattern.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)).map(\.range)
    }

    /// Distance between two matches in characters; 0 when they touch.
    private static func gap(_ first: NSRange, _ second: NSRange) -> Int {
        if first.upperBound <= second.location { return second.location - first.upperBound }
        if second.upperBound <= first.location { return first.location - second.upperBound }
        return 0
    }

    private static func group(_ index: Int, in match: NSTextCheckingResult, of text: String) -> String? {
        guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    static func compiled(_ expression: String) -> NSRegularExpression {
        // Every pattern is a constant in this file, so a failure is a
        // programming error and must be loud rather than silently skipped.
        do { return try NSRegularExpression(pattern: expression, options: [.caseInsensitive]) }
        catch { preconditionFailure("Invalid claim pattern \(expression): \(error)") }
    }

    // MARK: Pattern bank

    enum Pattern {
        /// Hedging is checked first so "we should add a passing test" is not a
        /// test claim.
        static let hedging = compiled(#"\b(?:should|shouldn['’]t|would|could|might|may|maybe|perhaps|probably|likely|possibly|presumably|let['’]s|we['’]?ll|i['’]?ll|we\s+plan|plan(?:ning)?\s+to|intends?\s+to|aims?\s+to|recommend|suggest|consider|seems?|appears?|tends?\s+to|i\s+think|i\s+believe|in\s+my\s+opinion|hopefully|next\s+step|propos(?:e|ed|al)|an?\s+idea|worth\s+considering|feel\s+free|you\s+may\s+want)\b"#)
        static let assertionVerb = compiled(#"\b(?:is|are|was|were|has|have|had|contains?|includes?|handles?|returns?|uses?|supports?|provides?|requires?|writes?|reads?|stores?|computes?|checks?|calls?|depends?|maps?|renders?|emits?)\b"#)
        /// A generic sentence becomes a claim only when it points at something
        /// concrete. This keeps a long reply from filling the ledger with noise.
        static let concrete = compiled(#"[`"']|\b\d+\b|[\w.@+-]+/[\w.@+-]+|\.[A-Za-z]{2,6}\b"#)

        /// Health expressed as a negation. Without this, "the build is not
        /// broken" would be recorded as a claim that the build fails.
        static let benignNegation = compiled(#"(?:\b(?:no|zero|without|free\s+of)\s+(?:\w+\s+){0,2}?(?:warnings?|errors?|violations?|failures?|issues?|problems?)\b)|(?:\b(?:not|isn['’]t|aren['’]t|never|no\s+longer)\s+(?:broken|failing|failed|red|erroring|a\s+failure)\b)"#)

        static let gitSubject = compiled(#"\b(?:working\s+tree|git\s+tree|the\s+tree|branch|repository|repo|working\s+directory)\b"#)
        static let gitClean = compiled(#"\b(?:clean|no\s+uncommitted|nothing\s+to\s+commit|no\s+changes|fully\s+committed|up\s+to\s+date)\b"#)
        static let gitDirty = compiled(#"\b(?:dirty|uncommitted\s+changes|has\s+uncommitted|uncommitted\s+files|modified\s+files|not\s+committed|pending\s+changes)\b"#)

        static let countExact = compiled(#"\b(?:only|exactly)\s+(one|two|three|four|five|\d{1,3})\s+(?:callers?|references?|usages?|calls?|uses?)\b"#)
        static let countZero = compiled(#"\b(?:no\s+(?:other\s+)?(?:callers?|references?|usages?|uses?)|nothing\s+else\s+(?:calls?|uses?|references?)|(?:is|are|was|were)\s+(?:now\s+)?unused|(?:is|are|was|were)\s+never\s+(?:called|used|referenced)|dead\s+code|not\s+used\s+anywhere)\b"#)
        static let countNonZero = compiled(#"\b(?:has|have|with)\s+(?:\d{1,3}|one|two|three|several|multiple)\s+(?:callers?|references?|usages?)\b"#)

        static let definedPositive = compiled(#"\b([A-Za-z_][A-Za-z0-9_]{1,63})\s+(?:is|was)\s+(?:now\s+)?(?:defined|declared|implemented)\b"#)
        static let definedNegative = compiled(#"\b([A-Za-z_][A-Za-z0-9_]{1,63})\s+(?:is|was)\s+(?:not|no\s+longer)\s+(?:defined|declared|implemented)\b"#)
        static let declarationKeyword = compiled(#"\b(?:func|function|def|class|struct|enum|protocol|extension|interface|trait|const|let|var|type|module)\s+([A-Za-z_][A-Za-z0-9_]{1,63})\b"#)

        static let lineNumber = compiled(#"\blines?\s+(\d{1,6})\b"#)
        static let definesNeedle = compiled(#"\b(?:defines?|declares?|contains?|implements?|holds?|has)\s+(?:the\s+)?(?:function|method|class|struct|enum|protocol|type|property|constant|const|var|let|key|field|line|text|string)?\s*([A-Za-z_][A-Za-z0-9_]{1,63})\b"#)

        /// Presence and absence are separate patterns on purpose: deriving
        /// polarity from a bare "not" would flip "the file is not missing".
        /// The negator lookbehinds keep "does not exist" out of the presence
        /// list, which would otherwise trip the ambiguity guard and drop the
        /// claim entirely.
        static let existencePositive = compiled(#"\b(?:(?<!not\s)(?<!n['’]t\s)(?<!longer\s)(?<!never\s)exists?\b|there\s+is\s+(?:a\s+)?(?:new\s+)?(?:file|path|module|directory|folder)\b|is\s+(?:in|at|present|created|added)|can\s+be\s+found|lives\s+(?:in|at)|was\s+(?:added|created)|has\s+been\s+(?:added|created))\b"#)
        static let existenceNegative = compiled(#"\b(?:no\s+longer\s+exists|does\s+not\s+exist|doesn['’]t\s+exist|was\s+(?:removed|deleted|renamed)|has\s+been\s+(?:removed|deleted|renamed)|is\s+missing|there\s+is\s+no|there\s+are\s+no)\b"#)

        static let extensions = "swift|ts|tsx|js|jsx|mjs|cjs|py|rb|go|rs|java|kt|kts|c|h|cc|cpp|hpp|m|mm|cs|php|sh|bash|zsh|pl|lua|sql|html|css|scss|md|txt|json|yml|yaml|toml|xml|plist|lock|cfg|ini|env|gradle|strings|xcconfig"
        static let fileToken = compiled("(?<![\\w/.-])(?:[\\w.@+-]+/)*[\\w.@+-]+\\.(?:\(extensions))(?![\\w])")
        static let quoted = compiled(#"[`"']([^`"'\n]{1,80})[`"']"#)

        static let backticked = compiled(#"`([A-Za-z_][A-Za-z0-9_]{1,63})`"#)
        static let namedSymbols: [NSRegularExpression] = [
            compiled(#"\bno\s+other\s+(?:code\s+)?(?:callers?|calls?|uses?|usages?|references?)\s+(?:of|to|for)?\s*(?:the\s+)?(?:function|method|symbol|constant|property|class|struct)?\s*`?([A-Za-z_][A-Za-z0-9_]{2,63})`?\b"#),
            compiled(#"\bnothing\s+else\s+(?:calls?|uses?|references?)\s+(?:the\s+)?(?:function|method|symbol)?\s*`?([A-Za-z_][A-Za-z0-9_]{2,63})`?\b"#),
            compiled(#"\b(?:only|exactly)\s+(?:one|two|three|four|five|\d{1,3})\s+(?:callers?|references?|usages?)\s+(?:of|to|for)?\s*`?([A-Za-z_][A-Za-z0-9_]{2,63})`?\b"#),
            compiled(#"\b(?:remove|removes|removed|deletes?|deleted)\s+`?([A-Za-z_][A-Za-z0-9_]{2,63})`?\b"#)
        ]
        static let symbolStopwords: Set<String> = [
            "these", "those", "this", "that", "they", "their", "them", "there", "here", "code", "file", "files",
            "method", "methods", "function", "functions", "symbol", "symbols", "project", "repo", "repository",
            "callers", "caller", "references", "reference", "usages", "usage", "tests", "test", "suite", "build",
            "anything", "everything", "something", "which", "where", "when", "what", "some", "other", "others",
            "wire", "place", "thing", "things", "case", "cases", "line", "lines", "duplicate", "unused"
        ]
    }

    struct CommandRule {
        let kind: ClaimKind
        let subject: NSRegularExpression
        let positive: NSRegularExpression
        let negativeOutcome: NSRegularExpression
    }

    enum Rules {
        static let commands: [CommandRule] = [
            CommandRule(kind: .testsPass,
                        subject: compiled(#"\b(?:tests?|test\s+suite|specs?|unit\s+tests?|integration\s+tests?|suite)\b"#),
                        positive: compiled(#"\b(?:pass(?:es|ed|ing)?|green|succeed(?:s|ed)?|successful|all\s+good|is\s+fine|works?)\b"#),
                        negativeOutcome: compiled(#"\b(?:fails?|failing|failed|red|broken|do\s+not\s+pass|don['’]t\s+pass|does\s+not\s+pass|doesn['’]t\s+pass|aren['’]t\s+passing|isn['’]t\s+passing|never\s+passes?|didn['’]t\s+pass)\b"#)),
            CommandRule(kind: .buildSucceeds,
                        subject: compiled(#"\b(?:build|builds|building|compiles?|compiling|compil(?:ed|ation)|type-?checks?)\b"#),
                        positive: compiled(#"\b(?:succeed(?:s|ed)?|pass(?:es|ed)?|green|clean(?:ly)?|works?|fine|ok(?:ay)?)\b"#),
                        negativeOutcome: compiled(#"\b(?:fails?|failing|failed|broken|red|errors?|cannot\s+compile|do\s+not\s+build|don['’]t\s+build|does\s+not\s+build|doesn['’]t\s+build|won['’]t\s+compile|do\s+not\s+compile|does\s+not\s+compile)\b"#)),
            CommandRule(kind: .lintClean,
                        subject: compiled(#"\b(?:lint(?:er|ing)?|swiftlint|eslint|flake8|rubocop|prettier|format(?:ting)?\s+check|warnings?)\b"#),
                        positive: compiled(#"\b(?:clean|pass(?:es|ed)?|green|no\s+(?:warnings|errors|issues)|zero\s+warnings|is\s+fine)\b"#),
                        negativeOutcome: compiled(#"\b(?:warnings?|errors?|violations?|fails?|failing)\b"#))
        ]
    }
}

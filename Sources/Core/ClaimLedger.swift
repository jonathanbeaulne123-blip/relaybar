import Foundation

/// Evidence fingerprints reuse the engine's existing, dependency-free SHA-256
/// rather than a second copy of the algorithm, so a receipt's hashes and the
/// engine's own digests can never disagree. This adapter only adapts the byte
/// API; the algorithm lives in `Toolbox.swift`.
extension SHA256Digest {
    static func hex(_ data: Data) -> String { hexDigest(Array(data)) }
    static func hex(_ text: String) -> String { hexDigest(Array(text.utf8)) }
    static func shortHex(_ data: Data) -> String { String(hex(data).prefix(12)) }
}

/// What a claim asserts. The kind is the only thing that decides which local
/// probe or declared command could settle it.
public enum ClaimKind: String, Codable, CaseIterable {
    case testsPass
    case buildSucceeds
    case lintClean
    case fileExists
    case lineContains
    case symbolDefined
    case referenceCount
    case gitFact
    /// A recognizable factual statement with no local probe available.
    case assertion
    /// Hedged, proposed, or opinionated text. Never treated as a claim to settle.
    case notFalsifiable

    public var title: String {
        switch self {
        case .testsPass: return "Tests"
        case .buildSucceeds: return "Build"
        case .lintClean: return "Lint"
        case .fileExists: return "File"
        case .lineContains: return "Location"
        case .symbolDefined: return "Definition"
        case .referenceCount: return "References"
        case .gitFact: return "Git state"
        case .assertion: return "Statement"
        case .notFalsifiable: return "Opinion or plan"
        }
    }

    /// The declared command kind that settles this claim, when one exists.
    public var verifyCommandKind: VerifyCommandKind? {
        switch self {
        case .testsPass: return .tests
        case .buildSucceeds: return .build
        case .lintClean: return .lint
        default: return nil
        }
    }
}

/// Where the text under review came from. Recorded because it changes what the
/// receipt is allowed to say: an assistant reply is not the user's own draft.
public enum ClaimSource: String, Codable, CaseIterable {
    case draft
    case reference
    case clipboard
    case assistantReply

    public var label: String {
        switch self {
        case .draft: return "Composed draft"
        case .reference: return "Captured reference"
        case .clipboard: return "Clipboard text"
        case .assistantReply: return "Pasted assistant reply"
        }
    }
}

/// Affirmative text asserts the statement; negative text asserts its absence.
/// The polarity is part of the claim, not a footnote, because "the tests do not
/// pass" and "the tests pass" demand opposite evidence.
public enum ClaimPolarity: String, Codable {
    case affirmative
    case negative

    public var flipped: ClaimPolarity { self == .affirmative ? .negative : .affirmative }
}

public enum ClaimVerdict: String, Codable, CaseIterable {
    case verified
    case refuted
    case unverified
    case notCheckable

    public var mark: String {
        switch self {
        case .verified: return "✅"
        case .refuted: return "❌"
        case .unverified: return "⚠️"
        case .notCheckable: return "⏭"
        }
    }

    public var title: String {
        switch self {
        case .verified: return "VERIFIED"
        case .refuted: return "REFUTED"
        case .unverified: return "UNVERIFIED"
        case .notCheckable: return "NOT CHECKABLE"
        }
    }
}

/// A bounded, read-only local check. Every case carries the token as written;
/// resolution against the project root happens in one guarded place.
public enum ClaimProbe: Codable, Equatable {
    case fileExists(path: String)
    case lineContains(path: String, line: Int, needle: String)
    case symbolDefined(name: String)
    case referenceCount(name: String, expected: ReferenceExpectation)
    case gitFact(GitFactExpectation)
}

public enum GitFactExpectation: String, Codable, Equatable {
    case clean
    case dirty

    public var title: String { self == .clean ? "working tree clean" : "uncommitted changes present" }

    /// Reads inside a sentence: "Working tree is dirty (uncommitted changes
    /// present)". The title alone would produce "Working tree is uncommitted
    /// changes present".
    public var notePhrase: String {
        switch self {
        case .clean: return "clean (no uncommitted changes)"
        case .dirty: return "dirty (uncommitted changes present)"
        }
    }
}

public enum ReferenceExpectation: Codable, Equatable {
    case zero
    case atLeastOne
    case exactly(Int)

    public var title: String {
        switch self {
        case .zero: return "no references"
        case .atLeastOne: return "at least one reference"
        case .exactly(let count): return "exactly \(count) references"
        }
    }

    public func matches(_ count: Int) -> Bool {
        switch self {
        case .zero: return count == 0
        case .atLeastOne: return count >= 1
        case .exactly(let expected): return count == expected
        }
    }
}

public enum ClaimCheckStrategy: Codable, Equatable {
    case observe(ClaimProbe)
    case execute(VerifyCommandKind)
    /// Settling this is outside RelayBar's local, read-only authority.
    case impossible(String)

    public var title: String {
        switch self {
        case .observe(let probe):
            switch probe {
            case .fileExists: return "Read a path"
            case .lineContains: return "Read a line"
            case .symbolDefined, .referenceCount: return "Scan the project"
            case .gitFact: return "Read Git state"
            }
        case .execute(let kind): return "Run the declared \(kind.declaredNoun)"
        case .impossible: return "No local check"
        }
    }
}

/// What RelayBar actually observed, with a fingerprint of the observed bytes.
public struct ClaimEvidence: Codable, Equatable {
    public let method: String
    /// Non-nil only when a declared command ran. Never synthesized.
    public let commandLine: String?
    public let summary: String
    /// Bounded verbatim observation. Never normalized or reworded.
    public let excerpt: String
    /// SHA-256 of the exact observation input: the bytes read, the line text,
    /// the sorted scan hits, the Git porcelain output, or the command output.
    /// Empty only when nothing at all could be read.
    public let contentHash: String
    public let exitCode: Int32?
    public let durationSeconds: Double?
    /// Non-nil when the check ran inside a throwaway rehearsal worktree.
    public let worktreePath: String?
    public let baseCommit: String
    public let observedAt: Date

    public init(
        method: String,
        commandLine: String? = nil,
        summary: String,
        excerpt: String = "",
        contentHash: String = "",
        exitCode: Int32? = nil,
        durationSeconds: Double? = nil,
        worktreePath: String? = nil,
        baseCommit: String,
        observedAt: Date = Date()
    ) {
        self.method = method
        self.commandLine = commandLine
        self.summary = summary
        self.excerpt = excerpt
        self.contentHash = contentHash
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
        self.worktreePath = worktreePath
        self.baseCommit = baseCommit
        // Evidence is persisted as ISO-8601 to the second. Aligning the stamp at
        // creation keeps an in-memory receipt equal to the one read back.
        self.observedAt = LedgerPolicy.persistedPrecision(observedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case method, commandLine, summary, excerpt, contentHash, exitCode, durationSeconds, worktreePath, baseCommit, observedAt
    }

    public func validate() throws {
        guard method.count <= LedgerPolicy.maxMethodCharacters else {
            throw RelayError.invalid("Evidence methods are limited to \(LedgerPolicy.maxMethodCharacters) characters.")
        }
        guard summary.count <= LedgerPolicy.maxSummaryCharacters else {
            throw RelayError.invalid("Evidence summaries are limited to \(LedgerPolicy.maxSummaryCharacters) characters.")
        }
        guard excerpt.count <= LedgerPolicy.maxStoredExcerptCharacters else {
            throw RelayError.invalid("Evidence excerpts are limited to \(LedgerPolicy.maxExcerptCharacters) characters; nothing was truncated silently.")
        }
        guard contentHash.isEmpty || Self.isDigest(contentHash) else {
            throw RelayError.invalid("Evidence must carry a hexadecimal SHA-256 fingerprint or none at all.")
        }
        guard baseCommit.count <= 128, (worktreePath ?? "").count <= 1_024 else {
            throw RelayError.invalid("Invalid evidence metadata.")
        }
    }

    public static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

/// One reviewed statement. `included` mirrors the Context Stack rule: the user
/// keeps the final say over what leaves the app.
public struct Claim: Codable, Identifiable, Equatable {
    public let id: UUID
    /// The verbatim sentence, exactly as it appeared in the reviewed text.
    public let text: String
    /// Display-only, control and bidirectional-override characters removed.
    public let display: String
    public let kind: ClaimKind
    public let polarity: ClaimPolarity
    public let source: ClaimSource
    public let strategy: ClaimCheckStrategy
    public var included: Bool
    public var verdict: ClaimVerdict
    public var note: String
    public var evidence: ClaimEvidence?
    /// Set when the tree moved after this was settled, so a receipt never
    /// presents a stale observation as current.
    public var isStale: Bool

    public var id_string: String { id.uuidString }

    public init(
        id: UUID = UUID(),
        text: String,
        display: String? = nil,
        kind: ClaimKind,
        polarity: ClaimPolarity = .affirmative,
        source: ClaimSource,
        strategy: ClaimCheckStrategy,
        included: Bool = true,
        verdict: ClaimVerdict = .unverified,
        note: String = "",
        evidence: ClaimEvidence? = nil,
        isStale: Bool = false
    ) {
        self.id = id
        self.text = text
        self.display = display ?? LedgerPolicy.displayText(text, limit: LedgerPolicy.maxClaimCharacters)
        self.kind = kind
        self.polarity = polarity
        self.source = source
        self.strategy = strategy
        self.included = included
        self.verdict = verdict
        self.note = note
        self.evidence = evidence
        self.isStale = isStale
    }

    public func validate() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayError.invalid("A claim cannot be empty.")
        }
        guard text.count <= LedgerPolicy.maxClaimCharacters else {
            throw RelayError.invalid("Claims are limited to \(LedgerPolicy.maxClaimCharacters) characters; nothing was truncated silently.")
        }
        guard note.count <= LedgerPolicy.maxSummaryCharacters else {
            throw RelayError.invalid("Claim notes are limited to \(LedgerPolicy.maxSummaryCharacters) characters.")
        }
        guard !(verdict == .verified && evidence == nil) else {
            throw RelayError.invalid("A verified claim must carry observed evidence.")
        }
        try evidence?.validate()
    }

    /// The verdict as it should be read now.
    public var effectiveVerdict: ClaimVerdict { isStale ? .unverified : verdict }
}

public struct LedgerSummary: Codable, Equatable {
    public var verified = 0
    public var refuted = 0
    public var unverified = 0
    public var notCheckable = 0
    public var stale = 0
    public var included = 0
    public var total = 0
}

/// A reviewed set of claims about one revision of one project.
public struct ClaimLedger: Codable, Identifiable, Equatable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public let schemaVersion: Int
    public let createdAt: Date
    public let projectID: String
    public let projectName: String
    public let gitRoot: String
    public let baseCommit: String
    /// The observed Git state when the claims were extracted. Reuses the
    /// reality snapshot record so one shape describes "state at a moment".
    public let treeState: GitSnapshotRecord
    public let source: ClaimSource
    /// Verbatim first 400 characters of the reviewed text, for the audit trail.
    public let sourcePreview: String
    public var claims: [Claim]
    /// Sentences RelayBar examined and did not recognize as claims.
    public let unmatchedSentenceCount: Int
    /// Fenced code-block lines excluded from claim extraction.
    public let excludedCodeFenceLines: Int
    /// True when the source exceeded the size cap, or the claim cap was reached.
    public let truncated: Bool
    public var revision: UUID

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        projectID: String,
        projectName: String,
        gitRoot: String,
        baseCommit: String,
        treeState: GitSnapshotRecord,
        source: ClaimSource,
        sourcePreview: String,
        claims: [Claim],
        unmatchedSentenceCount: Int,
        excludedCodeFenceLines: Int,
        truncated: Bool
    ) {
        self.id = id
        self.schemaVersion = Self.currentSchemaVersion
        // Same reason as `ClaimEvidence`: the persisted format is ISO-8601 to
        // the second, so a round trip through storage must be lossless.
        self.createdAt = LedgerPolicy.persistedPrecision(createdAt)
        self.projectID = projectID
        self.projectName = projectName
        self.gitRoot = gitRoot
        self.baseCommit = baseCommit
        self.treeState = treeState
        self.source = source
        self.sourcePreview = sourcePreview
        self.claims = claims
        self.unmatchedSentenceCount = unmatchedSentenceCount
        self.excludedCodeFenceLines = excludedCodeFenceLines
        self.truncated = truncated
        self.revision = UUID()
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw RelayError.invalid("Unsupported claim ledger version.") }
        guard !projectID.isEmpty, projectID.count <= 100 else { throw RelayError.invalid("A ledger must reference a valid project.") }
        guard !gitRoot.isEmpty, URL(fileURLWithPath: gitRoot).isFileURL else { throw RelayError.invalid("A ledger must reference a local project root.") }
        guard claims.count <= LedgerPolicy.maxClaims else { throw RelayError.invalid("Ledgers are limited to \(LedgerPolicy.maxClaims) claims.") }
        guard unmatchedSentenceCount >= 0, excludedCodeFenceLines >= 0 else { throw RelayError.invalid("Ledger counts cannot be negative.") }
        guard sourcePreview.count <= LedgerPolicy.maxClaimCharacters else { throw RelayError.invalid("The ledger preview is too large.") }
        try treeState.validate()
        for claim in claims { try claim.validate() }
    }

    public var summary: LedgerSummary {
        var result = LedgerSummary()
        result.total = claims.count
        for claim in claims where claim.included {
            result.included += 1
            if claim.isStale { result.stale += 1; continue }
            switch claim.verdict {
            case .verified: result.verified += 1
            case .refuted: result.refuted += 1
            case .unverified: result.unverified += 1
            case .notCheckable: result.notCheckable += 1
            }
        }
        return result
    }

    /// A ledger describes one commit. If the repository moved, every settled
    /// observation is marked stale rather than quietly re-read.
    public func staled(against commit: String) -> ClaimLedger {
        guard !baseCommit.isEmpty, !commit.isEmpty, commit != baseCommit else { return self }
        var copy = self
        for index in copy.claims.indices where copy.claims[index].evidence != nil {
            copy.claims[index].isStale = true
        }
        copy.revision = UUID()
        return copy
    }

    /// A claim may only leave as authored if it is not a fabricated quote. The
    /// stored text is verbatim, so this is a length check, not a rewrite.
    public func claim(id: UUID) -> Claim? { claims.first(where: { $0.id == id }) }
}

public enum LedgerPolicy {
    public static let maxClaims = 24
    public static let maxClaimCharacters = 400
    public static let maxSourceBytes = 65_536
    public static let maxExcerptCharacters = 4_096
    /// Excerpts may exceed the content bound by one labelled cut marker, which
    /// is how a bounded excerpt stays honest about being bounded.
    public static let maxStoredExcerptCharacters = 4_400
    public static let maxSummaryCharacters = 600
    public static let maxMethodCharacters = 200
    public static let maxPathCharacters = 512
    public static let maxSymbolCharacters = 64
    public static let minSentenceCharacters = 8
    public static let maxRenderedHits = 5
    public static let maxScanFiles = 4_000
    public static let maxScanFileBytes = 1_000_000
    public static let maxScanHits = 50
    /// Directories that never hold project source worth scanning.
    public static let skippedDirectories: Set<String> = [
        ".git", ".build", "build", "node_modules", "DerivedData", "Pods", ".swiftpm",
        "vendor", "dist", "target", "__pycache__", ".venv", "venv", ".idea", ".vscode"
    ]
    public static let skippedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "pdf", "icns", "ico", "zip", "gz", "tgz", "o", "a",
        "dylib", "so", "dSYM", "class", "jar", "woff", "woff2", "ttf", "otf", "mp4", "mov", "heic"
    ]

    /// Timestamps are stored as ISO-8601 to the second, so any stamp a receipt
    /// carries is truncated to that precision when it is created rather than
    /// when it is written. A ledger therefore compares equal to its own
    /// round-tripped copy, and no reader can be handed a timestamp that will
    /// not survive a save.
    public static func persistedPrecision(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// Display-only normalization. Mirrors the Context Stack rule: control
    /// characters and bidirectional overrides are stripped for display, and the
    /// stored text is never altered.
    public static func displayText(_ text: String, limit: Int) -> String {
        let safe = text.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
        }.filter { !(0x202A...0x202E).contains($0.value) && !(0x2066...0x2069).contains($0.value) }
        let flattened = String(String.UnicodeScalarView(safe))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(flattened.prefix(max(1, limit)))
    }

    /// Deterministic key for duplicate detection. Comparison only.
    public static func comparisonKey(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }
}

public enum ClaimLedgerError: LocalizedError, Equatable {
    case noProjectRoot
    case emptySource
    case oversizedSource
    case nothingRecognized

    public var errorDescription: String? {
        switch self {
        case .noProjectRoot:
            return "RelayBar needs a project root with Git to check claims against. Nothing was executed."
        case .emptySource:
            return "The text to review is empty or only whitespace. Nothing was executed."
        case .oversizedSource:
            return "This text exceeds the 64 KiB review limit. Split it and review a smaller passage; nothing was truncated or executed."
        case .nothingRecognized:
            return "No statement in this text could be recognized as a checkable claim. Nothing was executed."
        }
    }
}

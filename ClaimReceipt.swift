import Foundation

public struct ReplyAuditFinding: Codable, Equatable {
    public enum Relationship: String, Codable {
        /// The receipt refuted this or could not confirm it, and the reply
        /// states it again as fact.
        case repeatedUnverified
        /// The receipt verified the opposite, and the reply asserts the reverse.
        case disagreesWithReceipt

        public var mark: String { "❗" }

        public var title: String {
            switch self {
            case .repeatedUnverified: return "REPEATED-UNVERIFIED"
            case .disagreesWithReceipt: return "DISAGREES-WITH-RECEIPT"
            }
        }

        /// Deliberately about the receipt, never about the author's honesty.
        public var explanation: String {
            switch self {
            case .repeatedUnverified:
                return "The receipt did not confirm this, and the reply presents it as fact."
            case .disagreesWithReceipt:
                return "The receipt recorded the opposite. The reply may be right; RelayBar has not re-checked it."
            }
        }
    }

    public let claimID: UUID
    public let claimText: String
    public let claimKind: ClaimKind
    public let claimVerdict: ClaimVerdict
    public let replySentence: String
    public let relationship: Relationship
}

/// Deterministic text output. Nothing here is copied to the clipboard by this
/// type: the controller is the only caller that writes, and it never pastes.
public enum ClaimReceiptRenderer {
    public static func receipt(_ ledger: ClaimLedger) -> String {
        var lines: [String] = []
        lines.append("CLAIM LEDGER — \(ledger.projectName)")
        lines.append("Ledger \(ledger.id.uuidString) · created \(timestamp(ledger.createdAt)) · source: \(ledger.source.label)")
        lines.append("Project root: \(ledger.gitRoot)")
        lines.append("Base commit: \(ledger.baseCommit.isEmpty ? "unknown" : ledger.baseCommit) · working tree when reviewed: \(treeLine(ledger.treeState))")
        lines.append("Reviewed text (first \(min(ledger.sourcePreview.count, LedgerPolicy.maxClaimCharacters)) characters):")
        lines.append(ledger.sourcePreview)
        lines.append("")

        let summary = ledger.summary
        lines.append("CLAIMS — \(summary.included)/\(summary.total) included")
        if ledger.claims.isEmpty {
            lines.append("No statement in this text was recognized as a checkable claim.")
        }
        for claim in ledger.claims where claim.included {
            lines.append(claimLine(claim))
        }
        let excluded = ledger.claims.filter { !$0.included }
        if !excluded.isEmpty {
            lines.append("")
            lines.append("EXCLUDED BY THE USER — \(excluded.count) claim(s) were removed from this receipt and are not covered:")
            for claim in excluded { lines.append("· \(LedgerPolicy.displayText(claim.display, limit: 160))") }
        }

        lines.append("")
        lines.append("COVERAGE — what this receipt does NOT establish")
        lines.append("· \(ledger.unmatchedSentenceCount) statement(s) were not recognized as claims and are not covered by any verdict below.")
        if ledger.excludedCodeFenceLines > 0 {
            lines.append("· \(ledger.excludedCodeFenceLines) line(s) inside fenced code blocks were not treated as claims.")
        }
        if ledger.truncated {
            lines.append("· The \(LedgerPolicy.maxClaims)-claim limit was reached, so later statements in this text are not covered.")
        }
        if summary.stale > 0 {
            lines.append("· \(summary.stale) settled claim(s) are STALE: the repository moved after they were observed.")
        }
        if summary.verified == 0 {
            lines.append("· Nothing in this text was verified. Treat every claim above as unverified.")
        }
        lines.append("· A verified claim describes the recorded base commit and observation time only. RelayBar did not send, paste, or publish anything.")
        return lines.joined(separator: "\n")
    }

    /// Compact block intended to be appended to a handoff prompt. It states
    /// plainly that unlisted text is unverified, so the packet cannot be read
    /// as carrying more evidence than it does.
    public static func promptAddendum(_ ledger: ClaimLedger) -> String {
        var lines: [String] = []
        lines.append("## Evidence receipt (RelayBar, local)")
        lines.append("RelayBar observed these results on this machine before the packet was copied. Ledger \(ledger.id.uuidString), base commit \(ledger.baseCommit.isEmpty ? "unknown" : ledger.baseCommit).")
        for claim in ledger.claims where claim.included {
            let verdict = claim.effectiveVerdict
            guard verdict == .verified || verdict == .refuted || verdict == .unverified else { continue }
            let evidence = claim.evidence.map { " — \($0.summary)" } ?? ""
            lines.append("- \(verdict.title): \"\(LedgerPolicy.displayText(claim.display, limit: 200))\"\(evidence)")
        }
        if ledger.claims.filter({ $0.included && $0.effectiveVerdict == .notCheckable }).isEmpty == false {
            let count = ledger.claims.filter { $0.included && $0.effectiveVerdict == .notCheckable }.count
            lines.append("- NOT CHECKABLE: \(count) statement(s) are proposals, opinions, or beyond RelayBar's local checks.")
        }
        lines.append("- NOT COVERED: \(ledger.unmatchedSentenceCount) statement(s) in my message were not recognized as claims, and none of this receipt applies to them.")
        lines.append("Anything not listed as VERIFIED above is unverified. Do not restate it as established fact.")
        return lines.joined(separator: "\n")
    }

    public static func auditSummary(_ findings: [ReplyAuditFinding], ledger: ClaimLedger) -> String {
        guard !findings.isEmpty else {
            return "REPLY AUDIT — no claim in this reply repeats something the receipt left unverified or refuted.\nLedger \(ledger.id.uuidString). The reply may still contain claims that were never reviewed."
        }
        var lines: [String] = []
        lines.append("REPLY AUDIT — \(findings.count) statement(s) that this receipt does not support")
        lines.append("Ledger \(ledger.id.uuidString) · base commit \(ledger.baseCommit.isEmpty ? "unknown" : ledger.baseCommit)")
        lines.append("")
        for finding in findings {
            lines.append("\(finding.relationship.mark) \(finding.relationship.title)")
            lines.append("  Reply: \"\(LedgerPolicy.displayText(finding.replySentence, limit: 240))\"")
            lines.append("  Receipt: \(finding.claimVerdict.title) · \(LedgerPolicy.displayText(finding.claimText, limit: 200))")
            lines.append("  \(finding.relationship.explanation)")
        }
        lines.append("")
        lines.append("This is a comparison against RelayBar's own receipt, not a judgement about the reply's author, and RelayBar did not re-run any check for it.")
        return lines.joined(separator: "\n")
    }

    // MARK: Rendering helpers

    private static func claimLine(_ claim: Claim) -> String {
        let verdict = claim.effectiveVerdict
        var lines: [String] = []
        lines.append("\(verdict.mark) \(verdict.title)\(claim.isStale ? " (STALE)" : "") · \"\(LedgerPolicy.displayText(claim.display, limit: 240))\"")
        if !claim.note.isEmpty { lines.append("   ↳ \(claim.note)") }
        if let evidence = claim.evidence {
            var detail = "method \(evidence.method) · sha256 \(String(evidence.contentHash.prefix(12)))"
            if let exitCode = evidence.exitCode { detail += " · exit \(exitCode)" }
            if let duration = evidence.durationSeconds { detail += " · \(String(format: "%.1f", duration))s" }
            if let worktree = evidence.worktreePath { detail += " · worktree \(worktree)" }
            lines.append("   ⇥ \(detail) · observed \(timestamp(evidence.observedAt))")
        }
        return lines.joined(separator: "\n")
    }

    private static func treeLine(_ tree: GitSnapshotRecord) -> String {
        let state = tree.isDirty ? "dirty" : "clean"
        return "\(state) (branch \(tree.branch.isEmpty ? "unknown" : tree.branch), \(tree.modifiedCount) modified, \(tree.stagedCount) staged, \(tree.untrackedCount) untracked)"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// Matches a reply's claims against a ledger. Deterministic, local, and
/// conservative: a paraphrase below the similarity threshold is not reported,
/// because a false accusation is worse than a missed reminder.
public enum ClaimMatcher {
    public static let similarityThreshold = 0.6

    public static func audit(ledger: ClaimLedger, reply: String) -> [ReplyAuditFinding] {
        let extraction = ClaimExtractor.extract(from: reply, source: .assistantReply)
        var findings: [ReplyAuditFinding] = []
        for replyClaim in extraction.claims {
            guard replyClaim.kind != .notFalsifiable else { continue }
            guard let candidate = bestMatch(replyClaim, in: ledger.claims) else { continue }
            switch candidate.effectiveVerdict {
            case .unverified, .refuted:
                findings.append(make(replyClaim, candidate, .repeatedUnverified))
            case .verified:
                // Agreeing with verified evidence is not a finding. Asserting
                // the opposite is worth showing, framed as "not re-checked".
                if replyClaim.polarity != candidate.polarity {
                    findings.append(make(replyClaim, candidate, .disagreesWithReceipt))
                }
            case .notCheckable:
                break
            }
        }
        return findings
    }

    public static func bestMatch(_ claim: Claim, in claims: [Claim]) -> Claim? {
        var best: (claim: Claim, score: Double)?
        for candidate in claims where candidate.included && candidate.kind == claim.kind {
            if case .impossible = candidate.strategy { continue }
            let numbersAgree = numbers(in: claim.text) == numbers(in: candidate.text)
            let score = numbersAgree ? similarity(candidate.text, claim.text) : 0
            guard score >= similarityThreshold else { continue }
            if best == nil || score > best!.score { best = (candidate, score) }
        }
        return best?.claim
    }

    /// Jaccard similarity over content words. Numbers are treated separately,
    /// because "3 callers" and "5 callers" are different claims, not similar ones.
    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = contentWords(lhs), b = contentWords(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let union = a.union(b)
        guard !union.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(union.count)
    }

    static func contentWords(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 && !stopwords.contains($0) })
    }

    static func numbers(in text: String) -> Set<String> {
        Set(text.split(whereSeparator: { !$0.isNumber }).map(String.init))
    }

    private static func make(_ replyClaim: Claim, _ candidate: Claim, _ relationship: ReplyAuditFinding.Relationship) -> ReplyAuditFinding {
        ReplyAuditFinding(claimID: candidate.id, claimText: candidate.text, claimKind: candidate.kind,
                          claimVerdict: candidate.effectiveVerdict, replySentence: replyClaim.text,
                          relationship: relationship)
    }

    static let stopwords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "these", "those", "from", "into", "was", "were", "are", "is",
        "has", "have", "had", "not", "but", "you", "your", "our", "its", "it", "of", "to", "in", "on", "at", "as",
        "be", "been", "being", "will", "would", "can", "could", "should", "may", "might", "must", "do", "does",
        "did", "done", "then", "than", "there", "here", "which", "who", "whom", "what", "when", "where", "why",
        "how", "all", "any", "both", "each", "few", "more", "most", "other", "some", "such", "no", "nor", "only",
        "own", "same", "so", "too", "very", "just", "now", "also", "if", "or", "because", "while", "about",
        "after", "again", "against", "before", "below", "between", "during", "once", "over", "under", "up", "down",
        "out", "off", "above", "further", "me", "my", "we", "us", "they", "them", "their", "he", "she", "his",
        "her", "him", "i", "am", "an", "a"
    ]
}

/// Compact Touch Bar text. Kept here so the strip's wording is unit-tested with
/// the same rules that produce the receipt.
public enum LedgerChip {
    public static func title(for ledger: ClaimLedger) -> String {
        let summary = ledger.summary
        guard summary.total > 0 else { return "🔎 No claims" }
        var parts: [String] = []
        if summary.verified > 0 { parts.append("\(summary.verified)✓") }
        if summary.refuted > 0 { parts.append("\(summary.refuted)✗") }
        if summary.unverified > 0 { parts.append("\(summary.unverified)⚠") }
        if summary.notCheckable > 0 { parts.append("\(summary.notCheckable)⏭") }
        if summary.stale > 0 { parts.append("\(summary.stale)↻") }
        return "🔎 " + parts.joined(separator: " ")
    }

    public static func help(for ledger: ClaimLedger) -> String {
        let summary = ledger.summary
        return "Claim ledger: \(summary.verified) verified, \(summary.refuted) refuted, \(summary.unverified) unverified, \(summary.notCheckable) not checkable, \(summary.stale) stale. Opens the ledger before any check runs."
    }

    public static func auditTitle(_ findings: [ReplyAuditFinding]) -> String {
        findings.isEmpty ? "✓ Reply audited" : "❗ \(findings.count) repeated"
    }
}

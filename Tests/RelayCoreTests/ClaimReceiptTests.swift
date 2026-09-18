import XCTest
@testable import RelayCore

/// The receipt is the artifact a user actually sends, so these tests check the
/// two ways it could lie: promoting an unsettled claim, or hiding what it did
/// not look at.
final class ClaimReceiptTests: XCTestCase {

    private func evidence(_ method: String) -> ClaimEvidence {
        ClaimEvidence(method: method, commandLine: "swift test", summary: "exit 0", excerpt: "ok",
                      contentHash: String(repeating: "a", count: 64), exitCode: 0, durationSeconds: 1.5, baseCommit: "abc123")
    }

    private func ledger(claims: [Claim], unmatched: Int = 0, truncated: Bool = false, fenced: Int = 0,
                        commit: String = "abc123") -> ClaimLedger {
        ClaimLedger(
            projectID: "hearth",
            projectName: "Hearth",
            gitRoot: "/tmp/hearth",
            baseCommit: commit,
            treeState: GitSnapshotRecord(branch: "main", commit: commit, isDirty: false, modifiedCount: 0, stagedCount: 0, untrackedCount: 0),
            source: .assistantReply,
            sourcePreview: "The tests pass.",
            claims: claims,
            unmatchedSentenceCount: unmatched,
            excludedCodeFenceLines: fenced,
            truncated: truncated
        )
    }

    private func claim(_ text: String, _ kind: ClaimKind, _ verdict: ClaimVerdict,
                       polarity: ClaimPolarity = .affirmative, included: Bool = true,
                       strategy: ClaimCheckStrategy = .execute(.tests), withEvidence: Bool = false) -> Claim {
        Claim(text: text, kind: kind, polarity: polarity, source: .assistantReply, strategy: strategy,
              included: included, verdict: verdict, note: verdict == .verified ? "Declared test command exited 0." : "Not confirmed.",
              evidence: withEvidence ? evidence("Ran the declared test command") : nil)
    }

    // MARK: Receipt

    func testReceiptNeverPromotesAnUnsettledClaim() {
        let text = ClaimReceiptRenderer.receipt(ledger(claims: [
            claim("the tests pass", .testsPass, .verified, withEvidence: true),
            claim("the build succeeds", .buildSucceeds, .unverified, strategy: .impossible("No build command is declared.")),
            claim("we should revisit this", .notFalsifiable, .notCheckable, strategy: .impossible("Proposal."))
        ]))
        XCTAssertTrue(text.contains("✅ VERIFIED · \"the tests pass\""))
        XCTAssertTrue(text.contains("⚠️ UNVERIFIED"))
        XCTAssertTrue(text.contains("⏭ NOT CHECKABLE"))
        XCTAssertEqual(text.components(separatedBy: "✅ VERIFIED").count - 1, 1)
        XCTAssertTrue(text.contains("sha256 aaaaaaaaaaaa"))
    }

    func testReceiptDisclosesEverythingItDidNotCover() {
        let text = ClaimReceiptRenderer.receipt(ledger(
            claims: [claim("the tests pass", .testsPass, .unverified)],
            unmatched: 7, truncated: true, fenced: 12
        ))
        XCTAssertTrue(text.contains("7 statement(s) were not recognized as claims"))
        XCTAssertTrue(text.contains("12 line(s) inside fenced code blocks"))
        XCTAssertTrue(text.contains("claim limit was reached"))
        XCTAssertTrue(text.contains("Nothing in this text was verified"))
    }

    func testExcludedClaimsAreListedAndNotCounted() {
        let text = ClaimReceiptRenderer.receipt(ledger(claims: [
            claim("the tests pass", .testsPass, .verified, included: false, withEvidence: true),
            claim("there are no other callers of scanLedger", .referenceCount, .unverified, included: true,
                  strategy: .observe(.referenceCount(name: "scanLedger", expected: .zero)))
        ]))
        XCTAssertTrue(text.contains("EXCLUDED BY THE USER — 1 claim(s)"))
        XCTAssertTrue(text.contains("CLAIMS — 1/2 included"))
        XCTAssertFalse(text.contains("✅ VERIFIED"), "An excluded claim must not be presented as verified")
    }

    func testStaleClaimsAreCalledOut() {
        var staled = claim("the tests pass", .testsPass, .verified, withEvidence: true)
        staled.isStale = true
        let text = ClaimReceiptRenderer.receipt(ledger(claims: [staled]))
        XCTAssertTrue(text.contains("(STALE)"))
        XCTAssertTrue(text.contains("STALE: the repository moved"))
        XCTAssertFalse(text.contains("✅ VERIFIED"))
    }

    // MARK: Prompt addendum

    func testPromptAddendumStatesWhatIsNotCovered() {
        let addendum = ClaimReceiptRenderer.promptAddendum(ledger(
            claims: [claim("the tests pass", .testsPass, .verified, withEvidence: true),
                     claim("the build succeeds", .buildSucceeds, .unverified)],
            unmatched: 3
        ))
        XCTAssertTrue(addendum.contains("VERIFIED: \"the tests pass\""))
        XCTAssertTrue(addendum.contains("UNVERIFIED: \"the build succeeds\""))
        XCTAssertTrue(addendum.contains("NOT COVERED: 3 statement(s)"))
        XCTAssertTrue(addendum.contains("Do not restate it as established fact"))
    }

    // MARK: Reply audit

    func testReplyRestatingAnUnverifiedClaimIsFlagged() {
        let ledger = ledger(claims: [claim("The tests pass", .testsPass, .unverified)])
        let findings = ClaimMatcher.audit(ledger: ledger, reply: "The tests pass, so I moved on.")
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.relationship, .repeatedUnverified)
        XCTAssertEqual(findings.first?.claimVerdict, .unverified)
    }

    /// Prose wraps a claim in extra clauses, so a restatement has to be found
    /// inside a longer sentence rather than only in a sentence of equal size.
    func testReplyRestatingAClaimInsideALongerSentenceIsFlagged() {
        let ledger = ledger(claims: [claim("The test suite passes on this machine.", .testsPass, .unverified)])
        let findings = ClaimMatcher.audit(ledger: ledger, reply: "All good — the test suite passes, so I merged it.")
        XCTAssertEqual(findings.first?.relationship, .repeatedUnverified)
        XCTAssertEqual(findings.first?.claimVerdict, .unverified)
    }

    /// The counterweight: one word in common is a coincidence, and this feature
    /// must not accuse a reply of repeating something it never said.
    func testOneSharedWordIsNotARepetition() {
        let ledger = ledger(claims: [claim("The build succeeds", .buildSucceeds, .unverified,
                                          strategy: .execute(.build))])
        XCTAssertTrue(ClaimMatcher.audit(ledger: ledger, reply: "The build system is a separate project.").isEmpty)
        XCTAssertEqual(ClaimMatcher.similarity("The tests pass", "Tests are a habit."), 0)
    }

    func testReplyRestatingARefutedClaimIsFlagged() {
        let ledger = ledger(claims: [claim("The tests pass", .testsPass, .refuted)])
        XCTAssertEqual(ClaimMatcher.audit(ledger: ledger, reply: "The tests pass.").first?.relationship, .repeatedUnverified)
    }

    func testReplyAgreeingWithVerifiedEvidenceIsNotFlagged() {
        let ledger = ledger(claims: [claim("The tests pass", .testsPass, .verified, withEvidence: true)])
        XCTAssertTrue(ClaimMatcher.audit(ledger: ledger, reply: "The tests pass.").isEmpty)
    }

    func testReplyContradictingVerifiedEvidenceIsReportedWithoutReChecking() {
        let ledger = ledger(claims: [claim("The tests pass", .testsPass, .verified, withEvidence: true)])
        let findings = ClaimMatcher.audit(ledger: ledger, reply: "The tests do not pass on your machine.")
        XCTAssertEqual(findings.first?.relationship, .disagreesWithReceipt)
        XCTAssertTrue(findings.first?.relationship.explanation.contains("may be right") ?? false)
    }

    func testUnrelatedReplyIsNotFlagged() {
        let ledger = ledger(claims: [claim("The test suite passes", .testsPass, .unverified)])
        XCTAssertTrue(ClaimMatcher.audit(ledger: ledger, reply: "The packaging tests pass on Linux.").isEmpty)
        XCTAssertTrue(ClaimMatcher.audit(ledger: ledger, reply: "I will refactor the loader next.").isEmpty)
        XCTAssertTrue(ClaimMatcher.audit(ledger: ledger, reply: "").isEmpty)
    }

    func testDifferentNumbersAreDifferentClaims() {
        let ledger = ledger(claims: [claim("There are exactly two callers of `scanLedger`.", .referenceCount, .unverified,
                                           strategy: .observe(.referenceCount(name: "scanLedger", expected: .exactly(2))))])
        XCTAssertTrue(ClaimMatcher.audit(ledger: ledger, reply: "There are exactly three callers of `scanLedger`.").isEmpty)
    }

    func testAuditSummaryIsExplicitAboutItsOwnLimit() {
        let source = ledger(claims: [claim("The tests pass", .testsPass, .unverified)])
        let findings = ClaimMatcher.audit(ledger: source, reply: "The tests pass.")
        let summary = ClaimReceiptRenderer.auditSummary(findings, ledger: source)
        XCTAssertTrue(summary.contains("REPEATED-UNVERIFIED"))
        XCTAssertTrue(summary.contains("not a judgement about the reply's author"))
        XCTAssertTrue(ClaimReceiptRenderer.auditSummary([], ledger: source).contains("no claim in this reply"))
    }

    func testSimilarityIsConservative() {
        XCTAssertGreaterThan(ClaimMatcher.similarity("The tests pass", "the tests pass"), 0.9)
        XCTAssertLessThan(ClaimMatcher.similarity("The test suite passes", "The packaging tests pass on Linux"), ClaimMatcher.similarityThreshold)
    }

    // MARK: Chip

    func testChipSummarisesVerdictsWithoutDecidingAnything() {
        let source = ledger(claims: [
            claim("a", .testsPass, .verified, withEvidence: true),
            claim("b", .buildSucceeds, .verified, withEvidence: true),
            claim("c", .lintClean, .refuted),
            claim("The working tree is clean", .gitFact, .unverified, strategy: .observe(.gitFact(.clean)))
        ])
        XCTAssertEqual(LedgerChip.title(for: source), "🔎 2✓ 1✗ 1⚠")
        XCTAssertTrue(LedgerChip.help(for: source).contains("2 verified"))
        XCTAssertEqual(LedgerChip.auditTitle([]), "✓ Reply audited")
        // A reply that agrees with *verified* evidence is not a finding; the
        // count below can only come from the claim the receipt left unverified.
        XCTAssertEqual(LedgerChip.auditTitle(ClaimMatcher.audit(ledger: source, reply: "The tests pass.")), "✓ Reply audited")
        XCTAssertEqual(LedgerChip.auditTitle(ClaimMatcher.audit(ledger: source, reply: "The working tree is clean.")), "❗ 1 repeated")
    }

    func testEmptyLedgerChipIsExplicit() {
        XCTAssertEqual(LedgerChip.title(for: ledger(claims: [])), "🔎 No claims")
    }
}

import XCTest
@testable import RelayCore

/// Extraction is the weakest link in this feature, so these tests focus on what
/// it must refuse to do: invent claims, flip a negation, or stay silent about
/// text it did not cover.
final class ClaimExtractorTests: XCTestCase {

    private func kinds(_ text: String, source: ClaimSource = .draft) -> [ClaimKind] {
        ClaimExtractor.extract(from: text, source: source).claims.map(\.kind)
    }

    private func first(_ text: String, source: ClaimSource = .draft) -> Claim? {
        ClaimExtractor.extract(from: text, source: source).claims.first
    }

    // MARK: Refusals

    func testProposalAndHedgeAreNeverCheckable() {
        let claim = first("We should add a test that passes before merging this module.")
        XCTAssertEqual(claim?.kind, .notFalsifiable)
        guard case .impossible = claim?.strategy else { return XCTFail("A proposal must not be checkable") }
    }

    func testQuestionIsNotAClaim() {
        XCTAssertEqual(first("Does the build succeed on the release branch?")?.kind, .notFalsifiable)
    }

    func testOpinionWordsDoNotBecomeTestClaims() {
        let extraction = ClaimExtractor.extract(from: "I think the tests pass, probably.", source: .draft)
        XCTAssertEqual(extraction.claims.map(\.kind), [.notFalsifiable])
    }

    func testAmbiguousPresenceAndAbsenceYieldsNoFileClaim() {
        // "there is no doubt ... exists" must not become a checkable assertion.
        XCTAssertNotEqual(first("There is no doubt that Sources/Core/Reality.swift exists.")?.kind, .fileExists)
    }

    func testShortFragmentsAndEmptyTextProduceNothing() {
        XCTAssertTrue(ClaimExtractor.extract(from: "", source: .draft).isEmpty)
        XCTAssertTrue(ClaimExtractor.extract(from: "Ship it\nOk\n# Request", source: .draft).isEmpty)
    }

    func testStatementWithoutConcreteTokenIsCountedAsUnmatched() {
        let extraction = ClaimExtractor.extract(from: "The assistant handles this differently than expected.", source: .draft)
        XCTAssertTrue(extraction.claims.isEmpty)
        XCTAssertEqual(extraction.unmatchedSentenceCount, 1)
    }

    // MARK: Command claims

    func testTestsPassRequiresDeclaredTestCommand() {
        let claim = first("The test suite passes locally.")
        XCTAssertEqual(claim?.kind, .testsPass)
        XCTAssertEqual(claim?.polarity, .affirmative)
        XCTAssertEqual(claim?.strategy, .execute(.tests))
    }

    func testNegatedTestClaimKeepsItsPolarity() {
        let claim = first("The tests do not pass on this machine.")
        XCTAssertEqual(claim?.kind, .testsPass)
        XCTAssertEqual(claim?.polarity, .negative)
    }

    func testNegativePhrasingOfAFailingBuildIsNegative() {
        let claim = first("The build fails after the refactor.")
        XCTAssertEqual(claim?.kind, .buildSucceeds)
        XCTAssertEqual(claim?.polarity, .negative)
    }

    func testDoubleNegativeIsNotTreatedAsAFailure() {
        let claim = first("The build is not broken after all.")
        XCTAssertEqual(claim?.kind, .buildSucceeds)
        XCTAssertEqual(claim?.polarity, .affirmative)
    }

    func testLintClaimUsesLintCommand() {
        XCTAssertEqual(first("Eslint is clean now.")?.strategy, .execute(.lint))
    }

    func testMixedSentenceYieldsBothClaims() {
        let extraction = ClaimExtractor.extract(from: "The tests pass but the build fails.", source: .draft)
        let kinds = Set(extraction.claims.map(\.kind))
        XCTAssertTrue(kinds.contains(.testsPass))
        XCTAssertTrue(kinds.contains(.buildSucceeds))
    }

    // MARK: Observation claims

    func testFileExistenceClaimCarriesThePathVerbatim() {
        guard case .observe(.fileExists(let path)) = first("There is a file at Sources/Core/Reality.swift that covers this.")?.strategy else {
            return XCTFail("Expected a file probe")
        }
        XCTAssertEqual(path, "Sources/Core/Reality.swift")
    }

    func testAbsentFileClaimIsNegativePolarity() {
        let claim = first("package.json does not exist in this project.")
        XCTAssertEqual(claim?.kind, .fileExists)
        XCTAssertEqual(claim?.polarity, .negative)
    }

    func testLineClaimCapturesPathLineAndQuotedNeedle() {
        guard case .observe(.lineContains(let path, let line, let needle)) = first("Sources/Core/Reality.swift line 42 contains `RealityForkPlan`.")?.strategy else {
            return XCTFail("Expected a line probe")
        }
        XCTAssertEqual(path, "Sources/Core/Reality.swift")
        XCTAssertEqual(line, 42)
        XCTAssertEqual(needle, "RealityForkPlan")
    }

    func testSymbolDefinitionClaimCapturesTheName() {
        guard case .observe(.symbolDefined(let name)) = first("func fork is defined in the forker class.")?.strategy else {
            return XCTFail("Expected a symbol probe")
        }
        XCTAssertEqual(name, "fork")
    }

    func testReferenceCountClaims() {
        guard case .observe(.referenceCount(let name, let expected)) = first("There are no other callers of `scanLedger`.")?.strategy else {
            return XCTFail("Expected a reference probe")
        }
        XCTAssertEqual(name, "scanLedger")
        XCTAssertEqual(expected, .zero)

        guard case .observe(.referenceCount(_, let one)) = first("Only one caller references `scanLedger` today.")?.strategy else {
            return XCTFail("Expected an exact count probe")
        }
        XCTAssertEqual(one, .exactly(1))
    }

    func testReferenceClaimWithoutASymbolIsReportedNotChecked() {
        let claim = first("There are no other callers of the helper these days.")
        XCTAssertEqual(claim?.kind, .referenceCount)
        guard case .impossible = claim?.strategy else { return XCTFail("An unnamed symbol cannot be scanned") }
    }

    func testGitClaims() {
        XCTAssertEqual(first("The working tree is clean.")?.strategy, .observe(.gitFact(.clean)))
        XCTAssertEqual(first("The branch has uncommitted changes.")?.strategy, .observe(.gitFact(.dirty)))
    }

    func testDirtyAndCleanInOneSentenceIsNotAClaim() {
        XCTAssertNotEqual(first("The working tree is clean but has uncommitted changes.")?.kind, .gitFact)
    }

    // MARK: Segmentation and bounds

    func testSentencesAreSplitWithoutBreakingPathsOrVersions() {
        let extraction = ClaimExtractor.extract(from: "Tests pass. The file is at Sources/Core/Reality.swift and the version is 1.0.1.", source: .draft)
        XCTAssertTrue(extraction.claims.contains { $0.text.contains("Sources/Core/Reality.swift") })
        XCTAssertFalse(extraction.claims.contains { $0.text.hasSuffix("Sources/Core/Reality.") })
    }

    func testFencedCodeIsExcludedAndDisclosed() throws {
        let text = """
        The build succeeds here.

        ```bash
        swift build
        swift test
        ```

        Nothing else changed.
        """
        let extraction = ClaimExtractor.extract(from: text, source: .assistantReply)
        XCTAssertTrue(extraction.claims.contains { $0.kind == .buildSucceeds })
        XCTAssertFalse(extraction.claims.contains { $0.text.contains("swift build") })
        XCTAssertEqual(extraction.excludedCodeFenceLines, 4)
    }

    func testMarkdownPrefixesAreStrippedBeforeMatching() {
        let text = "- [x] The test suite passes.\n> 1. The build succeeds."
        let kinds = Set(ClaimExtractor.extract(from: text, source: .draft).claims.map(\.kind))
        XCTAssertTrue(kinds.contains(.testsPass))
        XCTAssertTrue(kinds.contains(.buildSucceeds))
    }

    func testClaimLimitIsReportedRatherThanSilentlyApplied() {
        let text = (1...40).map { "The test suite passes item \($0)." }.joined(separator: "\n")
        let extraction = ClaimExtractor.extract(from: text, source: .draft)
        XCTAssertEqual(extraction.claims.count, LedgerPolicy.maxClaims)
        XCTAssertTrue(extraction.truncated)
        XCTAssertGreaterThan(extraction.unmatchedSentenceCount, 0)
    }

    func testOversizedSourceIsRefusedRatherThanCut() {
        let text = String(repeating: "The test suite passes. ", count: 5_000)
        let extraction = ClaimExtractor.extract(from: text, source: .draft)
        XCTAssertTrue(extraction.oversized)
        XCTAssertTrue(extraction.claims.isEmpty)
        XCTAssertTrue(extraction.truncated)
    }

    func testDuplicateStatementsAreReportedOncePerKind() {
        let extraction = ClaimExtractor.extract(from: "The test suite passes.\nThe test suite passes.", source: .draft)
        XCTAssertEqual(extraction.claims.count, 1)
    }

    // MARK: Display safety and source stamping

    func testControlAndDirectionalCharactersAreStrippedForDisplayOnly() {
        let raw = "The build succeeds\u{202E}\u{0007} now."
        let claim = first(raw)
        XCTAssertEqual(claim?.kind, .buildSucceeds)
        XCTAssertFalse(claim?.display.contains("\u{202E}") ?? true)
        XCTAssertTrue(claim?.text.contains("\u{202E}") ?? false, "The stored text stays verbatim")
    }

    func testSourceIsStampedOnEveryClaim() {
        let extraction = ClaimExtractor.extract(from: "The test suite passes and the build succeeds.", source: .assistantReply)
        XCTAssertFalse(extraction.claims.isEmpty)
        XCTAssertTrue(extraction.claims.allSatisfy { $0.source == .assistantReply })
    }

    func testSanitizerRejectsUnsafeSymbolTokens() {
        XCTAssertNil(ClaimExtractor.sanitizedSymbol("fork`; rm -rf /"))
        XCTAssertNil(ClaimExtractor.sanitizedSymbol("these"))
        XCTAssertEqual(ClaimExtractor.sanitizedSymbol("forkReality"), "forkReality")
    }

    func testSHA256MatchesPublishedVectors() {
        XCTAssertEqual(SHA256Digest.hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Digest.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256Digest.hex(String(repeating: "a", count: 1_000_000)).prefix(16), "cdc76e5c9914fb92")
    }
}

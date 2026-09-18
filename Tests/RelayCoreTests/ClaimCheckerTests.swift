import XCTest
@testable import RelayCore

/// A deterministic double for the file system and Git. No test in this file
/// touches the developer's working tree or runs a real command.
final class FakeClaimSource: ClaimObservationSource {
    var files: [String: Data] = [:]
    var unreadable: Set<String> = []
    var listings: [String: [String]] = [:]
    var snapshot: GitSnapshotRecord?
    var commit: String?

    func fileExists(_ resolvedPath: String) -> Bool { files[resolvedPath] != nil || unreadable.contains(resolvedPath) }
    func fileBytes(_ resolvedPath: String) -> Data? { unreadable.contains(resolvedPath) ? nil : files[resolvedPath] }
    func listFiles(under root: String, limit: Int) -> [String] { Array((listings[root] ?? []).prefix(limit)) }
    func gitSnapshot(at root: String) -> GitSnapshotRecord? { snapshot }
    func currentCommit(at root: String) -> String? { commit }

    func add(_ path: String, _ text: String) { files[path] = Data(text.utf8) }
}

/// Records every command it is asked to run, so a test can prove that no
/// command text was ever synthesized from prose.
final class RecordingExecutor {
    private(set) var commands: [String] = []
    var exitCode: Int32 = 0
    var output = "ok"

    func run(_ command: VerifyCommand, in root: String) -> ActionResult {
        commands.append(command.command)
        let start = Date()
        return ActionResult(actionID: UUID(), output: output, exitCode: exitCode, startedAt: start,
                            finishedAt: start.addingTimeInterval(2), command: command.command)
    }
}

final class ClaimCheckerTests: XCTestCase {

    private let root = "/tmp/claim-fixture-project"

    private func environment(dirty: Bool = false, commit: String = "abc1234def", commands: [VerifyCommand] = [],
                            gitRoot: String? = nil) -> ClaimEnvironment {
        let tree = GitSnapshotRecord(branch: "main", commit: commit, isDirty: dirty,
                                     modifiedCount: dirty ? 2 : 0, stagedCount: 0, untrackedCount: dirty ? 1 : 0)
        return ClaimEnvironment(gitRoot: gitRoot ?? root, commit: commit, tree: tree,
                                verifyCommands: commands, projectID: "hearth")
    }

    private func testCommand(_ command: String = "swift test") -> VerifyCommand {
        VerifyCommand(name: "Suite", kind: .tests, command: command)
    }

    private func claim(_ text: String, kind: ClaimKind, strategy: ClaimCheckStrategy,
                       polarity: ClaimPolarity = .affirmative) -> Claim {
        Claim(text: text, kind: kind, polarity: polarity, source: .draft, strategy: strategy)
    }

    // MARK: Path guard

    func testPathGuardRefusesEverythingOutsideTheRoot() {
        XCTAssertNil(ClaimPathGuard.resolve("/etc/passwd", root: root))
        XCTAssertNil(ClaimPathGuard.resolve("~/notes.swift", root: root))
        XCTAssertNil(ClaimPathGuard.resolve("../secrets.swift", root: root))
        XCTAssertNil(ClaimPathGuard.resolve("a/../../b.swift", root: root))
        XCTAssertNil(ClaimPathGuard.resolve("-rf", root: root))
        XCTAssertNil(ClaimPathGuard.resolve("https://example.com/a.swift", root: root))
        XCTAssertNil(ClaimPathGuard.resolve("", root: root))
        XCTAssertEqual(ClaimPathGuard.resolve("Sources/Core/Reality.swift", root: root),
                       root + "/Sources/Core/Reality.swift")
    }

    // MARK: Probes and verdicts

    func testFileProbeVerdicts() {
        let source = FakeClaimSource()
        source.add(root + "/package.json", "{}")
        let observer = ClaimObserver(source: source)
        let checker = ClaimChecker(observer: observer)

        let present = claim("package.json exists", kind: .fileExists, strategy: .observe(.fileExists(path: "package.json")))
        let verified = checker.apply(observer.probe(.fileExists(path: "package.json"), root: root), to: present, baseCommit: "abc")
        XCTAssertEqual(verified.verdict, .verified)
        XCTAssertEqual(verified.evidence?.contentHash.count, 64)

        let absent = claim("missing.json exists", kind: .fileExists, strategy: .observe(.fileExists(path: "missing.json")))
        XCTAssertEqual(checker.apply(observer.probe(.fileExists(path: "missing.json"), root: root), to: absent, baseCommit: "abc").verdict, .refuted)

        let negative = claim("missing.json does not exist", kind: .fileExists,
                             strategy: .observe(.fileExists(path: "missing.json")), polarity: .negative)
        XCTAssertEqual(checker.apply(observer.probe(.fileExists(path: "missing.json"), root: root), to: negative, baseCommit: "abc").verdict, .verified)
    }

    func testUnreadableExistingFileIsStillVerifiedButKeepsAFingerprint() {
        let source = FakeClaimSource()
        source.unreadable.insert(root + "/big.bin")
        let observer = ClaimObserver(source: source)
        let probe = observer.probe(.fileExists(path: "big.bin"), root: root)
        guard case .fileExistence(_, let exists, let hash) = probe else { return XCTFail("Expected an existence result") }
        XCTAssertTrue(exists)
        XCTAssertEqual(hash.count, 64)
    }

    func testUnavailableProbeCanNeverBeVerified() {
        let observer = ClaimObserver(source: FakeClaimSource())
        let checker = ClaimChecker(observer: observer)
        let outside = claim("/etc/passwd exists", kind: .fileExists, strategy: .observe(.fileExists(path: "/etc/passwd")))
        let result = checker.apply(observer.probe(.fileExists(path: "/etc/passwd"), root: root), to: outside, baseCommit: "abc")
        XCTAssertEqual(result.verdict, .unverified)
        XCTAssertNil(result.evidence)

        let noGit = claim("the working tree is clean", kind: .gitFact, strategy: .observe(.gitFact(.clean)))
        let gitResult = checker.apply(observer.probe(.gitFact(.clean), root: root), to: noGit, baseCommit: "abc")
        XCTAssertEqual(gitResult.verdict, .unverified)
        XCTAssertNil(gitResult.evidence)
    }

    func testLineProbeVerdicts() {
        let source = FakeClaimSource()
        source.add(root + "/Notes.md", "line one\nline two\n\nline four")
        let observer = ClaimObserver(source: source)
        let checker = ClaimChecker(observer: observer)

        func check(line: Int, needle: String) -> Claim {
            let claim = self.claim("Notes.md line \(line) contains \(needle)", kind: .lineContains,
                                   strategy: .observe(.lineContains(path: "Notes.md", line: line, needle: needle)))
            return checker.apply(observer.probe(.lineContains(path: "Notes.md", line: line, needle: needle), root: root),
                                 to: claim, baseCommit: "abc")
        }

        XCTAssertEqual(check(line: 2, needle: "two").verdict, .verified)
        XCTAssertEqual(check(line: 2, needle: "four").verdict, .refuted)
        XCTAssertEqual(check(line: 9, needle: "two").verdict, .refuted)
        XCTAssertTrue(check(line: 9, needle: "two").note.contains("no line 9"))
        // No needle asserted means only "this line has content" is checked.
        XCTAssertEqual(check(line: 1, needle: "").verdict, .verified)
        XCTAssertEqual(check(line: 3, needle: "").verdict, .refuted)
    }

    func testMissingFileLineClaimIsRefutedWithTheFileName() {
        let observer = ClaimObserver(source: FakeClaimSource())
        let checker = ClaimChecker(observer: observer)
        let claim = self.claim("Gone.swift line 3 contains x", kind: .lineContains,
                               strategy: .observe(.lineContains(path: "Gone.swift", line: 3, needle: "x")))
        let result = checker.apply(observer.probe(.lineContains(path: "Gone.swift", line: 3, needle: "x"), root: root),
                                  to: claim, baseCommit: "abc")
        XCTAssertEqual(result.verdict, .refuted)
        XCTAssertTrue(result.note.contains("Gone.swift"))
    }

    func testSymbolScanDistinguishesDefinitionsFromReferences() {
        let source = FakeClaimSource()
        source.add(root + "/A.swift", "func scanLedger() {}\n")
        source.add(root + "/B.swift", "scanLedger()\nscanLedger()\n")
        source.listings[root] = [root + "/A.swift", root + "/B.swift"]
        let observer = ClaimObserver(source: source)
        let checker = ClaimChecker(observer: observer)

        let defined = claim("scanLedger is defined", kind: .symbolDefined, strategy: .observe(.symbolDefined(name: "scanLedger")))
        let definedResult = checker.apply(observer.probe(.symbolDefined(name: "scanLedger"), root: root), to: defined, baseCommit: "abc")
        XCTAssertEqual(definedResult.verdict, .verified)
        XCTAssertTrue(definedResult.note.contains("A.swift:1"))

        let zero = claim("no other callers of scanLedger", kind: .referenceCount,
                         strategy: .observe(.referenceCount(name: "scanLedger", expected: .zero)))
        XCTAssertEqual(checker.apply(observer.probe(.referenceCount(name: "scanLedger", expected: .zero), root: root), to: zero, baseCommit: "abc").verdict, .refuted)

        let exactlyTwo = claim("exactly two callers of scanLedger", kind: .referenceCount,
                               strategy: .observe(.referenceCount(name: "scanLedger", expected: .exactly(2))))
        XCTAssertEqual(checker.apply(observer.probe(.referenceCount(name: "scanLedger", expected: .exactly(2)), root: root), to: exactlyTwo, baseCommit: "abc").verdict, .verified)

        let absent = claim("ghostSymbol is defined", kind: .symbolDefined, strategy: .observe(.symbolDefined(name: "ghostSymbol")))
        XCTAssertEqual(checker.apply(observer.probe(.symbolDefined(name: "ghostSymbol"), root: root), to: absent, baseCommit: "abc").verdict, .refuted)
    }

    func testBoundedScanProvesPresenceButNeverAbsence() {
        let source = FakeClaimSource()
        let noisy = (0..<60).map { _ in "ghostSymbol()" }.joined(separator: "\n")
        source.add(root + "/Noisy.swift", noisy)
        source.listings[root] = [root + "/Noisy.swift"]
        let observer = ClaimObserver(source: source)
        let checker = ClaimChecker(observer: observer)

        // 60 occurrences exceed the 50-hit bound, so the scan is truncated.
        let absent = claim("ghostSymbol is defined", kind: .symbolDefined, strategy: .observe(.symbolDefined(name: "ghostSymbol")))
        let result = checker.apply(observer.probe(.symbolDefined(name: "ghostSymbol"), root: root), to: absent, baseCommit: "abc")
        XCTAssertEqual(result.verdict, .unverified)
        XCTAssertTrue(result.note.contains("bound"))

        let zero = claim("no other callers of ghostSymbol", kind: .referenceCount,
                         strategy: .observe(.referenceCount(name: "ghostSymbol", expected: .zero)))
        XCTAssertEqual(checker.apply(observer.probe(.referenceCount(name: "ghostSymbol", expected: .zero), root: root), to: zero, baseCommit: "abc").verdict, .unverified)
    }

    func testGitFactVerdicts() {
        let source = FakeClaimSource()
        source.snapshot = GitSnapshotRecord(branch: "main", commit: "abc", isDirty: true, modifiedCount: 2, stagedCount: 0, untrackedCount: 1)
        let observer = ClaimObserver(source: source)
        let checker = ClaimChecker(observer: observer)

        let clean = claim("the working tree is clean", kind: .gitFact, strategy: .observe(.gitFact(.clean)))
        let result = checker.apply(observer.probe(.gitFact(.clean), root: root), to: clean, baseCommit: "abc")
        XCTAssertEqual(result.verdict, .refuted)
        XCTAssertTrue(result.note.contains("dirty"))

        let dirty = claim("the tree is dirty", kind: .gitFact, strategy: .observe(.gitFact(.dirty)))
        XCTAssertEqual(checker.apply(observer.probe(.gitFact(.dirty), root: root), to: dirty, baseCommit: "abc").verdict, .verified)
    }

    // MARK: Planning

    func testCleanTreeRunsInPlace() {
        let checker = ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
        let ledger = try! makeLedger("The test suite passes.", environment: environment(commands: [testCommand()]))
        let tasks = checker.plan(ledger, environment: environment(commands: [testCommand()]))
        XCTAssertEqual(tasks.count, 1)
        guard case .execute(let id, let command, let rehearsal) = tasks[0] else { return XCTFail("Expected an execution task") }
        XCTAssertEqual(id, ledger.claims[0].id)
        XCTAssertEqual(command.command, "swift test")
        XCTAssertNil(rehearsal, "A clean tree is checked in place")
    }

    func testDirtyTreeIsRehearsedOutsideTheSourceCheckout() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let commands = [testCommand()]
        let environment = environment(dirty: true, commands: commands, gitRoot: sandbox.path)
        let checker = ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
        let ledger = try makeLedger("The test suite passes.", environment: environment)
        let tasks = checker.plan(ledger, environment: environment)

        guard case .execute(_, _, let rehearsal) = tasks[0], let plan = rehearsal else {
            return XCTFail("A dirty tree must be isolated in a rehearsal worktree")
        }
        XCTAssertFalse(plan.destinationRoot.hasPrefix(sandbox.path + "/"), "The rehearsal must not live inside the checkout")
        XCTAssertEqual(plan.branchName, RehearsalWorktree.branchName(ledgerID: ledger.id))
        XCTAssertEqual(plan.baseCommit, environment.commit)
        XCTAssertTrue(plan.destinationRoot.contains("relaybar-rehearsal-"))
    }

    func testMissingDeclarationRefusesToExecute() throws {
        let checker = ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
        let environment = environment()
        let ledger = try makeLedger("The test suite passes.", environment: environment)
        guard case .skip(_, let verdict, let note) = checker.plan(ledger, environment: environment)[0] else {
            return XCTFail("Expected a refusal")
        }
        XCTAssertEqual(verdict, .unverified)
        XCTAssertTrue(note.contains("No test command is declared"))
    }

    func testAmbiguousDeclarationsRefuseToChoose() throws {
        let commands = [testCommand("swift test"), VerifyCommand(name: "Alt suite", kind: .tests, command: "swift test --filter alt")]
        let environment = environment(commands: commands)
        let ledger = try makeLedger("The test suite passes.", environment: environment)
        guard case .skip(_, .unverified, let note) = ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
            .plan(ledger, environment: environment)[0] else { return XCTFail("Expected a refusal") }
        XCTAssertTrue(note.contains("Two or more"))
    }

    func testExecutionWithoutACommitIsRefused() throws {
        let commands = [testCommand()]
        let environment = environment(commit: "", commands: commands)
        let ledger = try makeLedger("The test suite passes.", environment: environment)
        guard case .skip(_, .unverified, let note) = ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
            .plan(ledger, environment: environment)[0] else { return XCTFail("Expected a refusal") }
        XCTAssertTrue(note.contains("current commit"))
    }

    func testProposalIsPlannedAsNotCheckable() throws {
        let environment = environment()
        let ledger = try makeLedger("We should probably rewrite this later.", environment: environment)
        guard case .skip(_, let verdict, _) = ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
            .plan(ledger, environment: environment)[0] else { return XCTFail("Expected a skip") }
        XCTAssertEqual(verdict, .notCheckable)
    }

    // MARK: Execution results

    func testCommandResultsRespectPolarity() throws {
        let checker = ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
        let command = testCommand()
        let affirmative = claim("the tests pass", kind: .testsPass, strategy: .execute(.tests))
        let negative = claim("the tests do not pass", kind: .testsPass, strategy: .execute(.tests), polarity: .negative)
        let start = Date()

        func result(_ code: Int32) -> ActionResult {
            ActionResult(actionID: UUID(), output: "out", exitCode: code, startedAt: start,
                         finishedAt: start.addingTimeInterval(1), command: command.command)
        }

        XCTAssertEqual(checker.apply(result(0), to: affirmative, command: command, baseCommit: "abc", worktree: nil).verdict, .verified)
        XCTAssertEqual(checker.apply(result(1), to: affirmative, command: command, baseCommit: "abc", worktree: nil).verdict, .refuted)
        XCTAssertEqual(checker.apply(result(1), to: negative, command: command, baseCommit: "abc", worktree: nil).verdict, .verified)
        XCTAssertEqual(checker.apply(result(0), to: negative, command: command, baseCommit: "abc", worktree: nil).verdict, .refuted)

        let timedOut = checker.apply(result(-1), to: affirmative, command: command, baseCommit: "abc", worktree: nil)
        XCTAssertEqual(timedOut.verdict, .unverified)
        XCTAssertTrue(timedOut.note.contains("concluded nothing"))
        XCTAssertEqual(timedOut.evidence?.exitCode, -1)

        let rehearsed = checker.apply(result(0), to: affirmative, command: command, baseCommit: "abc", worktree: "/tmp/rehearsal")
        XCTAssertEqual(rehearsed.evidence?.worktreePath, "/tmp/rehearsal")
    }

    func testBoundedExcerptSaysWhenItWasCut() {
        let long = String(repeating: "x", count: 5_000)
        let excerpt = ClaimChecker.boundedExcerpt(long)
        XCTAssertTrue(excerpt.contains("cut at 4096 characters"))
        XCTAssertEqual(ClaimChecker.boundedExcerpt("short"), "short")
    }

    /// The central guarantee of the feature: only declared commands can run,
    /// even when the reviewed text quotes a shell command of its own.
    func testNoCommandIsEverSynthesizedFromProse() throws {
        let declared = testCommand()
        let environment = environment(commands: [declared])
        let checker = ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
        let text = "Run `rm -rf build` first, then the test suite passes and the build succeeds."
        let ledger = try makeLedger(text, environment: environment)
        let executor = RecordingExecutor()

        var current = ledger
        for task in checker.plan(ledger, environment: environment) {
            switch task {
            case .skip: current = checker.applySkip(task, to: current)
            case .observe(let id, let probe):
                guard let claim = current.claim(id: id) else { continue }
                let result = ClaimObserver(source: FakeClaimSource()).probe(probe, root: environment.gitRoot)
                current = checker.replace(current, with: checker.apply(result, to: claim, baseCommit: environment.commit))
            case .execute(let id, let command, _):
                guard let claim = current.claim(id: id) else { continue }
                let result = executor.run(command, in: environment.gitRoot)
                current = checker.replace(current, with: checker.apply(result, to: claim, command: command,
                                                                     baseCommit: environment.commit, worktree: nil))
            }
        }

        XCTAssertFalse(executor.commands.isEmpty, "The declared test command should have run")
        let declaredCommands = Set([declared.command])
        for command in executor.commands {
            XCTAssertTrue(declaredCommands.contains(command), "RelayBar ran an undeclared command: \(command)")
        }
        XCTAssertTrue(current.claims.allSatisfy { $0.kind != .assertion || $0.verdict == .notCheckable })
        XCTAssertEqual(current.summary.refuted, 0)
    }

    // MARK: Staleness and validation

    func testEvidenceGoesStaleWhenTheRepositoryMoves() throws {
        let environment = environment()
        let checker = ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
        var ledger = try makeLedger("The test suite passes.", environment: environment)
        var claim = ledger.claims[0]
        claim.verdict = .verified
        claim.evidence = ClaimEvidence(method: "Ran the declared test command", summary: "exit 0", contentHash: String(repeating: "a", count: 64), baseCommit: environment.commit)
        ledger = checker.replace(ledger, with: claim)
        XCTAssertEqual(ledger.summary.verified, 1)

        let moved = ledger.staled(against: "differentcommit")
        XCTAssertTrue(moved.claims[0].isStale)
        XCTAssertEqual(moved.claims[0].effectiveVerdict, .unverified)
        XCTAssertEqual(moved.summary.stale, 1)
        XCTAssertEqual(moved.summary.verified, 0)
    }

    func testVerifiedClaimWithoutEvidenceIsRejected() {
        var claim = self.claim("the tests pass", kind: .testsPass, strategy: .execute(.tests))
        claim.verdict = .verified
        XCTAssertThrowsError(try claim.validate())
    }

    func testEvidenceRejectsAnInvalidFingerprint() {
        let evidence = ClaimEvidence(method: "scan", summary: "ok", contentHash: "not-a-digest", baseCommit: "abc")
        XCTAssertThrowsError(try evidence.validate())
    }

    func testMakeLedgerRefusesEmptyAndOversizedText() {
        let checker = ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
        let environment = environment()
        XCTAssertThrowsError(try checker.makeLedger(text: "   \n", source: .draft, environment: environment, projectName: "Hearth"))
        let huge = String(repeating: "The test suite passes. ", count: 5_000)
        XCTAssertThrowsError(try checker.makeLedger(text: huge, source: .draft, environment: environment, projectName: "Hearth")) { error in
            XCTAssertEqual(error as? ClaimLedgerError, .oversizedSource)
        }
    }

    func testInitialVerdictsAreUnverifiedOrNotCheckable() throws {
        let environment = environment(commands: [testCommand()])
        let ledger = try ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
            .makeLedger(text: "The test suite passes. We should revisit the layout later.",
                        source: .draft, environment: environment, projectName: "Hearth")
        XCTAssertEqual(ledger.claims.count, 2)
        XCTAssertEqual(ledger.claims[0].verdict, .unverified)
        XCTAssertEqual(ledger.claims[1].verdict, .notCheckable)
        XCTAssertEqual(ledger.summary.verified, 0)
    }

    func testSkipCarriesItsReasonOntoTheLedger() throws {
        let checker = ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
        let environment = environment()
        var ledger = try makeLedger("The test suite passes.", environment: environment)
        let task = checker.plan(ledger, environment: environment)[0]
        ledger = checker.applySkip(task, to: ledger)
        XCTAssertEqual(ledger.claims[0].verdict, .unverified)
        XCTAssertFalse(ledger.claims[0].note.isEmpty)
    }

    // MARK: Storage

    func testLedgerStorageRoundTripKeepsPrivatePermissions() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let store = try LocalStore(directory: sandbox)
        let environment = environment()
        let ledger = try ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
            .makeLedger(text: "The test suite passes.", source: .reference, environment: environment, projectName: "Hearth")

        let url = try store.saveLedger(ledger)
        XCTAssertEqual(try store.loadLedger(from: url), ledger)

        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: store.ledgersURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryPermissions?.intValue, 0o700)
        let filePermissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(filePermissions?.intValue, 0o600)

        XCTAssertEqual(try store.listLedgers().count, 1)
    }

    func testCorruptLedgerFileIsSkippedRatherThanRepaired() throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let store = try LocalStore(directory: sandbox)
        try Data("not json".utf8).write(to: store.ledgersURL.appendingPathComponent("broken.json"))
        XCTAssertTrue(try store.listLedgers().isEmpty)
    }

    private func makeLedger(_ text: String, environment: ClaimEnvironment) throws -> ClaimLedger {
        try ClaimChecker(observer: ClaimObserver(source: FakeClaimSource()))
            .makeLedger(text: text, source: .draft, environment: environment, projectName: "Hearth")
    }
}

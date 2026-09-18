import Cocoa
#if canImport(RelayCore)
import RelayCore
#endif

/// AppKit/pasteboard/Touch Bar checks for the claim ledger. Runnable only on
/// macOS, and deliberately hermetic: it uses a named pasteboard, a synthetic
/// observation source, and never executes a declared command.
///
/// This test proves structure, refusals, and clipboard discipline. It does not
/// prove physical Touch Bar rendering, and it does not run a real verification.
@MainActor
enum ClaimLedgerNativeChecks {

    /// A synthetic project: one committed file, no Git, no real command.
    private final class SelfTestSource: ClaimObservationSource {
        private let root: String
        private let file = "Sources/Core/Sample.swift"
        private let contents: [String: Data]

        init(root: String) {
            self.root = root
            self.contents = [root + "/" + file: Data("func scanLedger() {}\n".utf8)]
        }

        func fileExists(_ resolvedPath: String) -> Bool { contents[resolvedPath] != nil }
        func fileBytes(_ resolvedPath: String) -> Data? { contents[resolvedPath] }
        func listFiles(under root: String, limit: Int) -> [String] { Array(contents.keys.prefix(limit)) }
        func gitSnapshot(at root: String) -> GitSnapshotRecord? {
            GitSnapshotRecord(branch: "main", commit: "abc1234def5678", isDirty: false,
                              modifiedCount: 0, stagedCount: 0, untrackedCount: 0)
        }
        func currentCommit(at root: String) -> String? { "abc1234def5678" }
    }

    static func run() -> Int32 {
        var passed = 0, failed = 0
        func check(_ condition: Bool, _ label: String) {
            if condition { passed += 1; print("PASS: \(label)") }
            else { failed += 1; print("FAIL: \(label)") }
        }

        let board = NSPasteboard(name: NSPasteboard.Name("local.relaybar.ledger-selftest.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let generalChangeCount = NSPasteboard.general.changeCount

        let fixtureRoot = "/tmp/relaybar-ledger-selftest-\(UUID().uuidString)"
        let controller = ClaimLedgerController(projectID: "fixture", projectName: "Synthetic project",
                                               board: board, observationSource: SelfTestSource(root: fixtureRoot))
        defer { controller.stopForTermination() }

        // 1. A review without a project root is refused, not guessed.
        let refusal = controller.review("The test suite passes.", source: .draft, gitRoot: nil)
        check(refusal != nil, "review without a project root is refused")
        check(controller.ledger == nil, "a refused review creates no ledger")

        // 2. A real review builds a ledger, still without checking anything.
        let text = """
        The test suite passes on this machine.
        Sources/Core/Sample.swift exists in the tree.
        We should probably revisit the layout later.
        """
        let reviewError = controller.review(text, source: .reference, gitRoot: fixtureRoot)
        check(reviewError == nil, "review builds a ledger from reviewed text")
        guard let ledger = controller.ledger else {
            print("FAIL: ledger was not created; stopping.")
            return 1
        }
        check(ledger.claims.count == 3, "three claims were recognized (\(ledger.claims.count))")
        check(ledger.claims.allSatisfy { $0.verdict == .unverified || $0.verdict == .notCheckable }, "nothing is settled before Verify")

        // 3. With no declared command, verification refuses to execute and says so.
        check(controller.verifyCommands.isEmpty, "self-test declares no command")
        controller.verify()
        let settled = controller.ledger ?? ledger
        let declaredAbsent = settled.claims.first { $0.kind == .testsPass }
        check(declaredAbsent?.verdict == .unverified, "an execution claim stays UNVERIFIED with no declared command")
        check(declaredAbsent?.note.contains("No test command is declared") == true, "the refusal explains the missing declaration")

        // 4. A local read settles what it can.
        let fileClaim = settled.claims.first { $0.kind == .fileExists }
        check(fileClaim?.verdict == .verified, "an existing file claim is verified from a local read")
        check(fileClaim?.evidence?.contentHash.count == 64, "observed evidence carries a SHA-256 fingerprint")
        check(settled.claims.first { $0.kind == .notFalsifiable }?.verdict == .notCheckable, "a proposal is never checkable")

        // 5. Planning alone would schedule the declared command, without running it.
        if let executionClaim = settled.claims.first(where: { $0.kind == .testsPass }) {
            let environment = ClaimEnvironment(gitRoot: fixtureRoot, commit: "abc1234def5678", tree: settled.treeState,
                                               verifyCommands: [VerifyCommand(name: "Suite", kind: .tests, command: "swift test")],
                                               projectID: "fixture")
            let tasks = ClaimChecker().plan(settled, environment: environment)
            let planned = tasks.first { $0.claimID == executionClaim.id }
            if case .execute(let id, let command, let rehearsal) = planned {
                check(id == executionClaim.id && command.command == "swift test", "planning selects the declared command verbatim")
                check(rehearsal == nil, "a clean tree is planned in place")
            } else {
                check(false, "planning should have scheduled the declared command")
            }
        }

        // 6. The reply audit compares text and re-runs nothing.
        let auditError = controller.audit(reply: "All good — the test suite passes, so I merged it.")
        check(auditError == nil, "auditing a reply succeeds")
        check(controller.findings.contains { $0.relationship == .repeatedUnverified }, "a repeated unverified claim is flagged")
        check(controller.findings.allSatisfy { $0.claimVerdict == .unverified || $0.claimVerdict == .refuted },
              "only unsettled claims can be flagged as repeated")

        // 7. Copying writes exactly one marked text item to the named board.
        controller.copyReceipt()
        let items = board.pasteboardItems ?? []
        check(items.count == 1, "the receipt is exactly one pasteboard item")
        check(board.types?.contains(NSPasteboard.PasteboardType(ContextStackPolicy.ownType)) == true, "the receipt is marked as RelayBar output")
        let receipt = board.string(forType: .string) ?? ""
        check(receipt.contains("COVERAGE"), "the receipt includes its coverage disclosure")
        check(receipt.contains("✅ VERIFIED") || receipt.contains("⚠️ UNVERIFIED"), "the receipt renders verdicts")

        controller.copyAudit()
        check((board.string(forType: .string) ?? "").contains("REPLY AUDIT"), "the audit summary is copyable")

        // 8. Touch Bar structure: a chip on every page, real items, bounded width.
        let driver = TouchBarDriver()
        let chip = controller.chipSlots()
        check(chip.count == 1, "one evidence chip is offered")
        check(chip.first?.title.hasPrefix("🔎") == true || chip.first?.title.hasPrefix("❗") == true, "the chip summarises verdicts")

        var back = false, hidden = false
        let slots = controller.slots() + [.init(key: "ledger-hide", title: "×", help: "Hide", width: 28) { hidden = true }]
        check(!slots.isEmpty, "the Verify page offers controls")
        check(slots.reduce(CGFloat(0)) { $0 + ($1.width ?? 0) } + CGFloat(slots.count - 1) * 8 <= 685,
              "declared widths plus estimated gaps fit the 685pt budget (not hardware measurement)")
        driver.update(chip + slots)
        for slot in chip + slots {
            let item = driver.touchBar(driver.bar, makeItemForIdentifier: NSTouchBarItem.Identifier("local.relaybar.\(slot.key)")) as? NSCustomTouchBarItem
            check(item?.view is NSButton, "construct actual Touch Bar item: \(slot.key)")
        }

        // 9. The panel constructs without being shown or activated.
        let panel = controller.constructPanelForSelfTest()
        check(panel?.contentView != nil && panel?.isVisible == false, "the ledger panel is constructed without being shown")
        check(!back && !hidden, "construction did not trigger navigation or hide actions")

        // 10. Nothing was executed, and the general pasteboard was never touched.
        check(controller.message.isEmpty == false, "the controller always reports a status")
        check(NSPasteboard.general.changeCount == generalChangeCount, "NSPasteboard.general was never read or written")

        print("\n\(passed) native checks passed; \(failed) failed. Named pasteboard and synthetic observation source only. No declared command was executed, and no physical Touch Bar or real repository was verified by this self-test.")
        return failed == 0 ? 0 : 1
    }
}

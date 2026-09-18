import Cocoa
#if canImport(RelayCore)
import RelayCore
#endif

/// Owns the claim ledger in the running app: review, plan, verify, audit, and
/// the single declared-command execution path.
///
/// The controller is the only object in this feature that can change anything,
/// and it only starts commands the user declared. Everything else is a read.
@MainActor
final class ClaimLedgerController: NSObject, NSWindowDelegate {
    private(set) var ledger: ClaimLedger?
    private(set) var findings: [ReplyAuditFinding] = []
    private(set) var message = "No claims reviewed yet."
    var verifyCommands: [VerifyCommand] = []
    var projectID: String
    var projectName: String
    var onChange: (() -> Void)?
    var onReturnToWork: (() -> Void)?
    var onJournal: ((JournalEntryKind) -> Void)?
    var onVerifyCommandsChanged: (([VerifyCommand]) -> Void)?

    private let checker: ClaimChecker
    private let observer: ClaimObserver
    private let runner = ActionRunner()
    private let rehearsal = RehearsalWorktree()
    private let board: NSPasteboard
    private let storeProvider: () -> LocalStore?
    private var queue: [ClaimTask] = []
    private var environment: ClaimEnvironment?
    private var activeTask: (claimID: UUID, command: VerifyCommand, rehearsal: RehearsalWorktreePlan?)?
    private var activeRehearsal: RehearsalWorktreePlan?
    private var keepRehearsal = false

    private var panel: RelayPanel?
    private var rows = NSStackView()
    private var summary = label("")
    private var footer = label("", secondary: true)
    private var verifyButton: ActionButton?
    private var receiptButton: ActionButton?
    private var previewText: NSTextView?

    init(
        projectID: String,
        projectName: String,
        board: NSPasteboard = .general,
        observationSource: ClaimObservationSource = SystemClaimObservationSource(),
        storeProvider: @escaping () -> LocalStore? = { nil }
    ) {
        self.projectID = projectID
        self.projectName = projectName
        self.board = board
        self.observer = ClaimObserver(source: observationSource)
        self.checker = ClaimChecker(observer: self.observer)
        self.storeProvider = storeProvider
        super.init()
        runner.onComplete = { [weak self] result in
            DispatchQueue.main.async { self?.finished(result) }
        }
    }

    // MARK: Project and lifecycle

    func syncProject(id: String, name: String) {
        guard id != projectID else { projectName = name; return }
        projectID = id
        projectName = name
        // A ledger describes one project's revision. Switching projects does not
        // re-target it; the previous review stays saved and unchanged.
        ledger = nil
        findings = []
        message = "Project changed. Review text again to build a ledger for \(name)."
        refresh()
    }

    func stopForTermination() {
        runner.cancel()
        queue.removeAll()
        if let plan = activeRehearsal {
            // Never leave a rehearsal worktree behind on quit.
            try? rehearsal.discard(plan)
            activeRehearsal = nil
        }
        panel?.orderOut(nil)
    }

    // MARK: Review

    /// Builds a ledger from explicit text. Returns nil on success, or a message
    /// describing why nothing was reviewed.
    @discardableResult
    func review(_ text: String, source: ClaimSource, gitRoot: String?) -> String? {
        let root = gitRoot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !root.isEmpty else {
            let error = ClaimLedgerError.noProjectRoot.localizedDescription
            message = error
            refresh()
            return error
        }
        guard let environment = observer.environment(root: root, verifyCommands: verifyCommands, projectID: projectID) else {
            let error = "RelayBar could not read Git state at \(root), so claims cannot be checked against a known revision. Nothing was executed."
            message = error
            refresh()
            return error
        }
        do {
            let ledger = try checker.makeLedger(text: text, source: source, environment: environment, projectName: projectName)
            self.environment = environment
            self.ledger = ledger
            self.findings = []
            keepRehearsal = false
            message = ledger.claims.isEmpty
                ? "No statement was recognized as a checkable claim. \(ledger.unmatchedSentenceCount) statement(s) were not covered."
                : "Reviewed \(ledger.claims.count) claim(s). Nothing has been checked or executed yet."
            if let store = storeProvider() { _ = try? store.saveLedger(ledger) }
            onJournal?(.claimLedgerCreated(claimCount: ledger.claims.count, verified: 0, refuted: 0, unverified: 0))
            refresh()
            return nil
        } catch {
            message = error.localizedDescription
            refresh()
            return error.localizedDescription
        }
    }

    /// Compares a pasted reply against the saved ledger. This never re-checks
    /// anything: it is a text comparison against an existing receipt.
    @discardableResult
    func audit(reply: String) -> String? {
        guard let ledger = ledger else {
            let error = "Review and save a ledger before auditing a reply."
            message = error
            refresh()
            return error
        }
        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let error = "There is no text on the clipboard to audit."
            message = error
            refresh()
            return error
        }
        findings = ClaimMatcher.audit(ledger: ledger, reply: reply)
        message = findings.isEmpty
            ? "Audited the reply. No statement repeated something the receipt left unverified or refuted."
            : "Audited the reply: \(findings.count) statement(s) are not supported by this receipt."
        for finding in findings {
            onJournal?(.claimRepeated(text: LedgerPolicy.displayText(finding.replySentence, limit: 120)))
        }
        refresh()
        return nil
    }

    func auditClipboardReply() {
        let text = board.types?.contains(.string) == true ? (board.string(forType: .string) ?? "") : ""
        _ = audit(reply: text)
    }

    // MARK: Verification

    /// Settles every included claim that RelayBar is allowed to settle. Local
    /// reads happen immediately; declared commands run one at a time, and a
    /// dirty tree is rehearsed in a throwaway worktree.
    func verify() {
        guard let ledger = ledger else { message = "Review some text first."; return }
        guard !runner.isRunning else { message = "A declared command is already running. RelayBar runs one at a time."; refresh(); return }
        guard let environment = observer.environment(root: ledger.gitRoot, verifyCommands: verifyCommands, projectID: projectID) else {
            message = "RelayBar could not read Git state at \(ledger.gitRoot). Nothing was checked."
            refresh()
            return
        }
        self.environment = environment

        let tasks = checker.plan(ledger, environment: environment)
        queue.removeAll()
        var observations = 0
        var refusals = 0
        var current = ledger
        for task in tasks {
            switch task {
            case .skip:
                current = checker.applySkip(task, to: current)
                refusals += 1
            case .observe(let id, let probe):
                guard let claim = current.claim(id: id) else { continue }
                let result = observer.probe(probe, root: environment.gitRoot)
                let updated = checker.apply(result, to: claim, baseCommit: environment.commit)
                current = checker.replace(current, with: updated)
                observations += 1
                if updated.verdict == .verified || updated.verdict == .refuted {
                    record(updated, method: updated.evidence?.method ?? "Local read")
                }
            case .execute:
                queue.append(task)
            }
        }
        current = checker.staled(current, environment: environment)
        self.ledger = current
        message = "Checked \(observations) claim(s) from local reads. \(refusals) could not be checked. \(queue.count) declared command(s) queued."
        persist()
        refresh()
        startNextExecution()
    }

    /// Applies a single settled verdict to the saved ledger and journals it.
    private func record(_ claim: Claim, method: String) {
        onJournal?(.claimVerified(text: LedgerPolicy.displayText(claim.display, limit: 120),
                                  verdict: claim.verdict.rawValue, method: method))
    }

    private func startNextExecution() {
        guard !runner.isRunning, let environment = environment else { return }
        guard !queue.isEmpty else {
            if activeRehearsal == nil { updateMessageAfterExecutions() }
            return
        }
        let task = queue.removeFirst()
        guard case .execute(let id, let command, let rehearsalPlan) = task,
              let ledger = ledger, let claim = ledger.claim(id: id) else { return }

        var runRoot = environment.gitRoot
        if let plan = rehearsalPlan {
            do {
                try rehearsal.create(plan)
                activeRehearsal = plan
                runRoot = plan.destinationRoot
                onJournal?(.rehearsalRan(command: command.command, exitCode: 0, worktree: plan.destinationRoot))
                message = "Rehearsing `\(command.command)` in a throwaway worktree. Your working tree is untouched."
            } catch {
                let skipped = ClaimTask.skip(claimID: id, verdict: .unverified, note: error.localizedDescription)
                self.ledger = checker.applySkip(skipped, to: ledger)
                message = error.localizedDescription
                persist(); refresh()
                startNextExecution()
                return
            }
        }

        activeTask = (claimID: id, command: command, rehearsal: rehearsalPlan)
        // The declared command is reused verbatim; only its working directory
        // changes when the run is isolated in a rehearsal worktree.
        let action = QuickAction(name: command.name, command: command.command,
                                 workingDirectory: rehearsalPlan == nil ? command.workingDirectory : .custom(runRoot),
                                 showOutput: false)
        runner.run(action, projectRoot: runRoot, timeout: command.maxSeconds)
        message = "Running the declared \(command.kind.declaredNoun) `\(command.command)` \(rehearsalPlan == nil ? "at the project root" : "in the rehearsal worktree"). One command at a time."
        refresh()
    }

    private func finished(_ result: ActionResult) {
        defer { activeTask = nil; startNextExecution() }
        guard let active = activeTask, let ledger = ledger, let claim = ledger.claim(id: active.claimID) else { return }
        let worktree = active.rehearsal?.destinationRoot
        let updated = checker.apply(result, to: claim, command: active.command, baseCommit: ledger.baseCommit, worktree: worktree)
        self.ledger = checker.replace(ledger, with: updated)
        record(updated, method: updated.evidence?.method ?? "Declared command")
        cleanupRehearsal()
        persist()
        refresh()
    }

    private func cleanupRehearsal() {
        guard let plan = activeRehearsal else { return }
        activeRehearsal = nil
        guard !keepRehearsal else {
            message = "Kept the rehearsal worktree at \(plan.destinationRoot). Nothing in your working tree was changed."
            return
        }
        do {
            try rehearsal.discard(plan)
            message = "Removed the rehearsal worktree. Your working tree was not changed by it."
        } catch {
            message = error.localizedDescription
        }
    }

    private func updateMessageAfterExecutions() {
        guard let ledger = ledger else { return }
        let summary = ledger.summary
        message = "Settled \(summary.verified) verified, \(summary.refuted) refuted, \(summary.unverified) unverified, \(summary.notCheckable) not checkable."
        persist()
        refresh()
    }

    private func persist() {
        guard let ledger = ledger, let store = storeProvider() else { return }
        _ = try? store.saveLedger(ledger)
    }

    // MARK: Output

    func copyReceipt() {
        guard let ledger = ledger else { message = "Nothing to copy yet."; refresh(); return }
        let text = ClaimReceiptRenderer.receipt(ledger)
        guard write(text) else { message = "The receipt could not be written to the clipboard. Nothing was copied."; refresh(); return }
        message = "Receipt copied (\(ledger.summary.verified) verified, \(ledger.summary.unverified) unverified). Paste it yourself; RelayBar never pastes or sends."
        refresh()
    }

    func copyAudit() {
        guard let ledger = ledger else { message = "Nothing to copy yet."; refresh(); return }
        let text = ClaimReceiptRenderer.auditSummary(findings, ledger: ledger)
        guard write(text) else { message = "The audit could not be written to the clipboard. Nothing was copied."; refresh(); return }
        message = "Reply audit copied. Paste it yourself; RelayBar never pastes or sends."
        refresh()
    }

    /// Reuses the Context Stack's own-output marker on purpose, so RelayBar's
    /// receipt is never collected back into the user's stack as if they had
    /// copied source material.
    private func write(_ text: String) -> Bool {
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string),
              item.setData(Data(), forType: NSPasteboard.PasteboardType(ContextStackPolicy.ownType)),
              item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.source")) else { return false }
        board.clearContents()
        return board.writeObjects([item])
    }

    func toggle(_ id: UUID) {
        guard let ledger = ledger, let claim = ledger.claim(id: id) else { return }
        var updated = claim
        updated.included.toggle()
        self.ledger = checker.replace(ledger, with: updated)
        persist()
        refresh()
    }

    func setKeepRehearsal(_ keep: Bool) { keepRehearsal = keep }

    // MARK: Touch Bar

    /// The evidence chip. One slot, so it can sit beside the fixed shell
    /// controls on every page without crowding a page's own buttons.
    func chipSlots() -> [TouchBarDriver.Slot] {
        guard let ledger = ledger else { return [] }
        let title = findings.isEmpty ? LedgerChip.title(for: ledger) : LedgerChip.auditTitle(findings)
        var help = LedgerChip.help(for: ledger)
        if !findings.isEmpty { help += " The reply audit found \(findings.count) statement(s) this receipt does not support." }
        return [.init(key: "ledger-chip", title: title, help: help, width: 108) { [weak self] in self?.showLedger() }]
    }

    /// Page-local controls for the Verify page.
    func slots() -> [TouchBarDriver.Slot] {
        guard let ledger = ledger else {
            return [.init(key: "ledger-empty", title: "Review the draft first", help: "Compose or capture text, then review it as claims.", isEnabled: false, width: 190, action: {})]
        }
        let checkable = ledger.claims.contains { $0.included && $0.verdict != .notCheckable }
        return [
            .init(key: "ledger-verify", title: "Verify", help: "Check every included claim from local reads and your declared commands. One command at a time; a dirty tree is rehearsed.", isEnabled: checkable && !runner.isRunning, width: 56) { [weak self] in self?.verify() },
            .init(key: "ledger-audit", title: "Audit reply", help: "Compare the clipboard text against this receipt. RelayBar re-checks nothing.", width: 82) { [weak self] in self?.auditClipboardReply() },
            .init(key: "ledger-receipt", title: "Receipt", help: "Copy the receipt with every verdict and its coverage disclosure.", width: 62) { [weak self] in self?.copyReceipt() },
            .init(key: "ledger-open", title: "Ledger ›", help: LedgerChip.help(for: ledger), width: 66) { [weak self] in self?.showLedger() }
        ]
    }

    // MARK: Panel

    func showLedger() {
        if panel == nil { buildPanel() }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel?.orderOut(nil)
        onReturnToWork?()
        return false
    }

    func constructPanelForSelfTest() -> NSPanel? {
        if panel == nil { buildPanel() }
        refresh()
        return panel
    }

    private func buildPanel() {
        let window = RelayPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
                                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "RelayBar · Claim Ledger"
        window.minSize = NSSize(width: 820, height: 620)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.onEscape = { [weak self] in
            self?.panel?.orderOut(nil)
            self?.onReturnToWork?()
        }
        panel = window
        window.center()

        let outer = NSScrollView()
        outer.hasVerticalScroller = true
        outer.translatesAutoresizingMaskIntoConstraints = false
        if let content = window.contentView {
            content.addSubview(outer)
            NSLayoutConstraint.activate([
                outer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                outer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                outer.topAnchor.constraint(equalTo: content.topAnchor),
                outer.bottomAnchor.constraint(equalTo: content.bottomAnchor)
            ])
        }
        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        outer.documentView = document
        document.widthAnchor.constraint(equalTo: outer.contentView.widthAnchor).isActive = true

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18)
        ])
        func full(_ view: NSView) {
            root.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }

        full(label("CLAIM LEDGER", size: 22, weight: .bold))
        full(summary)
        full(label("Every verdict below is either an observation RelayBar made locally or a declared command it ran. A receipt describes one commit; it never claims more than that.", secondary: true))

        verifyButton = ActionButton("Verify included claims") { [weak self] in self?.verify() }
        receiptButton = ActionButton("Copy receipt") { [weak self] in self?.copyReceipt() }
        let keep = NSButton(checkboxWithTitle: "Keep the rehearsal worktree", target: nil, action: nil)
        keep.state = .off
        keep.toolTip = "Leave the throwaway worktree in place after the declared command finishes, so you can inspect it. Your own working tree is never changed either way."
        keep.target = self
        keep.action = #selector(toggleKeepRehearsal(_:))

        full(row([verifyButton!, receiptButton!,
                  ActionButton("Audit clipboard reply") { [weak self] in self?.auditClipboardReply() },
                  ActionButton("Copy audit") { [weak self] in self?.copyAudit() },
                  ActionButton("Declare verify command…") { [weak self] in self?.presentVerifyCommandEditor() },
                  keep]))
        full(label("Nothing is pasted or sent. RelayBar only writes text to the clipboard when you ask.", size: 11, secondary: true))

        let listScroll = NSScrollView()
        listScroll.hasVerticalScroller = true
        listScroll.borderType = .bezelBorder
        listScroll.heightAnchor.constraint(equalToConstant: 380).isActive = true
        let listDocument = FlippedDocumentView()
        listDocument.translatesAutoresizingMaskIntoConstraints = false
        listScroll.documentView = listDocument
        listDocument.widthAnchor.constraint(equalTo: listScroll.contentView.widthAnchor).isActive = true
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        rows.translatesAutoresizingMaskIntoConstraints = false
        listDocument.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: listDocument.leadingAnchor, constant: 8),
            rows.trailingAnchor.constraint(equalTo: listDocument.trailingAnchor, constant: -8),
            rows.topAnchor.constraint(equalTo: listDocument.topAnchor, constant: 8),
            rows.bottomAnchor.constraint(equalTo: listDocument.bottomAnchor, constant: -8)
        ])
        full(listScroll)

        full(label("PREVIEW · read-only · nothing has been sent", size: 11, weight: .semibold))
        let (previewScroll, preview) = textEditor(height: 150, mono: true)
        preview.isEditable = false
        preview.setAccessibilityLabel("Complete receipt preview")
        previewText = preview
        full(previewScroll)
        full(row([ActionButton("Refresh preview") { [weak self] in self?.refresh() },
                  ActionButton("Back to work") { [weak self] in
                      self?.panel?.orderOut(nil)
                      self?.onReturnToWork?()
                  },
                  footer]))
    }

    @objc private func toggleKeepRehearsal(_ sender: NSButton) {
        keepRehearsal = sender.state == .on
    }

    private func refresh() {
        onChange?()
        guard let window = panel, window.contentView != nil else { return }
        let ledger = self.ledger
        footer.stringValue = message

        guard let ledger = ledger else {
            summary.stringValue = "No ledger for \(projectName) yet."
            verifyButton?.isEnabled = false
            receiptButton?.isEnabled = false
            for view in rows.arrangedSubviews { rows.removeArrangedSubview(view); view.removeFromSuperview() }
            rows.addArrangedSubview(label("Compose or capture text, then choose Verify claims. RelayBar reads only this project and runs only the commands you declare."))
            setPreview("")
            return
        }

        let stats = ledger.summary
        summary.stringValue = "\(ledger.projectName) · \(stats.total) claim(s) · \(stats.verified) verified · \(stats.refuted) refuted · \(stats.unverified) unverified · \(stats.notCheckable) not checkable · \(stats.stale) stale · base \(ledger.baseCommit.prefix(8))"
        verifyButton?.isEnabled = !runner.isRunning
        receiptButton?.isEnabled = true

        for view in rows.arrangedSubviews { rows.removeArrangedSubview(view); view.removeFromSuperview() }
        if ledger.claims.isEmpty {
            rows.addArrangedSubview(label("No statement in the reviewed text was recognized as a claim. \(ledger.unmatchedSentenceCount) statement(s) were not covered by this ledger."))
        }
        for claim in ledger.claims {
            rows.addArrangedSubview(claimRow(claim))
        }
        if !findings.isEmpty {
            rows.addArrangedSubview(label("REPLY AUDIT — \(findings.count) statement(s) this receipt does not support", size: 12, weight: .semibold))
            for finding in findings {
                rows.addArrangedSubview(label("\(finding.relationship.mark) \(finding.relationship.title) — \(finding.relationship.explanation) \(LedgerPolicy.displayText(finding.replySentence, limit: 160))", size: 11, secondary: true))
            }
        }
        setPreview(ClaimReceiptRenderer.receipt(ledger))
    }

    private func setPreview(_ text: String) { previewText?.string = text }

    private func claimRow(_ claim: Claim) -> NSView {
        let verdict = claim.effectiveVerdict
        let toggle = ActionButton(claim.included ? "✓" : "—", help: claim.included
            ? "Exclude this claim from the receipt"
            : "Include this claim in the receipt") { [weak self] in self?.toggle(claim.id) }
        let title = label("\(verdict.mark) \(verdict.title)\(claim.isStale ? " (STALE)" : "") · \(claim.kind.title)",
                          size: 12, weight: .semibold)
        title.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let text = label(LedgerPolicy.displayText(claim.display, limit: 260), size: 12)
        let note = label(claim.note.isEmpty ? claim.strategy.title : claim.note, size: 11, secondary: true)
        var lines: [NSView] = [row([toggle, title, text])]
        if let evidence = claim.evidence {
            let detail = "method \(evidence.method) · sha256 \(String(evidence.contentHash.prefix(12)))"
                + (evidence.exitCode.map { " · exit \($0)" } ?? "")
                + (evidence.worktreePath.map { " · worktree \($0)" } ?? "")
            lines.append(label(detail, size: 10, secondary: true))
            if !evidence.excerpt.isEmpty {
                lines.append(label(LedgerPolicy.displayText(evidence.excerpt, limit: 200), size: 10, secondary: true))
            }
        }
        lines.append(note)
        let stack = NSStackView(views: lines)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }

    // MARK: Declared commands

    /// The only place a verify command can be created. It is validated with the
    /// same limits as a Quick Action and stored in the app configuration.
    func presentVerifyCommandEditor() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Declare a local verification command"
        alert.informativeText = "RelayBar settles test, build, and lint claims by running the command you declare here, verbatim. It never derives a command from prose. On a clean working tree the command runs at the project root; with uncommitted changes it runs in a throwaway worktree so your work is untouched."

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        nameField.placeholderString = "Name, e.g. Swift test suite"
        let commandField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        commandField.placeholderString = "Command, e.g. swift test"
        let kindPicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 25), pullsDown: false)
        kindPicker.addItems(withTitles: VerifyCommandKind.allCases.map(\.title))
        let accessory = NSStackView(views: [nameField, kindPicker, commandField])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 6
        accessory.frame = NSRect(x: 0, y: 0, width: 320, height: 90)
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Remove all")

        let response = alert.runModal()
        if response == .alertThirdButtonReturn {
            verifyCommands.removeAll()
            onVerifyCommandsChanged?(verifyCommands)
            message = "Removed every declared verify command. Claims that need a command now report UNVERIFIED."
            refresh()
            return
        }
        guard response == .alertFirstButtonReturn else { return }
        let kind = VerifyCommandKind.allCases[max(0, min(kindPicker.indexOfSelectedItem, VerifyCommandKind.allCases.count - 1))]
        let command = VerifyCommand(name: nameField.stringValue.isEmpty ? "\(kind.title) check" : nameField.stringValue,
                                    kind: kind, command: commandField.stringValue)
        do {
            try command.validate()
        } catch {
            message = error.localizedDescription
            refresh()
            return
        }
        verifyCommands.removeAll { $0.kind == kind && $0.projectID.isEmpty }
        verifyCommands.append(command)
        onVerifyCommandsChanged?(verifyCommands)
        message = "Declared \(kind.title.lowercased()) command `\(command.command)`. It runs only when you verify a matching claim."
        refresh()
    }
}

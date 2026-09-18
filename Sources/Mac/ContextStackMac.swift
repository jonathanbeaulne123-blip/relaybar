import Cocoa

/// NSPasteboard is touched on main only. A named pasteboard can be injected into
/// native self-tests; production is the sole caller using .general.
final class ContextStackMacPasteboard: ContextStackPasteboard {
    let board: NSPasteboard
    init(_ board: NSPasteboard) { self.board = board }
    var changeCount: Int { board.changeCount }
    var typeNames: [String] { (board.types ?? []).map(\.rawValue) }
    var itemCount: Int { board.pasteboardItems?.count ?? 0 }
    func readPlainText() -> String? {
        if (board.types ?? []).contains(.string) { return board.string(forType: .string) }
        return board.string(forType: .URL)
    }
    func writePlainText(_ text: String) -> Bool {
        // Prepare one complete item BEFORE clearing. The own marker and text are
        // published in the same write, preventing the collector recording itself.
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string),
              item.setData(Data(), forType: NSPasteboard.PasteboardType(ContextStackPolicy.ownType)),
              item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.source")) else { return false }
        board.clearContents()
        return board.writeObjects([item])
    }
}

@MainActor
final class ContextStackController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private let workspace: ContextStackWorkspace
    var session: ContextStackSession { workspace.current }
    var onChange: (() -> Void)?
    var onReturnToWork: (() -> Void)?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var consentedThisLaunch = false
    private var review: RelayPanel?
    private var clipList = NSStackView()
    private var summary = label("")
    private var feedback = label("", secondary: true)
    private var preview: NSTextView?
    private var manualInput: NSTextView?
    private var packetButton: ActionButton?
    private var selectedID: UUID?
    private var presentedProject = ""
    private var manualDrafts: [String: String] = [:]
    private var copyPreviewButton: ActionButton?
    private var previewIsPacket = true

    init(projectID: String, projectName: String, board: NSPasteboard = .general) {
        workspace = ContextStackWorkspace(pasteboard: ContextStackMacPasteboard(board), projectID: projectID, projectName: projectName)
        super.init()
        // No timer, type query, or content read is started at launch.
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.pause("Collection paused for sleep, display sleep, or session change.") }
            })
        }
    }
    func stopForTermination() {
        stopTimer(); workspace.clearAll(); manualDrafts.removeAll()
        preview?.string = ""; manualInput?.string = ""
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
    func syncProject(id: String, name: String) {
        let priorID = session.stack.projectID, priorName = session.stack.projectName
        if priorID != id { saveManualDraft(); stopTimer() }
        guard workspace.activate(projectID: id, projectName: name) else {
            pause("Could not switch stack: project limit or invalid identifier."); return
        }
        if priorID != id || priorName != session.stack.projectName {
            selectedID = nil; previewIsPacket = true
            if priorID != id { manualInput?.string = manualDrafts[id] ?? "" }
            changed()
        }
    }
    func pause(_ message: String = "Paused. Your stack is still here.") {
        session.pause(message); stopTimer(); changed()
    }
    func toggleCollection() {
        if session.collecting { pause(); return }
        if !consentedThisLaunch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert(); alert.messageText = "Collect copied text into a Context Stack?"
            alert.informativeText = "For up to 15 minutes, RelayBar checks for NEW text copies from any app and keeps up to 20 passages in memory for this project. Text is not saved to disk or sent anywhere by this feature. The current clipboard is not imported when you start.\n\nKnown private/temporary clipboard markers and some obvious secret patterns are skipped, but unmarked passwords or private text may still be collected. Do not copy secrets while collecting. Copy handoff, Pause, sleep, project changes, and quitting stop collection.\n\nmacOS may ask for clipboard access. RelayBar does not change or bypass that permission. You can use Paste clip or manually paste into Review instead."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Start collecting")
            guard alert.runModal() == .alertSecondButtonReturn else { onReturnToWork?(); return }
            consentedThisLaunch = true
        }
        if session.start(now: ProcessInfo.processInfo.systemUptime) {
            startTimer(); review?.orderOut(nil); onReturnToWork?()
        }
        changed()
    }
    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
    private func tick() {
        let front = NSWorkspace.shared.frontmostApplication
        if session.poll(now: ProcessInfo.processInfo.systemUptime, appBundle: front?.bundleIdentifier ?? "", appName: front?.localizedName ?? "Unknown app") { changed() }
        if !session.collecting { stopTimer() }
    }
    func pasteClip() { session.pasteClip(); stopTimer(); changed() }
    func copyClip(_ id: UUID) { _ = session.copyClip(id); changed() }
    func copyPacket(expected: UUID) {
        _ = session.copyPacket(expectedRevision: expected)
        if !session.collecting { stopTimer() }; changed()
    }
    func clearCurrent() {
        guard !session.stack.clips.isEmpty || !(manualInput?.string ?? "").isEmpty || manualDrafts[session.stack.projectID] != nil else { pause(); return }
        pause(); NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Clear \(session.stack.projectName)'s Context Stack?"
        alert.informativeText = "This removes this project's collected clips and manual-input draft from RelayBar's memory. The system clipboard, other project stacks, screenshots, project briefs, and saved checkpoints are unchanged."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Clear stack")
        if alert.runModal() == .alertSecondButtonReturn {
            session.clear(); manualDrafts.removeValue(forKey: session.stack.projectID)
            manualInput?.string = ""; selectedID = nil; previewIsPacket = true; changed()
        }
    }
    func showReview() {
        pause("Reviewing the stack. Collection paused so the handoff stays stable.")
        if review == nil { buildReview() }
        refreshReview(); onChange?(); NSApp.activate(ignoringOtherApps: true); review?.makeKeyAndOrderFront(nil)
    }
    func bindTouchBar(_ bar: NSTouchBar) {
        review?.touchBar = bar; preview?.touchBar = bar; manualInput?.touchBar = bar
    }
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard textView === manualInput, let replacement = replacementString else { return true }
        guard let range = Range(affectedCharRange, in: textView.string) else { return false }
        let proposed = textView.string.replacingCharacters(in: range, with: replacement)
        guard proposed.utf8.count <= ContextStackPolicy.maxClipBytes else {
            feedback.stringValue = "Manual input is limited to 64 KiB. Paste a smaller passage; nothing was truncated."
            return false
        }
        return true
    }
    private func hideReview() { saveManualDraft(); review?.orderOut(nil); onReturnToWork?() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hideReview(); return false }
    private func saveManualDraft() {
        guard let input = manualInput, !presentedProject.isEmpty else { return }
        // The input editor is not a clipboard history; bound what we retain when
        // changing projects. No truncation is silently presented as a full clip.
        if input.string.utf8.count <= ContextStackPolicy.maxClipBytes { manualDrafts[presentedProject] = input.string }
        else { manualDrafts[presentedProject] = "" }
    }
    private func changed() { refreshReview(); onChange?() }

    /// Fits within ~610 points including conservative inter-item spacing.
    /// Buttons refer to immutable clip IDs/revisions, never a moving array index.
    func slots(back: @escaping () -> Void, hide: @escaping () -> Void) -> [TouchBarDriver.Slot] {
        let snapshot = session.stack
        var slots: [TouchBarDriver.Slot] = [
            .init(key: "stack-back", title: "Tools", help: "Return to this app's controls; collection can continue", width: 46, action: back),
            .init(key: "stack-collect", title: session.collecting ? "Ⅱ Pause" : "● Collect", help: session.collecting ? "Pause clipboard collection" : "Explicitly collect new text copies for up to 15 minutes", width: 76) { [weak self] in self?.toggleCollection() }
        ]
        let recent = Array(snapshot.clips.suffix(3))
        for index in 0..<3 {
            if recent.indices.contains(index) {
                let clip = recent[index]
                let ordinal = (snapshot.clips.firstIndex(where: { $0.id == clip.id }) ?? 0) + 1
                let title = session.copiedID == clip.id ? "✓ Copied" : "\(ordinal) \(String(clip.title.prefix(11)))"
                slots.append(.init(key: "stack-clip-\(clip.id.uuidString)", title: title,
                    help: "Copy excerpt \(ordinal) exactly: \(clip.title). \(clip.observedApp). \(clip.byteCount) bytes.", width: 94) { [weak self] in self?.copyClip(clip.id) })
            } else {
                slots.append(.init(key: "stack-empty-\(index)", title: "—", help: "Copy a passage while Collect is on", isEnabled: false, width: 94, action: {}))
            }
        }
        slots.append(.init(key: "stack-pack-\(snapshot.revision.uuidString)", title: "Pack \(snapshot.included.count)",
            help: "Copy all included excerpts as one ordered handoff, then pause. Does not paste or send.", isEnabled: !snapshot.included.isEmpty, width: 64) { [weak self] in self?.copyPacket(expected: snapshot.revision) })
        slots.append(.init(key: "stack-review", title: "Review", help: "Review all 20 clips, include/exclude, reorder, or paste text manually", width: 58) { [weak self] in self?.showReview() })
        slots.append(.init(key: "stack-hide", title: "×", help: "Pause collection and hide RelayBar", width: 28) { [weak self] in self?.pause(); hide() })
        return slots
    }

    /// Native self-test: constructs the real review hierarchy without displaying,
    /// activating, reading General clipboard, or enabling collection.
    func constructReviewForSelfTest() -> NSPanel? {
        if review == nil { buildReview() }; refreshReview(); return review
    }
    private func buildReview() {
        let window = RelayPanel(contentRect: NSRect(x: 0, y: 0, width: 950, height: 810), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "RelayBar · Context Stack"; window.minSize = NSSize(width: 850, height: 700)
        window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false; window.delegate = self
        window.onEscape = { [weak self] in self?.hideReview() }
        review = window; window.center()
        // The complete review scrolls at smaller window sizes; fixed-height
        // editors must never force controls below an unscrollable window edge.
        let outer = NSScrollView(); outer.hasVerticalScroller = true
        outer.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(outer)
        if let content = window.contentView {
            NSLayoutConstraint.activate([outer.leadingAnchor.constraint(equalTo: content.leadingAnchor), outer.trailingAnchor.constraint(equalTo: content.trailingAnchor), outer.topAnchor.constraint(equalTo: content.topAnchor), outer.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        }
        let document = FlippedDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false
        outer.documentView = document
        document.widthAnchor.constraint(equalTo: outer.contentView.widthAnchor).isActive = true
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20), root.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20), root.topAnchor.constraint(equalTo: document.topAnchor, constant: 18), root.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18)])
        func full(_ view: NSView) { root.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        full(label("CONTEXT STACK", size: 22, weight: .bold)); full(summary)
        full(label("Copy pieces once. Hand them over together. Collection is paused while reviewing. App labels are observations, not verified authorship.", secondary: true))
        packetButton = ActionButton("Copy handoff") { [weak self] in
            guard let self = self else { return }; self.copyPacket(expected: self.session.stack.revision)
        }
        full(row([ActionButton("Resume collecting") { [weak self] in self?.toggleCollection() },
                  ActionButton("Paste clip") { [weak self] in self?.pasteClip() }, packetButton!,
                  ActionButton("Preview handoff") { [weak self] in self?.previewIsPacket = true; self?.selectedID = nil; self?.refreshReview() },
                  ActionButton("Clear stack…") { [weak self] in self?.clearCurrent() },
                  ActionButton("Back to work") { [weak self] in self?.hideReview() }]))
        let listScroll = NSScrollView(); listScroll.hasVerticalScroller = true; listScroll.borderType = .bezelBorder
        listScroll.heightAnchor.constraint(equalToConstant: 200).isActive = true
        let doc = FlippedDocumentView(); doc.translatesAutoresizingMaskIntoConstraints = false
        listScroll.documentView = doc
        doc.widthAnchor.constraint(equalTo: listScroll.contentView.widthAnchor).isActive = true
        clipList.orientation = .vertical; clipList.alignment = .leading; clipList.spacing = 6
        clipList.translatesAutoresizingMaskIntoConstraints = false; doc.addSubview(clipList)
        NSLayoutConstraint.activate([clipList.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 8), clipList.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -8), clipList.topAnchor.constraint(equalTo: doc.topAnchor, constant: 8), clipList.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -8)])
        full(listScroll)
        full(label("PREVIEW · READ-ONLY · NOTHING HAS BEEN SENT", size: 11, weight: .semibold))
        let (previewScroll, text) = textEditor(height: 175, mono: true); text.isEditable = false
        text.setAccessibilityLabel("Exact handoff or selected excerpt preview")
        preview = text; full(previewScroll)
        copyPreviewButton = ActionButton("Copy selected excerpt") { [weak self] in
            if let id = self?.selectedID { self?.copyClip(id) }
        }
        full(row([copyPreviewButton!, label("A clip tap copies its exact original text; Pack includes only checked clips.", secondary: true)]))
        full(label("MANUAL INPUT · OPTIONAL · paste here when automatic collection is not available", size: 11, weight: .semibold))
        let (inputScroll, input) = textEditor(height: 72, mono: true); manualInput = input; input.delegate = self
        input.setAccessibilityLabel("Manually paste a passage to add as a clip; 64 KiB maximum")
        full(inputScroll)
        full(row([ActionButton("Add this text") { [weak self] in
            guard let self = self, let input = self.manualInput else { return }
            let oldRevision = self.session.stack.revision
            self.session.addManualText(input.string)
            if self.session.stack.revision != oldRevision { input.string = ""; self.manualDrafts.removeValue(forKey: self.session.stack.projectID) }
            self.changed()
        }, feedback]))
    }
    private func refreshReview() {
        guard review != nil else { return }
        let snapshot = session.stack; presentedProject = snapshot.projectID
        summary.stringValue = "\(snapshot.projectName) · \(snapshot.clips.count)/20 clips · \(snapshot.included.count) included · \(snapshot.totalBytes.formatted())/262,144 UTF-8 bytes · memory only"
        feedback.stringValue = session.message
        packetButton?.title = "Copy handoff (\(snapshot.included.count))"; packetButton?.isEnabled = !snapshot.included.isEmpty
        // Capture the reviewed revision. A queued old click must not copy a changed packet.
        packetButton?.handler = { [weak self] in self?.copyPacket(expected: snapshot.revision) }
        for view in clipList.arrangedSubviews { clipList.removeArrangedSubview(view); view.removeFromSuperview() }
        if snapshot.clips.isEmpty {
            clipList.addArrangedSubview(label("No clips yet. Resume Collect and copy passages, or use Paste clip / manual input."))
        }
        for (index, clip) in snapshot.clips.enumerated() {
            let sessionID = snapshot.projectID
            let toggle = ActionButton(clip.included ? "✓" : "—", help: "\(clip.included ? "Exclude" : "Include") excerpt \(index + 1) in the handoff") { [weak self] in
                guard let self = self, self.session.stack.projectID == sessionID else { return }; self.session.toggle(clip.id); self.changed()
            }
            let title = ActionButton("\(index + 1). \(String(clip.title.prefix(37)))", help: "Preview the complete original excerpt") { [weak self] in
                self?.selectedID = clip.id; self?.previewIsPacket = false; self?.refreshReview()
            }
            title.widthAnchor.constraint(equalToConstant: 295).isActive = true
            let up = ActionButton("↑", help: "Move excerpt earlier") { [weak self] in self?.session.move(clip.id, by: -1); self?.changed() }
            let down = ActionButton("↓", help: "Move excerpt later") { [weak self] in self?.session.move(clip.id, by: 1); self?.changed() }
            up.isEnabled = index > 0; down.isEnabled = index + 1 < snapshot.clips.count
            let delete = ActionButton("Remove", help: "Remove only this clip from memory") { [weak self] in self?.session.remove(clip.id); self?.changed() }
            let info = label("\(clip.byteCount.formatted()) B · \(clip.observedApp)", size: 11, secondary: true)
            let line = row([toggle, title, up, down, delete, info], spacing: 5)
            clipList.addArrangedSubview(line); line.widthAnchor.constraint(equalTo: clipList.widthAnchor).isActive = true
        }
        if let id = selectedID, let clip = snapshot.clips.first(where: { $0.id == id }), !previewIsPacket { preview?.string = clip.text }
        else {
            selectedID = nil; previewIsPacket = true
            preview?.string = (try? snapshot.packet(expectedRevision: snapshot.revision)) ?? "Include at least one excerpt to preview a handoff."
        }
        copyPreviewButton?.isEnabled = selectedID != nil
    }
}

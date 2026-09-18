import Cocoa

@MainActor
final class PinnedChatsController {
    var onChange: (() -> Void)?
    var onSwitchProvider: ((PinProvider) -> Void)?
    private let reader = PinnedChatsAXReader()
    private let queue = DispatchQueue(label: "local.relaybar.pinned-chats", qos: .userInitiated)
    private var active = false
    private var reading = false
    private var opening = false
    private var epoch = UUID()
    private var requestedPID: pid_t = 0
    private var requestedBundle = ""
    private var requestedProvider: PinProvider?
    private var lastRead = Date.distantPast
    private var sample: PinnedChatsAXReader.Sample?
    private var gate = PinNavigationGate()
    private var page = 0
    private(set) var message = "Open ChatGPT or Claude with its Pinned / Starred sidebar visible."
    private(set) var provider: PinProvider?
    private var statusWindow: NSPanel?
    private var statusField: NSTextField?
    private var sleepObserver: NSObjectProtocol?

    init() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.invalidate("Pins cleared for sleep. Return to the assistant to refresh.") }
            }
    }
    func start() { active = true; lastRead = .distantPast; onChange?() }
    func stop() { active = false; invalidate("Pins paused. No sidebar is being read.") }
    func stopForTermination() {
        active = false; epoch = UUID(); gate.clear(); sample = nil
        statusWindow?.close(); statusWindow = nil
        if let observer = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        sleepObserver = nil
        queue.async { [reader] in reader.forget() }
    }
    private func setMessage(_ value: String) {
        guard message != value else { return }
        message = value; statusField?.stringValue = statusText; onChange?()
    }
    private func invalidate(_ text: String) {
        epoch = UUID(); gate.clear(); sample = nil; page = 0; opening = false
        provider = nil; requestedPID = 0; requestedBundle = ""; requestedProvider = nil
        queue.async { [reader] in reader.forget() }
        message = text; statusField?.stringValue = statusText; onChange?()
    }
    func update(front: NSRunningApplication?, nativeProvider: PinProvider?, force: Bool = false) {
        guard active else { return }
        guard let app = front, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !app.isTerminated, let bundle = app.bundleIdentifier,
              nativeProvider != nil || PinnedChatsAXReader.browsers.contains(bundle) else {
            if sample != nil || requestedPID != 0 { invalidate("Return to ChatGPT or Claude to use its pinned chats.") }
            return
        }
        let changed = requestedPID != app.processIdentifier || requestedBundle != bundle || requestedProvider != nativeProvider
        if changed {
            invalidate("Reading the active assistant’s pinned-chat sidebar…")
            requestedPID = app.processIdentifier; requestedBundle = bundle; requestedProvider = nativeProvider
            lastRead = .distantPast
        }
        guard !reading, !opening, force || Date().timeIntervalSince(lastRead) >= 2 else { return }
        reading = true; lastRead = Date()
        let request = PinnedChatsAXReader.Request(pid: app.processIdentifier, bundle: bundle, nativeProvider: nativeProvider)
        let expectedEpoch = epoch
        queue.async { [weak self, reader] in
            let result = reader.scan(request)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.reading = false
                guard self.active, !self.opening, self.epoch == expectedEpoch,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == request.pid else { return }
                self.publish(result)
            }
        }
    }
    private func publish(_ result: PinnedChatsAXReader.Outcome) {
        switch result {
        case .unavailable(let reason):
            let had = sample != nil
            sample = nil; gate.clear(); provider = nil; page = 0
            if had { onChange?() }
            setMessage(reason)
        case .ready(let newSample):
            let oldGeneration = gate.generation
            sample = newSample; provider = newSample.session.provider
            gate.update(session: newSample.session, chats: newSample.inventory.chats, now: Date.timeIntervalSinceReferenceDate)
            if oldGeneration != gate.generation { page = min(page, PinnedChatPolicy.pageCount(gate.chats.count) - 1) }
            let inventory = newSample.inventory
            let text: String
            if inventory.limited { text = "Sidebar scan reached its limit. Partial results are disabled; collapse unrelated sidebar sections and Refresh." }
            else if inventory.chats.isEmpty {
                text = inventory.recognizedSection
                    ? "No pressable chat rows are exposed in Pinned / Starred. Expand the section and Refresh. This is not proof that your account has no pins."
                    : "Pinned status is not exposed. Open the Pinned / Starred sidebar section and Refresh. Recent chats are not substituted."
            } else {
                text = "\(provider!.title) · \(inventory.chats.count) exposed pinned chat\(inventory.chats.count == 1 ? "" : "s")" +
                    (inventory.ambiguous > 0 ? " · \(inventory.ambiguous) ambiguous entries disabled" : " · tap a title to navigate")
            }
            let changed = text != message || oldGeneration != gate.generation
            message = text; statusField?.stringValue = statusText
            if changed { onChange?() }
        }
    }
    func refresh() { lastRead = .distantPast; setMessage("Refresh requested. Keep the assistant in front with its sidebar open.") }
    func showStatus() {
        if statusWindow == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 330),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "RelayBar · Pinned Chats"; panel.isReleasedWhenClosed = false
            let field = label(statusText, size: 13)
            field.isSelectable = true
            let controls = row([
                ActionButton("Enable Accessibility…") { RBBridge.requestAccessibility() },
                ActionButton("Close") { [weak panel] in panel?.orderOut(nil) }
            ])
            let content = NSStackView(views: [label("Your sidebar, on the Touch Bar", size: 19, weight: .semibold), field, controls])
            content.orientation = .vertical; content.alignment = .leading; content.spacing = 18
            content.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView?.addSubview(content)
            if let view = panel.contentView {
                NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                    content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                    content.topAnchor.constraint(equalTo: view.topAnchor, constant: 24)])
            }
            panel.center(); statusWindow = panel; statusField = field
        }
        statusField?.stringValue = statusText
        // This is a help window, not an automatic navigation or app activation.
        statusWindow?.orderFront(nil)
    }
    private var statusText: String {
        "\(message)\n\nUse Pins with ChatGPT or Claude in front. Open the sidebar and expand Pinned / Starred. Enable RelayBar in System Settings → Privacy & Security → Accessibility. Use RB → Choose ChatGPT / Claude application for a differently named desktop app.\n\nOnly exposed sidebar labels, pin markers, private chat URLs and navigation controls are used. No conversation bodies, clipboard data or credentials are read by this feature. Pins stay in memory. No browser extension is required. Where supported, opening Pins requests the app’s accessibility tree; the app may use more memory until it exits."
    }
    func slots(back: @escaping () -> Void, hide: @escaping () -> Void) -> [TouchBarDriver.Slot] {
        let generation = gate.generation
        let chats = PinnedChatPolicy.page(gate.chats, index: page)
        let pages = PinnedChatPolicy.pageCount(gate.chats.count)
        let current = provider
        var slots: [TouchBarDriver.Slot] = [
            .init(key: "pins-tools", title: "Tools", help: "Leave pinned chats and return to RelayBar tools", width: 46, action: back),
            .init(key: "pins-provider-\(current?.rawValue ?? "none")", title: current.map { "\($0.shortTitle) ⇄" } ?? "Open GPT",
                help: "Open the \((current?.other ?? .chatgpt).title) desktop application; no message is sent", width: 78) { [weak self] in
                    self?.invalidate("Switching assistants; pins will be read from the new foreground sidebar.")
                    self?.onSwitchProvider?(current?.other ?? .chatgpt)
                },
            .init(key: "pins-prev", title: "‹", help: "Previous page of pinned chats", isEnabled: pages > 1 && !opening, width: 28) { [weak self] in
                guard let self = self else { return }; self.page = (self.page + pages - 1) % pages; self.onChange?()
            }
        ]
        if chats.isEmpty {
            slots.append(.init(key: "pins-help", title: "Pins setup / status", help: message, width: 318) { [weak self] in self?.showStatus() })
        } else {
            for (offset, chat) in chats.enumerated() {
                let ordinal = page * PinnedChatPolicy.pageSize + offset + 1
                let title = "\(chat.selected ? "✓" : String(ordinal)) \(String(chat.title.prefix(15)))"
                slots.append(.init(key: "pin-\(generation.uuidString)-\(chat.token)", title: title,
                    help: "\(ordinal). \(chat.title) · \(chat.enabled ? "Open this pinned conversation" : "Unavailable or ambiguous; open it in the sidebar")",
                    isEnabled: chat.enabled && !opening, width: 102) { [weak self] in
                        self?.navigate(token: chat.token, generation: generation)
                    })
            }
        }
        slots.append(.init(key: "pins-next", title: "\(page+1)/\(pages) ›", help: "Next page of pinned chats", isEnabled: pages > 1 && !opening, width: 46) { [weak self] in
            guard let self = self else { return }; self.page = (self.page + 1) % pages; self.onChange?()
        })
        slots.append(.init(key: "pins-refresh", title: opening ? "…" : "↻", help: "Refresh pinned-chat sidebar · " + message, isEnabled: !opening, width: 34) { [weak self] in self?.refresh() })
        slots.append(.init(key: "hide", title: "×", help: "Hide RelayBar and disable cross-app Touch Bar", width: 28, action: hide))
        return slots
    }
    private func navigate(token: String, generation: UUID) {
        guard active, !opening, generation == gate.generation, let old = sample,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == old.session.pid,
              let ticket = gate.ticket(token: token, now: Date.timeIntervalSinceReferenceDate) else {
            refresh(); return
        }
        opening = true; onChange?()
        let expectedEpoch = epoch
        let request = PinnedChatsAXReader.Request(pid: old.session.pid, bundle: old.session.bundle, nativeProvider: requestedProvider)
        queue.async { [weak self, reader] in
            let outcome = reader.scan(request)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.active, self.epoch == expectedEpoch else { return }
                self.opening = false
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == old.session.pid,
                      case .ready(let fresh) = outcome,
                      self.gate.consume(ticket, liveSession: fresh.session, liveChats: fresh.inventory.chats,
                                        now: Date.timeIntervalSinceReferenceDate) else {
                    self.gate.clear(); self.sample = nil; self.lastRead = .distantPast
                    self.setMessage("Pins or active window changed. Nothing was opened. Refresh and choose the chat again.")
                    self.onChange?(); return
                }
                let failure = PinnedChatsAXReader.press(ticket.chat, in: fresh, expected: old)
                self.gate.clear(); self.sample = nil; self.lastRead = .distantPast
                self.setMessage(failure ?? "Navigation requested for ‘\(ticket.chat.title)’. Check the app; refreshing its sidebar next.")
                // The request's success is not falsely reported as a loaded chat.
                // Delayed presses never retry, even after an AX timeout.
                self.onChange?()
            }
        }
    }
}

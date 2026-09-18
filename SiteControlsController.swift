import Cocoa

/// Your Sites: resolves the user's rule for the frontmost app or page and runs
/// exactly one, explicitly chosen effect.
///
/// Boundaries that this controller enforces:
/// - A rule is re-resolved immediately before any effect runs. If the frontmost
///   app or page changed while a confirmation sat on the strip, the effect is
///   refused instead of firing into the wrong target.
/// - Input injection requires Accessibility trust and is refused otherwise,
///   with a status message rather than silence.
/// - A pending confirmation expires; an old ticket can never be replayed.
/// - Nothing here reads page content, cells, chat text or files.
@MainActor
public final class SiteControlsController {
    public struct Pending: Equatable {
        public var ruleID: String
        public var buttonID: String
        public var label: String
        public var createdAt: Double
    }

    /// The label shown on the strip before an effect runs.
    public private(set) var pending: Pending?

    public private(set) var detection: SiteDetection = .none
    public private(set) var page = 0
    /// A one-use ticket for each accepted tap, mirroring the app's other
    /// confirmation paths.
    public private(set) var ticket = UUID()

    public var rules: [SiteRule] = []
    /// How long a confirmation stays valid. Long enough to read, short enough
    /// that the underlying page has not moved on.
    public static let confirmationSeconds: Double = 20
    /// Applied to a raw selection request. The reader is owned by AppMain.
    public var selectionProvider: () -> String = { "" }
    public var currentTarget: () -> SiteTarget = { SiteTarget() }

    public var onStatus: ((String) -> Void)?

    // Injected effects that need app state the controller deliberately does not own.
    public var onRelay: ((RelayPage) -> Void)?
    public var onPrompt: ((PromptAction) -> Void)?
    public var onQuickAction: ((UUID) -> Void)?
    public var onPluginCommand: ((String, String) -> Void)?

    public init() {}

    // MARK: - Resolution

    public var matchedRule: SiteRule? {
        guard case .matched(let match) = detection else { return nil }
        return rules.first(where: { $0.id == match.ruleID })
    }

    public var matchedButtons: [SiteButton] { matchedRule?.buttons ?? [] }

    public var status: String { detection.status }

    /// Re-resolves the matched rule for the current target. Returns true when
    /// the visible site changed, so the caller can rebuild the strip.
    @discardableResult
    public func refresh(target: SiteTarget? = nil) -> Bool {
        let previous = detection
        detection = SiteRuleMatcher.detect(target: target ?? currentTarget(), rules: rules)
        let changed = previous != detection
        if changed { page = 0 }
        if let pending = pending, pending.ruleID != detection.ruleID { clearPending() }
        return changed
    }

    public func invalidate() {
        detection = .none
        page = 0
        clearPending()
    }

    public var overflowButtons: [SiteButton] { SiteControlsPolicy.overflowButtons(matchedButtons) }

    public var buttonsForCurrentPage: [SiteButton] {
        SiteControlsPolicy.page(overflowButtons, index: page)
    }

    public func nextPage() {
        let pages = SiteControlsPolicy.pageCount(overflowButtons.count)
        page = (page + 1) % pages
        advanceTicket()
    }

    private func advanceTicket() { ticket = UUID() }

    /// True when the site currently offers a group page worth opening.
    public var hasOverflow: Bool { !overflowButtons.isEmpty }

    // MARK: - Explicit request

    public func request(_ button: SiteButton, ruleID: String) {
        guard case .matched(let match) = detection, match.ruleID == ruleID else {
            onStatus?("This page changed before the tap. Open the site again and choose the button once more.")
            return
        }
        guard matchesCurrentTarget(buttonID: button.id, ruleID: ruleID) != nil else {
            onStatus?("This page changed before the tap; nothing was run.")
            return
        }
        if button.requiresConfirmation {
            let summary = confirmationLabel(for: button)
            pending = Pending(ruleID: ruleID, buttonID: button.id, label: summary,
                              createdAt: ProcessInfo.processInfo.systemUptime)
            advanceTicket()
            onStatus?("Confirm “\(summary)”. Nothing has run yet.")
            return
        }
        clearPending()
        execute(button, ruleID: ruleID)
    }

    public func confirmPending() {
        guard let pending = pending else { return }
        let age = ProcessInfo.processInfo.systemUptime - pending.createdAt
        guard age <= Self.confirmationSeconds else {
            clearPending()
            onStatus?("That confirmation expired after \(Int(Self.confirmationSeconds)) seconds. Choose the button again.")
            return
        }
        guard case .matched(let match) = detection, match.ruleID == pending.ruleID,
              let button = matchedButtons.first(where: { $0.id == pending.buttonID }) else {
            clearPending()
            onStatus?("The page changed while confirming. Nothing was run.")
            return
        }
        clearPending()
        execute(button, ruleID: pending.ruleID)
    }

    public func cancelPending() {
        guard pending != nil else { return }
        clearPending()
        onStatus?("Cancelled without running anything.")
    }

    private func clearPending() { pending = nil }

    /// The text shown on the confirmation button. It names the resolved target
    /// so a mistaken template cannot fire blindly.
    public func confirmationLabel(for button: SiteButton) -> String {
        let title = SiteControlsPolicy.displayTitle(button)
        switch button.effect {
        case .keystroke(let key, let modifiers):
            let combo = (modifiers.map { $0.lowercased() } + [key.lowercased()]).joined(separator: "+")
            return "\(title) → \(combo)"
        case .quickAction(let id):
            return "\(title) → shell action \(id.uuidString.prefix(8))"
        case .pluginCommand(let plugin, let command):
            return "\(title) → \(plugin):\(command)"
        case .openURL(let template):
            return "\(title) → \(rendered(template) ?? "invalid URL")"
        case .copyTemplate(let text):
            return "\(title) → copies \(min(text.count, 999)) characters"
        case .prompt(let action):
            return "\(title) → \(action.title) draft"
        case .relay(let page):
            return "\(title) → \(page.title)"
        }
    }

    // MARK: - Effect execution

    private func execute(_ button: SiteButton, ruleID: String) {
        // Fresh target check immediately before any effect.
        guard let rule = matchesCurrentTarget(buttonID: button.id, ruleID: ruleID) else {
            onStatus?("The page or application changed; \(SiteControlsPolicy.displayTitle(button)) was not run.")
            return
        }
        switch button.effect {
        case .keystroke(let key, let modifiers):
            guard RBBridge.accessibilityTrusted() else {
                onStatus?("Key presses need Accessibility approval. Use RB → Settings → Native controls to enable it; nothing was sent.")
                return
            }
            guard let code = SiteControlsPolicy.keysAndCodes[key.lowercased()] else {
                onStatus?("The key “\(key)” is not on RelayBar's allowlist; nothing was sent.")
                return
            }
            let frontmost = NSWorkspace.shared.frontmostApplication
            guard frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier else {
                onStatus?("RelayBar is frontmost; the key press was not sent.")
                return
            }
            postKey(code: code, modifiers: modifiers)
            onStatus?("Sent \(modifiers.map { $0.lowercased() }.joined(separator: "+"))\(modifiers.isEmpty ? "" : "+")\(key.lowercased()) to \(frontmost?.localizedName ?? "the frontmost app").")
        case .openURL(let template):
            guard let rendered = rendered(template), let url = validated(urlString: rendered) else {
                onStatus?("The URL for \(SiteControlsPolicy.displayTitle(button)) is not a plain https address, so nothing was opened.")
                return
            }
            if NSWorkspace.shared.open(url) {
                onStatus?("Opened \(url.host ?? "the link") for \(rule.name).")
            } else {
                onStatus?("macOS refused to open that link.")
            }
        case .copyTemplate(let template):
            let text = rendered(template) ?? template
            guard !text.isEmpty else {
                onStatus?("Nothing to copy: the template rendered empty.")
                return
            }
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(text, forType: .string) {
                onStatus?("Copied \(text.count) characters for \(rule.name). RelayBar never pastes or sends them.")
            } else {
                onStatus?("The clipboard could not be written.")
            }
        case .quickAction(let id):
            onQuickAction?(id)
        case .pluginCommand(let plugin, let command):
            onPluginCommand?(plugin, command)
        case .prompt(let action):
            onPrompt?(action)
        case .relay(let destination):
            onRelay?(destination)
        }
    }

    private func rendered(_ template: String) -> String? {
        let target = currentTarget()
        let context = SiteTemplateContext(url: target.url, title: target.title,
                                          selection: selectionProvider(), bundleID: target.bundleID)
        guard let text = try? SiteTemplate.render(template, context: context) else { return nil }
        return text
    }

    /// Only a plain https URL with no credentials can be opened.
    private func validated(urlString: String) -> URL? {
        guard let components = URLComponents(string: urlString),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              let host = components.host, !host.isEmpty else { return nil }
        return components.url
    }

    private func postKey(code: UInt16, modifiers: [String]) {
        var flags: CGEventFlags = []
        for modifier in modifiers.map({ $0.lowercased() }) {
            switch modifier {
            case "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option": flags.insert(.maskAlternate)
            case "control": flags.insert(.maskControl)
            default: break
            }
        }
        // One down/up pair. Never retried after either event is posted.
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
           let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) {
            down.flags = flags; up.flags = flags
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Re-resolves the rule for the live target and returns it only when the
    /// same rule and button are still the correct answer.
    private func matchesCurrentTarget(buttonID: String, ruleID: String) -> SiteRule? {
        let fresh = SiteRuleMatcher.detect(target: currentTarget(), rules: rules)
        guard case .matched(let match) = fresh, match.ruleID == ruleID,
              let rule = rules.first(where: { $0.id == ruleID && $0.enabled }),
              rule.buttons.contains(where: { $0.id == buttonID }) else { return nil }
        return rule
    }
}

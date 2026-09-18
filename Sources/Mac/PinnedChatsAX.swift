import Cocoa
import ApplicationServices

/// Thread-confined native reader. All discovery is metadata-only and restricted
/// to the focused window of the explicitly chosen assistant or approved browser.
/// AXValue is read ONLY for static text inside a recognized sidebar, never for
/// document/composer/secure fields. No input injection, URL launching or sockets.
final class PinnedChatsAXReader {
    struct Request {
        var pid: pid_t
        var bundle: String
        var nativeProvider: PinProvider?
    }
    struct Sample {
        var session: PinSession
        var inventory: PinInventory
        var elements: [String: AXUIElement]
        var window: AXUIElement
        var documentRoot: AXUIElement
        var sidebar: AXUIElement
        var documentURL: String
    }
    enum Outcome {
        case ready(Sample)
        case unavailable(String)
    }
    static let browsers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "org.chromium.Chromium", "org.mozilla.firefox", "company.thebrowser.Browser"]
    private var prior: [CFHashCode: [(AXUIElement, String)]] = [:]
    private var current: [String: AXUIElement] = [:]
    private var deadline = Date.distantPast
    private var visited = 0
    private var limited = false
    private var seen = Set<String>()
    private var preparedApp = ""

    // Electron documents AXManualAccessibility for third-party assistive tools.
    // Request only after Pins was opened and macOS permission was granted. This
    // does not change browser preferences or disable other assistive tools.
    private func prepareAccessibility(_ application: AXUIElement, request: Request) {
        let key = "\(request.pid)|\(request.bundle)"
        guard preparedApp != key else { return }
        preparedApp = key
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(application, "AXManualAccessibility" as CFString, &settable) == .success, settable.boolValue {
            _ = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.08)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func string(_ element: AXUIElement, _ name: String, limit: Int = 1024) -> String {
        guard let value = attribute(element, name) else { return "" }
        if CFGetTypeID(value) == CFStringGetTypeID() {
            let text = value as! String
            return text.count <= limit ? text : ""
        }
        if CFGetTypeID(value) == CFURLGetTypeID() {
            let text = (value as! URL).absoluteString
            return text.count <= limit ? text : ""
        }
        return ""
    }
    static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(parent, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func bool(_ element: AXUIElement, _ name: String, default fallback: Bool = false) -> Bool {
        guard let value = attribute(element, name) else { return fallback }
        return (value as? NSNumber)?.boolValue ?? fallback
    }
    static func actions(_ element: AXUIElement) -> [String] {
        AXUIElementSetMessagingTimeout(element, 0.08)
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }
    private func isForeground(_ pid: pid_t) -> Bool {
        guard let app = Self.element(AXUIElementCreateSystemWide(), "AXFocusedApplication") else { return false }
        var focusedPID: pid_t = 0
        return AXUIElementGetPid(app, &focusedPID) == .success && focusedPID == pid
    }
    private func token(_ element: AXUIElement) -> String {
        if let pair = prior[CFHash(element)]?.first(where: { CFEqual($0.0, element) }) {
            current[pair.1] = element; return pair.1
        }
        if let pair = current.first(where: { CFEqual($0.value, element) }) { return pair.key }
        let key = UUID().uuidString; current[key] = element; return key
    }
    private func budget(_ depth: Int) -> Bool {
        guard Date() < deadline, visited < PinnedChatPolicy.maximumNodes, depth <= PinnedChatPolicy.maximumDepth else {
            limited = true; return false
        }
        visited += 1; return true
    }
    private func children(_ element: AXUIElement) -> [AXUIElement] {
        guard Date() < deadline else { limited = true; return [] }
        AXUIElementSetMessagingTimeout(element, 0.08)
        var count: CFIndex = 0
        let countResult = AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count)
        guard countResult == .success else {
            if countResult != .attributeUnsupported && countResult != .noValue { limited = true }
            return []
        }
        guard count > 0 else { return [] }
        let maximum = min(250, PinnedChatPolicy.maximumNodes - visited)
        guard maximum > 0 else { limited = true; return [] }
        if count > maximum { limited = true }
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, min(count, maximum), &values) == .success else { limited = true; return [] }
        guard let elements = values as? [AXUIElement] else { limited = true; return [] }; return elements
    }
    private func webAreas(_ node: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard budget(depth), !Self.bool(node, "AXHidden") else { return [] }
        let role = Self.string(node, "AXRole")
        if role == "AXWebArea" { return [node] }
        guard !["AXTextArea", "AXTextField", "AXSecureTextField", "AXStaticText", "AXButton", "AXLink", "AXMenuBar", "AXToolbar", "AXSheet", "AXDialog"].contains(role) else { return [] }
        var found: [AXUIElement] = []
        for child in children(node) {
            found += webAreas(child, depth: depth + 1)
            if found.count > 1 { break }
        }
        return found
    }
    private func descriptor(_ node: AXUIElement) -> (role: String, subrole: String, label: String, id: String) {
        let role = Self.string(node, "AXRole")
        let subrole = Self.string(node, "AXSubrole")
        var title = Self.string(node, "AXTitle", limit: 240)
        if title.isEmpty { title = Self.string(node, "AXDescription", limit: 240) }
        let id = Self.string(node, "AXIdentifier", limit: 200)
        return (role, subrole, title, id.isEmpty ? Self.string(node, "AXDOMIdentifier", limit: 200) : id)
    }
    private func sidebars(_ node: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard budget(depth), !Self.bool(node, "AXHidden") else { return [] }
        let role = Self.string(node, "AXRole")
        guard !["AXTextArea", "AXTextField", "AXSecureTextField", "AXStaticText", "AXButton", "AXLink", "AXMenuBar", "AXToolbar", "AXSheet", "AXDialog"].contains(role) else { return [] }
        let subrole = Self.string(node, "AXSubrole")
        if subrole == "AXLandmarkMain" { return [] }
        let d = descriptor(node)
        if PinnedChatPolicy.isSidebar(role: d.role, subrole: d.subrole, label: d.label, identifier: d.id) { return [node] }
        if ["AXLandmarkMain", "AXLandmarkComplementary"].contains(d.subrole) || ["main", "conversation", "chat-messages"].contains(d.id) { return [] }
        var found: [AXUIElement] = []
        for child in children(node) {
            found += sidebars(child, depth: depth + 1)
            if found.count > 1 { break }
        }
        return found
    }
    private func snapshot(_ node: AXUIElement, depth: Int = 0) -> PinNode? {
        guard budget(depth) else { return nil }
        let id = token(node)
        guard seen.insert(id).inserted else { return nil }
        let role = Self.string(node, "AXRole")
        let hidden = Self.bool(node, "AXHidden")
        let blocked = ["AXTextArea", "AXTextField", "AXSecureTextField", "AXMenu", "AXMenuItem", "AXSheet", "AXDialog"].contains(role)
        guard !hidden, !blocked else { return nil }
        let d = descriptor(node)
        var title = d.label
        if title.isEmpty, d.role == "AXStaticText" { title = Self.string(node, "AXValue", limit: 240) }
        let rawURL = Self.string(node, "AXURL")
        let pressable = ["AXLink", "AXButton", "AXRow"].contains(d.role) && Self.actions(node).contains(kAXPressAction as String)
        let descendants = children(node).compactMap { snapshot($0, depth: depth + 1) }
        if title.isEmpty, ["AXHeading", "AXDisclosureTriangle"].contains(d.role) {
            let labels = descendants.filter { $0.role == "AXStaticText" }.map(\.label).filter { !$0.isEmpty }
            if labels.count == 1 { title = labels[0] }
        }
        // Native row labels may be supplied by a single static-text child.
        if title.isEmpty, ["AXButton", "AXRow", "AXLink"].contains(d.role) {
            let labels = descendants.filter { $0.role == "AXStaticText" && !PinnedChatPolicy.pinLabels.contains(PinnedChatPolicy.normalized($0.label)) }.map(\.label).filter { !$0.isEmpty }
            if labels.count == 1 { title = labels[0] }
        }
        return PinNode(token: id, role: d.role, subrole: d.subrole, label: title,
            identifier: d.id, url: rawURL.isEmpty ? nil : rawURL,
            enabled: Self.bool(node, "AXEnabled", default: true), hidden: hidden,
            pressable: pressable, selected: Self.bool(node, "AXSelected"), children: descendants)
    }
    func scan(_ request: Request) -> Outcome {
        guard request.pid > 0, request.nativeProvider != nil || Self.browsers.contains(request.bundle) else {
            forget(); return .unavailable("Open ChatGPT or Claude, then tap Refresh.")
        }
        guard AXIsProcessTrusted() else { forget(); return .unavailable("Enable Accessibility for RelayBar to read the pinned-chat sidebar.") }
        guard isForeground(request.pid) else { forget(); return .unavailable("The assistant is no longer in front. Return to it and Refresh.") }
        deadline = Date().addingTimeInterval(1.2); visited = 0; limited = false; current = [:]; seen = []
        let application = AXUIElementCreateApplication(request.pid)
        prepareAccessibility(application, request: request)
        guard let window = Self.element(application, "AXFocusedWindow"),
              !Self.bool(window, "AXMinimized"), !Self.bool(window, "AXModal") else {
            forget(); return .unavailable("Open the assistant’s main window; a dialog or minimized window cannot supply pins.")
        }
        if let sheets = Self.attribute(window, "AXSheets") as? [AXUIElement], !sheets.isEmpty {
            forget(); return .unavailable("Close the app’s dialog before navigating pinned chats.")
        }
        let roots = webAreas(window)
        guard roots.count <= 1 else { forget(); return .unavailable("Several browser documents are exposed. Focus one assistant tab and Refresh.") }
        let document = roots.first ?? window
        var url = Self.string(document, "AXURL")
        if url.isEmpty { url = Self.string(document, "AXDocument") }
        let provider: PinProvider
        if let native = request.nativeProvider {
            if url.hasPrefix("http"), PinProvider.site(url) != native {
                forget(); return .unavailable("This window is not the assistant’s own chat interface.")
            }
            provider = native
        } else {
            guard !roots.isEmpty, let site = PinProvider.site(url) else {
                forget(); return .unavailable("Focus a chatgpt.com or claude.ai tab with its sidebar open.")
            }
            provider = site
        }
        let candidates = sidebars(document)
        guard candidates.count == 1, let sidebar = candidates.first else {
            forget(); return .unavailable(limited ? "Sidebar discovery reached its safety limit. Open the sidebar and Refresh." : "No single chat sidebar is exposed. Open the sidebar and its Pinned / Starred section, then Refresh.")
        }
        guard var tree = snapshot(sidebar) else { forget(); return .unavailable("The sidebar changed while reading it. Tap Refresh.") }
        // Normalize a semantically identified AXNavigation sidebar for the core.
        if tree.label.isEmpty { tree.label = "Sidebar" }
        var inventory = PinnedChatPolicy.inventory(sidebar: tree, provider: provider, native: request.nativeProvider != nil)
        if limited || inventory.limited { inventory.limited = true; inventory.chats = inventory.chats.map { var c = $0; c.enabled = false; return c } }
        guard isForeground(request.pid), let stillWindow = Self.element(application, "AXFocusedWindow"), CFEqual(stillWindow, window) else {
            forget(); return .unavailable("Window changed. Refresh in the intended assistant.")
        }
        let windowToken = token(window), documentToken = token(document)
        let sample = Sample(session: PinSession(pid: request.pid, bundle: request.bundle, window: windowToken,
            document: documentToken + "|" + url, provider: provider), inventory: inventory, elements: current,
            window: window, documentRoot: document, sidebar: sidebar, documentURL: url)
        prior = Dictionary(grouping: current.map { ($0.value, $0.key) }, by: { CFHash($0.0) })
        return .ready(sample)
    }
    func forget() { prior = [:]; current = [:] }

    /// Called only after an explicit tap, fresh rescan, generation validation and
    /// foreground PID check. No retry after AXPress, including a timeout.
    @MainActor static func press(_ chat: PinnedChat, in fresh: Sample, expected: Sample) -> String? {
        guard AXIsProcessTrusted(), NSWorkspace.shared.frontmostApplication?.processIdentifier == fresh.session.pid,
              CFEqual(fresh.window, expected.window), CFEqual(fresh.documentRoot, expected.documentRoot),
              CFEqual(fresh.sidebar, expected.sidebar), let target = fresh.elements[chat.token],
              let old = expected.elements[chat.token], CFEqual(target, old),
              let window = element(AXUIElementCreateApplication(fresh.session.pid), "AXFocusedWindow"), CFEqual(window, fresh.window),
              !bool(target, "AXHidden"), bool(target, "AXEnabled", default: true),
              actions(target).contains(kAXPressAction as String) else { return "Chat or window changed. No navigation was attempted; Refresh." }
        var documentURL = string(fresh.documentRoot, "AXURL")
        if documentURL.isEmpty { documentURL = string(fresh.documentRoot, "AXDocument") }
        guard documentURL == fresh.documentURL else { return "The active tab changed. No navigation was attempted." }
        AXUIElementSetMessagingTimeout(target, 0.15)
        let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
        return result == .success ? nil : "The app did not confirm the navigation request (AX \(result.rawValue)). Check the app; RelayBar will not retry automatically."
    }
}

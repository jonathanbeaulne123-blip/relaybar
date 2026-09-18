import Cocoa
import ApplicationServices

/// Reads a bounded, read-only text excerpt from the focused window of a
/// supported browser so "Ask about this page" can include page prose.
///
/// This reader deliberately does not reuse the native menu metadata interface:
/// that type exists to expose UI shape only, and holds no text accessor. The
/// reads here are narrow, budgeted, and fail closed:
/// - static text is read only after the user selects Excerpt mode;
/// - editable, search and secure fields are skipped, so a draft or password
///   field can never be captured;
/// - the traversal stops at a node, depth and time budget, and any exhausted
///   budget returns nothing at all rather than a partial excerpt presented as
///   the whole page;
/// - nothing is cached, persisted, logged or sent.
@MainActor
final class PageTextReader {
    static let shared = PageTextReader()

    static let maximumNodes = 500
    static let maximumDepth = 20
    static let secondsBudget: Double = 0.8
    static let perElementCharacters = 2000
    static let messagingTimeout: Float = 0.08

    /// Roles that carry the user's own editable content. Never read.
    static let excludedRoles: Set<String> = [
        "AXSecureTextField", "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"
    ]
    /// Roles whose value is page prose.
    static let readableRoles: Set<String> = ["AXStaticText", "AXHeading", "AXParagraph"]
    static let hiddenAttribute = "AXHidden"
    static let valueAttribute = "AXValue"
    static let childrenAttribute = "AXChildren"

    private let queue = DispatchQueue(label: "local.relaybar.page-text", qos: .userInitiated)
    private var busy = false

    private init() {}

    /// Completion runs on the main thread with nil when the excerpt could not be
    /// read honestly. Callers must report that rather than substituting one.
    func read(pid: Int32, bundle: String, completion: @escaping (String?) -> Void) {
        guard !busy, pid > 0, RBBridge.accessibilityTrusted() else {
            completion(nil); return
        }
        busy = true
        queue.async { [weak self] in
            let excerpt = Self.readSync(pid: pid, bundle: bundle)
            DispatchQueue.main.async {
                self?.busy = false
                completion(excerpt)
            }
        }
    }

    nonisolated private static func readSync(pid: Int32, bundle: String) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        // Ask the browser to expose its tree where it offers that switch. Only
        // ever set true; another assistive tool may rely on the same flags.
        requestBrowserExposure(pid: pid, bundle: bundle)

        let application = AXUIElementCreateApplication(pid)
        guard let window = element(application, "AXFocusedWindow") else { return nil }
        guard let focusedPID = frontmostPID(), focusedPID == pid else { return nil }

        let deadline = ProcessInfo.processInfo.systemUptime + secondsBudget
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited = Set<CFHashCode>()
        var pieces: [String] = []
        var total = 0

        while let (node, depth) = queue.first {
            queue.removeFirst()
            guard visited.count < maximumNodes else { return nil }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            guard visited.insert(CFHash(node)).inserted else { return nil }
            guard flag(node, hiddenAttribute) != true else { continue }

            let role = string(node, "AXRole")
            if let role = role, readableRoles.contains(role) {
                if let text = string(node, valueAttribute) {
                    let cleaned = normalize(text)
                    if !cleaned.isEmpty {
                        let clipped = cleaned.count <= perElementCharacters
                            ? cleaned
                            : String(cleaned.prefix(perElementCharacters))
                        total += clipped.count
                        guard total <= PageContextPolicy.maximumExcerpt else { return nil }
                        pieces.append(clipped)
                    }
                }
            }
            // Editable and secure fields are skipped entirely: their subtree is
            // never traversed either.
            if let role = role, excludedRoles.contains(role) { continue }
            guard depth < maximumDepth else { continue }
            guard let children = children(node) else { return nil }
            for child in children where queue.count + visited.count < maximumNodes {
                queue.append((child, depth + 1))
            }
        }
        let excerpt = pieces.joined(separator: "\n")
        return excerpt.isEmpty ? nil : excerpt
    }

    // MARK: - Narrow AX helpers (bounded, single-shot)

    nonisolated private static func frontmostPID() -> Int32? {
        if Thread.isMainThread { return NSWorkspace.shared.frontmostApplication?.processIdentifier }
        return DispatchQueue.main.sync { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    }

    nonisolated private static func requestBrowserExposure(pid: Int32, bundle: String) {
        guard NativeMenuPolicy.browserBundles.contains(bundle), bundle != "com.apple.Safari" else { return }
        let application = AXUIElementCreateApplication(pid)
        for attribute in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            var settable: DarwinBoolean = false
            AXUIElementSetMessagingTimeout(application, messagingTimeout)
            if AXUIElementIsAttributeSettable(application, attribute as CFString, &settable) == .success,
               settable.boolValue {
                if (raw(application, attribute) as? Bool) == true { return }
                if AXUIElementSetAttributeValue(application, attribute as CFString, kCFBooleanTrue) == .success { return }
            }
        }
    }

    nonisolated private static func raw(_ node: AXUIElement, _ attribute: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(node, messagingTimeout)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    nonisolated private static func element(_ node: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = raw(node, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    nonisolated private static func string(_ node: AXUIElement, _ attribute: String) -> String? {
        guard let value = raw(node, attribute), CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }

    nonisolated private static func flag(_ node: AXUIElement, _ attribute: String) -> Bool? {
        guard let value = raw(node, attribute) else { return nil }
        return value as? Bool
    }

    nonisolated private static func children(_ node: AXUIElement) -> [AXUIElement]? {
        AXUIElementSetMessagingTimeout(node, messagingTimeout)
        var count: CFIndex = 0
        let error = AXUIElementGetAttributeValueCount(node, childrenAttribute as CFString, &count)
        if error == .attributeUnsupported || error == .noValue { return [] }
        guard error == .success, count >= 0, count <= 4096 else { return nil }
        guard count > 0 else { return [] }
        var result: CFArray?
        guard AXUIElementCopyAttributeValues(node, childrenAttribute as CFString, 0, count, &result) == .success,
              let array = result as? [AXUIElement], array.count == count else { return nil }
        return array
    }

    nonisolated private static func normalize(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\t" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }
}

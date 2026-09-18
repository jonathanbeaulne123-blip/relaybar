import Cocoa
import ApplicationServices

struct NativeAXNode: Hashable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
    static func == (a: Self, b: Self) -> Bool { CFEqual(a.element, b.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}
final class NativeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
}

/// Accessed only on NativeMenuController's serial worker queue. Every IPC has a
/// timeout plus a per-read deadline/query budget; the main thread never scans AX.
final class NativeAXSource: NativeMenuSource {
    typealias Node = NativeAXNode
    private let cancellation: NativeCancellation
    private var budget = NativeReadBudget(now: 0)
    private var headers: [Node: NativeNodeHeader] = [:]
    private var headerBatches = 0, headerFallbacks = 0, childPages = 0, widestBranch = 0
    init(cancellation: NativeCancellation) { self.cancellation = cancellation; beginRead() }
    var now: Double { ProcessInfo.processInfo.systemUptime }
    var trusted: Bool { !cancellation.cancelled && AXIsProcessTrusted() }
    var limited: Bool { budget.currentFailure(now: now, cancelled: cancellation.cancelled) != .none }
    var metrics: NativeReadMetrics {
        var result = NativeReadMetrics()
        result.queries = budget.queries
        result.milliseconds = Int(max(0, min(60_000, (now - budget.start) * 1000)))
        result.headerBatches = headerBatches; result.headerFallbacks = headerFallbacks
        result.childPages = childPages; result.widestBranch = widestBranch
        result.failure = budget.currentFailure(now: now, cancelled: cancellation.cancelled)
        return result
    }
    func beginRead() {
        budget = NativeReadBudget(now: now); headers.removeAll(keepingCapacity: true)
        headerBatches = 0; headerFallbacks = 0; childPages = 0; widestBranch = 0
    }
    private func take() -> Bool { budget.take(now: now, cancelled: cancellation.cancelled) }

    func header(_ node: Node) -> NativeNodeHeader {
        // Role, subrole and hidden are static shape metadata for this read only.
        // Cache is cleared before every discovery and every pre-tap rescan.
        guard !limited else { return NativeNodeHeader(role: nil) }
        if let cached = headers[node] { return cached }
        guard take() else { return NativeNodeHeader(role: nil) }
        AXUIElementSetMessagingTimeout(node.element, 0.08)
        var result: CFArray?
        let names = ["AXRole", "AXSubrole", "AXHidden"] as CFArray
        let error = AXUIElementCopyMultipleAttributeValues(node.element, names,
            AXCopyMultipleAttributeOptions(rawValue: 0), &result)
        headerBatches += 1
        let shape: NativeNodeHeader
        if error == .success, let values = result as? [AnyObject], values.count == 3,
           let role = values[0] as? String {
            // Missing optional attributes are AXError values, not booleans or
            // labels. Typed casts deliberately leave those fields nil.
            shape = NativeNodeHeader(role: role, subrole: values[1] as? String, hidden: values[2] as? Bool)
        } else {
            // Browsers/providers that lack the batch API keep the safe scalar
            // path. Still bounded; no fabricated successful metadata.
            headerFallbacks += 1
            shape = NativeNodeHeader(role: value(node, "AXRole") as? String,
                subrole: value(node, "AXSubrole") as? String, hidden: value(node, "AXHidden") as? Bool)
        }
        headers[node] = shape
        return shape
    }
    func frontmostPID() -> Int32 {
        guard !cancellation.cancelled else { return -1 }
        if Thread.isMainThread { return NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1 }
        return DispatchQueue.main.sync { NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1 }
    }
    func application(_ pid: Int32) -> Node { Node(AXUIElementCreateApplication(pid)) }
    private func value(_ node: Node, _ name: String) -> CFTypeRef? {
        guard take() else { return nil }
        AXUIElementSetMessagingTimeout(node.element, 0.08)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node.element, name as CFString, &result) == .success else { return nil }
        return result
    }
    func element(_ node: Node, _ attribute: NativeAXAttribute) -> Node? {
        guard let result = value(node, attribute.rawValue), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return Node(unsafeBitCast(result, to: AXUIElement.self))
    }
    func string(_ node: Node, _ attribute: NativeAXAttribute) -> String? {
        if attribute == .role { return header(node).role }
        if attribute == .subrole { return header(node).subrole }
        guard let result = value(node, attribute.rawValue) else { return nil }
        if CFGetTypeID(result) == CFURLGetTypeID() {
            guard let text = CFURLGetString(unsafeBitCast(result, to: CFURL.self)) else { return nil }
            return text as String
        }
        guard CFGetTypeID(result) == CFStringGetTypeID() else { return nil }
        return result as? String
    }
    func flag(_ node: Node, _ attribute: NativeAXAttribute) -> Bool? {
        if attribute == .hidden { return header(node).hidden }
        guard let result = value(node, attribute.rawValue) else { return nil }
        if attribute == .hasPopup, let text = result as? String { return text == "menu" || text == "true" }
        return result as? Bool
    }
    func children(_ node: Node) -> [Node]? {
        guard take() else { return nil }
        AXUIElementSetMessagingTimeout(node.element, 0.08)
        var count: CFIndex = 0
        let error = AXUIElementGetAttributeValueCount(node.element, kAXChildrenAttribute as CFString, &count)
        if error == .attributeUnsupported || error == .noValue { return [] }
        guard error == .success, count >= 0 else { budget.fail(.readFailed); return nil }
        widestBranch = max(widestBranch, count)
        guard count <= NativeReadBudget.maximumChildren else { budget.fail(.children); return nil }
        if count == 0 { return [] }
        // A wide wrapper no longer poisons the scan at 257 children. Fetch
        // bounded pages; do not silently return only the first page.
        var children: [Node] = [], seen = Set<Node>(), offset = 0
        while offset < count {
            guard take() else { return nil }
            let length = min(NativeReadBudget.childPageSize, count - offset)
            var result: CFArray?
            let read = AXUIElementCopyAttributeValues(node.element, kAXChildrenAttribute as CFString,
                offset, length, &result)
            childPages += 1
            guard read == .success, let array = result as? [AXUIElement], array.count == length else {
                budget.fail(.readFailed); return nil
            }
            for element in array {
                let child = Node(element)
                guard seen.insert(child).inserted else { budget.fail(.readFailed); return nil }
                children.append(child)
            }
            offset += length
        }
        if count > NativeReadBudget.childPageSize {
            guard take() else { return nil }
            var finalCount: CFIndex = 0
            guard AXUIElementGetAttributeValueCount(node.element, kAXChildrenAttribute as CFString, &finalCount) == .success,
                  finalCount == count else { budget.fail(.readFailed); return nil }
        }
        return children
    }
    func rect(_ node: Node) -> NativeRect? {
        guard let p = value(node, kAXPositionAttribute), let s = value(node, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        let pointValue = unsafeBitCast(p, to: AXValue.self), sizeValue = unsafeBitCast(s, to: AXValue.self)
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetType(pointValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize,
              AXValueGetValue(pointValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return NativeRect(x: Double(point.x), y: Double(point.y), width: Double(size.width), height: Double(size.height))
    }
    func actions(_ node: Node) -> [String] {
        guard take() else { return [] }
        AXUIElementSetMessagingTimeout(node.element, 0.08)
        var result: CFArray?
        guard AXUIElementCopyActionNames(node.element, &result) == .success else { return [] }
        return result as? [String] ?? []
    }
    func hitTest(_ app: Node, x: Double, y: Double) -> Node? {
        guard take(), x.isFinite, y.isFinite, abs(x) < 1_000_000, abs(y) < 1_000_000 else { return nil }
        AXUIElementSetMessagingTimeout(app.element, 0.08)
        var result: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app.element, Float(x), Float(y), &result) == .success,
              let element = result else { return nil }
        return Node(element)
    }
    func pointerClick(x: Double, y: Double) -> Bool {
        guard take(), trusted, !cancellation.cancelled, x.isFinite, y.isFinite,
              abs(x) < 1_000_000, abs(y) < 1_000_000,
              !CGEventSource.buttonState(.combinedSessionState, button: .left) else { return false }
        let point = CGPoint(x: x, y: y)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left),
              !cancellation.cancelled, trusted else { return false }
        // One click = one down/up pair. Never retry after posting either event.
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
    func perform(_ node: Node, action: String) -> Bool {
        guard take(), trusted, action == "AXPress" || action == "AXShowMenu" else { return false }
        AXUIElementSetMessagingTimeout(node.element, 0.2)
        return AXUIElementPerformAction(node.element, action as CFString) == .success
    }

    /// Ask a Chromium browser to expose its accessibility tree where it offers
    /// that switch. No browser preference files are changed; no web JS is run.
    /// Never set these flags false: another assistive tool may also depend on them.
    func prepareBrowser(pid: Int32, bundle: String) {
        guard trusted, NativeMenuPolicy.browserBundles.contains(bundle), bundle != "com.apple.Safari",
              frontmostPID() == pid else { return }
        let app = application(pid)
        for attribute in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            guard take() else { return }
            var settable: DarwinBoolean = false
            AXUIElementSetMessagingTimeout(app.element, 0.08)
            if AXUIElementIsAttributeSettable(app.element, attribute as CFString, &settable) == .success, settable.boolValue {
                if (value(app, attribute) as? Bool) == true { return }
                guard !cancellation.cancelled, trusted, frontmostPID() == pid else { return }
                if AXUIElementSetAttributeValue(app.element, attribute as CFString, kCFBooleanTrue) == .success { return }
            }
        }
    }
}

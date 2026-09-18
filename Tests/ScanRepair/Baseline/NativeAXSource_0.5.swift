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
    private var deadline: Double = 0
    private var queries = 0
    private var hitLimit = false
    init(cancellation: NativeCancellation) { self.cancellation = cancellation; beginRead() }
    var now: Double { ProcessInfo.processInfo.systemUptime }
    var trusted: Bool { !cancellation.cancelled && AXIsProcessTrusted() }
    var limited: Bool { hitLimit || cancellation.cancelled || now > deadline }
    func beginRead() { deadline = now + 0.85; queries = 0; hitLimit = false }
    private func take() -> Bool {
        guard !limited, queries < 3500 else { hitLimit = true; return false }
        queries += 1; return true
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
        guard let result = value(node, attribute.rawValue) else { return nil }
        if CFGetTypeID(result) == CFURLGetTypeID() {
            guard let text = CFURLGetString(unsafeBitCast(result, to: CFURL.self)) else { return nil }
            return text as String
        }
        guard CFGetTypeID(result) == CFStringGetTypeID() else { return nil }
        return result as? String
    }
    func flag(_ node: Node, _ attribute: NativeAXAttribute) -> Bool? {
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
        guard error == .success, count >= 0, count <= 256 else { hitLimit = true; return nil }
        if count == 0 { return [] }
        guard take() else { return nil }
        var result: CFArray?
        guard AXUIElementCopyAttributeValues(node.element, kAXChildrenAttribute as CFString, 0, count, &result) == .success,
              let array = result as? [AXUIElement] else { return nil }
        return array.map(Node.init)
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

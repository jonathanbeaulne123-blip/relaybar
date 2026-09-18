import Foundation

/// Only UI metadata is available through this interface. There is deliberately
/// no AXValue/selected-text accessor, keyboard injection, JS, or network client.
public enum NativeAXAttribute: String {
    case role = "AXRole", subrole = "AXSubrole", title = "AXTitle"
    case description = "AXDescription", url = "AXURL"
    case enabled = "AXEnabled", hidden = "AXHidden", expanded = "AXExpanded"
    case hasPopup = "AXHasPopup", parent = "AXParent"
    case focusedWindow = "AXFocusedWindow", focusedElement = "AXFocusedUIElement"
}
public struct NativeRect: Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var valid: Bool { [x,y,width,height].allSatisfy(\.isFinite) && width > 1 && height > 1 }
    public var center: (Double, Double) { (x + width/2, y + height/2) }
    public func intersects(_ other: NativeRect) -> Bool {
        valid && other.valid && x < other.x + other.width && other.x < x + width &&
            y < other.y + other.height && other.y < y + height
    }
}
public protocol NativeMenuSource: AnyObject {
    associatedtype Node: Hashable
    var trusted: Bool { get }
    var limited: Bool { get }
    var now: Double { get } // monotonic clock
    func beginRead()
    func frontmostPID() -> Int32
    func application(_ pid: Int32) -> Node
    func element(_ node: Node, _ attribute: NativeAXAttribute) -> Node?
    func string(_ node: Node, _ attribute: NativeAXAttribute) -> String?
    func flag(_ node: Node, _ attribute: NativeAXAttribute) -> Bool?
    /// nil means a failed or oversized read, not an empty child list.
    func children(_ node: Node) -> [Node]?
    func rect(_ node: Node) -> NativeRect?
    func actions(_ node: Node) -> [String]
    func hitTest(_ app: Node, x: Double, y: Double) -> Node?
    func perform(_ node: Node, action: String) -> Bool
}
public enum NativeSite: String { case sheets, chatgpt, claude, other }
public enum NativeMenuPolicy {
    public static let browserBundles: Set<String> = ["com.google.Chrome", "com.microsoft.edgemac",
        "com.brave.Browser", "org.chromium.Chromium", "com.apple.Safari"]
    public static let maximumNodes = 900
    public static let maximumDepth = 24
    public static let pageSize = 4
    public static let freshness = 2.5
    // Stop before fetching children or text inside these content-bearing nodes.
    public static let contentRoles: Set<String> = ["AXTable", "AXGrid", "AXRow", "AXCell",
        "AXColumn", "AXTextArea", "AXTextField", "AXStaticText", "AXOutline", "AXList",
        "AXImage", "AXCanvas", "AXScrollBar"]
    public static let itemRoles: Set<String> = ["AXMenuItem", "AXMenuBarItem", "AXPopUpButton", "AXButton"]
    public static let standardMenus: Set<String> = ["file", "edit", "view", "insert", "format", "data",
        "tools", "extensions", "help", "accessibility"]
    public static func site(_ raw: String) -> NativeSite {
        guard raw.count <= 4096, let u = URLComponents(string: raw), u.scheme?.lowercased() == "https",
              u.user == nil, u.password == nil, u.port == nil || u.port == 443,
              let host = u.host?.lowercased() else { return .other }
        if host == "chatgpt.com" || host == "chat.openai.com" { return .chatgpt }
        if host == "claude.ai" { return .claude }
        guard host == "docs.google.com" else { return .other }
        // Reject encoded separators, published pages, look-alike hosts and previews.
        let path = u.percentEncodedPath
        guard !path.contains("%"), !path.contains("//") else { return .other }
        let pieces = path.split(separator: "/").map(String.init)
        let offset: Int
        if pieces.prefix(2) == ["spreadsheets", "d"] { offset = 2 }
        else if pieces.count >= 6, pieces[0] == "spreadsheets", pieces[1] == "u",
                !pieces[2].isEmpty, pieces[2].allSatisfy(\.isNumber), pieces[3] == "d" { offset = 4 }
        else { return .other }
        guard pieces.count == offset + 2, pieces[offset+1] == "edit",
              !pieces[offset].isEmpty, pieces[offset].count <= 160,
              pieces[offset].utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) ||
                  (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return .other }
        return .sheets
    }
    public static func label(_ raw: String?) -> String? {
        guard let raw = raw, raw.count <= 256,
              !raw.unicodeScalars.contains(where: { $0.value < 32 || (0x202A...0x202E).contains($0.value) ||
                  (0x2066...0x2069).contains($0.value) }) else { return nil }
        let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }
    public static func pageCount(_ count: Int) -> Int { max(1, (max(0, count) + pageSize-1)/pageSize) }
}
public struct NativeRoute<Node: Hashable>: Equatable {
    public let pid: Int32
    public let bundle: String
    public let window: Node
    public let webArea: Node
    // Exact current URL, including fragment/worksheet. Memory-only; never logged.
    public let url: String
    public var site: NativeSite { NativeMenuPolicy.site(url) }
}
public struct NativeControl<Node: Hashable>: Equatable {
    public let node: Node
    public let label: String
    public let path: String
    public let role: String
    public let isMenu: Bool
    public let action: String
    public let enabled: Bool
    public let frame: NativeRect
}
public struct NativeMenuSnapshot<Node: Hashable> {
    public var route: NativeRoute<Node>?
    public var focus: Node?
    public var roots: [NativeControl<Node>] = []
    public var openItems: [NativeControl<Node>] = []
    public var status = "Waiting for a supported browser."
    public var sampledAt: Double
    public var nodesVisited = 0
    public var ready: Bool { route?.site == .sheets && (!roots.isEmpty || !openItems.isEmpty) }
    public func sameContent(as other: Self) -> Bool {
        route == other.route && focus == other.focus && roots == other.roots &&
            openItems == other.openItems && status == other.status
    }
}
public enum NativeDispatchResult: Equatable {
    case requested, refused(String), uncertain
}

/// The same bounded traversal and revalidation run in the Mac app and tests.
/// Reading never performs a UI action. Only request() can call source.perform.
public final class NativeMenuEngine<S: NativeMenuSource> {
    public typealias N = S.Node
    private let source: S
    public init(source: S) { self.source = source }

    public func scan(pid: Int32, bundle: String) -> NativeMenuSnapshot<N> {
        source.beginRead()
        var result = NativeMenuSnapshot<N>(sampledAt: source.now)
        guard source.trusted else { result.status = "Accessibility permission needed."; return result }
        guard NativeMenuPolicy.browserBundles.contains(bundle) else {
            result.status = "This application keeps its native controls."; return result
        }
        guard source.frontmostPID() == pid else { result.status = "Application changed."; return result }
        let app = source.application(pid)
        guard let window = source.element(app, .focusedWindow), let windowRect = source.rect(window), windowRect.valid else {
            result.status = "Browser did not expose a focused window."; return result
        }
        result.focus = source.element(app, .focusedElement)
        // Search the focused window only; never enumerate all tabs/windows.
        var queue: [(N,Int)] = [(window, 0)], seen = Set<N>(), areas: [N] = []
        var cursor = 0, incomplete = false, modal = false
        while cursor < queue.count {
            let (node, depth) = queue[cursor]; cursor += 1
            guard seen.insert(node).inserted else { continue }
            if seen.count > NativeMenuPolicy.maximumNodes || depth > NativeMenuPolicy.maximumDepth || source.limited {
                incomplete = true; break
            }
            guard source.flag(node, .hidden) != true else { continue }
            guard let role = source.string(node, .role) else { incomplete = true; continue }
            if role == "AXSheet" || role == "AXDialog" || source.string(node, .subrole) == "AXDialog" {
                modal = true; continue
            }
            if role == "AXWebArea" {
                if let r = source.rect(node), r.intersects(windowRect) { areas.append(node) }
                continue // Do not mistake an iframe for another browser tab.
            }
            if NativeMenuPolicy.contentRoles.contains(role) || role == "AXMenuBar" { continue }
            guard let children = source.children(node) else { incomplete = true; continue }
            queue.append(contentsOf: children.map { ($0, depth+1) })
        }
        result.nodesVisited = seen.count
        guard !incomplete, !source.limited else { result.status = "Accessibility scan incomplete; actions disabled."; return result }
        guard !modal else { result.status = "Close the browser dialog to show Sheet menus."; return result }
        guard areas.count == 1, let web = areas.first,
              let url = source.string(web, .url), url.count <= 4096 else {
            result.status = areas.count > 1 ? "Ambiguous browser document; actions disabled." : "Browser has not exposed the page URL."
            return result
        }
        let route = NativeRoute(pid: pid, bundle: bundle, window: window, webArea: web, url: url)
        result.route = route
        guard route.site == .sheets else { result.status = "Native browser context available."; return result }
        // Depth-first ordering reaches menu children before the spreadsheet grid.
        var stack: [(N,Int,String,Bool,Bool)] = [(web,0,"",false,false)]
        seen.removeAll(); var roots: [NativeControl<N>] = [], groups: [(Int,[NativeControl<N>])] = []
        while let (node, depth, path, inBar, inMenu) = stack.popLast() {
            guard seen.insert(node).inserted else { continue }
            if seen.count > NativeMenuPolicy.maximumNodes || depth > NativeMenuPolicy.maximumDepth || source.limited {
                incomplete = true; break
            }
            guard source.flag(node, .hidden) != true else { continue }
            guard let role = source.string(node, .role) else { incomplete = true; continue }
            if node != web && role == "AXWebArea" { continue }
            if role == "AXSheet" || role == "AXDialog" || source.string(node, .subrole) == "AXDialog" { modal = true; continue }
            if NativeMenuPolicy.contentRoles.contains(role) { continue }
            // The cell canvas is usually a scroll area; don't fetch its contents.
            if role == "AXScrollArea" { continue }
            let isBar = role == "AXMenuBar"
            let isPopup = role == "AXMenu"
            if (isBar || isPopup), !(source.rect(node)?.valid ?? false) { continue }
            guard let children = source.children(node) else { incomplete = true; continue }
            var nextPath = path
            if NativeMenuPolicy.itemRoles.contains(role), (inBar || inMenu),
               let control = control(node, role: role, path: path, root: inBar, children: children) {
                if inBar { roots.append(control) }
                else { groups.append((depth, [control])) }
                if control.isMenu { nextPath = path.isEmpty ? control.label : path + " › " + control.label }
            }
            // Menubar descendants are root navigation; menu descendants are actions.
            let childInBar = isBar || (inBar && !isPopup)
            let childInMenu = isPopup || (inMenu && !isBar)
            for child in children.reversed() {
                stack.append((child, depth+1, nextPath, childInBar && !isPopup, childInMenu))
            }
        }
        result.nodesVisited += seen.count
        guard !incomplete, !source.limited else { result.status = "Accessibility scan limit reached; actions disabled."; return result }
        guard !modal else { result.status = "A Sheet dialog is open; actions disabled."; return result }
        guard source.frontmostPID() == pid, source.element(app, .focusedWindow) == window,
              source.string(web, .url) == url, source.element(app, .focusedElement) == result.focus else {
            result.route = nil; result.status = "Document changed during discovery."; return result
        }
        // Custom menu ordering is a convenience only; no menu is omitted.
        result.roots = roots.enumerated().sorted { a,b in
            let sa = NativeMenuPolicy.standardMenus.contains(a.element.label.lowercased())
            let sb = NativeMenuPolicy.standardMenus.contains(b.element.label.lowercased())
            return sa == sb ? a.offset < b.offset : !sa
        }.map(\.element)
        var unique = Set<N>()
        // Deeper open submenu controls come first. Distinct visible menus remain
        // reachable; do not guess which sibling popup Google considers active.
        result.openItems = groups.enumerated().sorted { a,b in
            a.element.0 == b.element.0 ? a.offset < b.offset : a.element.0 > b.element.0
        }.flatMap { $0.element.1 }.filter { unique.insert($0.node).inserted }
        result.status = result.ready ? "Google Sheets · native menu controls" :
            "Sheet detected, but no accessible menus are exposed."
        result.sampledAt = source.now
        return result
    }

    private func control(_ node: N, role: String, path: String, root: Bool, children: [N]) -> NativeControl<N>? {
        guard let label = NativeMenuPolicy.label(source.string(node, .title)) ??
                NativeMenuPolicy.label(source.string(node, .description)),
              let frame = source.rect(node), frame.valid else { return nil }
        let actions = source.actions(node)
        let menuChild = children.contains { source.string($0, .role) == "AXMenu" }
        let isMenu = root || menuChild || source.flag(node, .hasPopup) == true ||
            source.flag(node, .expanded) != nil || actions.contains("AXShowMenu")
        let action = isMenu && actions.contains("AXShowMenu") ? "AXShowMenu" : "AXPress"
        // Missing enabled state or action support is not permission to click.
        return NativeControl(node: node, label: label, path: path, role: role, isMenu: isMenu,
            action: action, enabled: source.flag(node, .enabled) == true && actions.contains(action), frame: frame)
    }

    public func request(_ control: NativeControl<N>, expected: NativeMenuSnapshot<N>) -> NativeDispatchResult {
        guard let route = expected.route, route.site == .sheets, expected.ready,
              (expected.roots + expected.openItems).contains(control), control.enabled,
              source.now >= expected.sampledAt, source.now - expected.sampledAt <= NativeMenuPolicy.freshness else {
            return .refused("Expired or unavailable button. Tap the current control again.")
        }
        let fresh = scan(pid: route.pid, bundle: route.bundle)
        guard fresh.ready, fresh.route == route, fresh.focus == expected.focus,
              (fresh.roots + fresh.openItems).contains(control) else {
            return .refused("The document, selection, menu or button changed. Nothing was requested.")
        }
        let app = source.application(route.pid)
        let (x,y) = control.frame.center
        guard var hit = source.hitTest(app, x: x, y: y) else {
            return .refused("The control could not be verified on screen. Use its Sheet menu directly.")
        }
        var hitMatches = false, visited = Set<N>()
        for _ in 0..<24 {
            if hit == control.node { hitMatches = true; break }
            guard visited.insert(hit).inserted, let parent = source.element(hit, .parent) else { break }
            hit = parent
        }
        guard hitMatches, !source.limited, source.trusted, source.frontmostPID() == route.pid,
              source.element(app, .focusedWindow) == route.window,
              source.string(route.webArea, .url) == route.url,
              source.element(app, .focusedElement) == expected.focus,
              source.flag(control.node, .enabled) == true,
              source.actions(control.node).contains(control.action) else {
            return .refused("The target is covered, changed, or no longer in the foreground.")
        }
        // A single AX action, never a coordinate click or a keyboard fallback.
        // Failure can mean the application already received it: DO NOT RETRY.
        return source.perform(control.node, action: control.action) ? .requested : .uncertain
    }
}

public struct NativeTapRequest: Equatable {
    public let id: UUID
    public let revision: Int
    public let index: Int
    public let createdAt: Double
}
public enum NativeTapDecision: Equatable { case ignore, confirm(NativeTapRequest), execute(NativeTapRequest) }
/// Inline Touch Bar confirmation keeps the browser foreground and its menu open.
public struct NativeTapGate {
    public private(set) var pending: NativeTapRequest?
    public private(set) var executing: NativeTapRequest?
    public init() {}
    public mutating func tap(index: Int, revision: Int, now: Double, isMenu: Bool, ask: Bool) -> NativeTapDecision {
        guard now.isFinite, index >= 0, executing == nil else { return .ignore }
        let request = NativeTapRequest(id: UUID(), revision: revision, index: index, createdAt: now)
        if !isMenu && ask { pending = request; return .confirm(request) }
        pending = nil; executing = request; return .execute(request)
    }
    public mutating func confirm(revision: Int, now: Double) -> NativeTapDecision {
        guard let p = pending, executing == nil, p.revision == revision, now.isFinite,
              now >= p.createdAt, now - p.createdAt < 8 else { pending = nil; return .ignore }
        pending = nil; executing = p; return .execute(p)
    }
    public mutating func expire(revision: Int, now: Double) -> Bool {
        guard let p = pending else { return false }
        if p.revision != revision || !now.isFinite || now < p.createdAt || now - p.createdAt >= 8 {
            pending = nil; return true
        }
        return false
    }
    public mutating func finish(_ id: UUID) { if executing?.id == id { executing = nil } }
    public mutating func cancel() { pending = nil; executing = nil }
}

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
/// Shape only: deliberately excludes names, values, descriptions and URLs.
public struct NativeNodeHeader {
    public var role: String?
    public var subrole: String?
    public var hidden: Bool?
    public init(role: String?, subrole: String? = nil, hidden: Bool? = nil) {
        self.role = role; self.subrole = subrole; self.hidden = hidden
    }
}
public enum NativeScanFailure: String {
    case none, deadline, queries, children, depth, nodes, readFailed, cancelled
    public var explanation: String {
        switch self {
        case .none: return "none"
        case .deadline: return "time budget reached"
        case .queries: return "AX query budget reached"
        case .children: return "child-list safety bound reached"
        case .depth: return "tree depth bound reached"
        case .nodes: return "node bound reached"
        case .readFailed: return "required UI metadata unavailable or changed"
        case .cancelled: return "scan cancelled"
        }
    }
}
public struct NativeReadMetrics {
    public var queries = 0
    public var milliseconds = 0
    public var headerBatches = 0
    public var headerFallbacks = 0
    public var childPages = 0
    public var widestBranch = 0
    public var failure: NativeScanFailure = .none
    public init() {}
}
/// Shared with the real adapter and portable regression tests. These remain
/// hard bounds, not a setting the user has to tune for each workbook.
public struct NativeReadBudget {
    public static let seconds: Double = 0.85
    public static let maximumQueries = 5000
    public static let maximumChildren = 4096
    public static let childPageSize = 64
    public private(set) var start: Double
    public private(set) var queries = 0
    public private(set) var failure: NativeScanFailure = .none
    public init(now: Double) { start = now }
    public func currentFailure(now: Double, cancelled: Bool) -> NativeScanFailure {
        if cancelled { return .cancelled }
        if failure != .none { return failure }
        if !now.isFinite || !start.isFinite || now < start || now - start > Self.seconds { return .deadline }
        return .none
    }
    public mutating func take(now: Double, cancelled: Bool) -> Bool {
        let current = currentFailure(now: now, cancelled: cancelled)
        guard current == .none else { fail(current); return false }
        guard queries < Self.maximumQueries else { fail(.queries); return false }
        queries += 1; return true
    }
    public mutating func fail(_ reason: NativeScanFailure) { if failure == .none { failure = reason } }
}
public protocol NativeMenuSource: AnyObject {
    associatedtype Node: Hashable
    var trusted: Bool { get }
    var limited: Bool { get }
    var now: Double { get } // monotonic clock
    var metrics: NativeReadMetrics { get }
    func header(_ node: Node) -> NativeNodeHeader
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
    /// Post one verified primary-button click at a point already revalidated by
    /// the engine. Implementations must never retry an uncertain delivery.
    func pointerClick(x: Double, y: Double) -> Bool
    func perform(_ node: Node, action: String) -> Bool
}
public extension NativeMenuSource {
    // Defaults keep existing service doubles explicit; the Mac implementation
    // overrides header with one batched AX request and read-local caching.
    var metrics: NativeReadMetrics {
        var result = NativeReadMetrics(); if limited { result.failure = .readFailed }; return result
    }
    func header(_ node: Node) -> NativeNodeHeader {
        NativeNodeHeader(role: string(node, .role), subrole: string(node, .subrole), hidden: flag(node, .hidden))
    }
}
public enum NativeSite: String { case sheets, chatgpt, claude, other }
public enum NativeMenuPolicy {
    public static let browserBundles: Set<String> = ["com.google.Chrome", "com.microsoft.edgemac",
        "com.brave.Browser", "org.chromium.Chromium", "com.apple.Safari"]
    /// Chromium exposes web accessibility actions asynchronously. For Sheet
    /// controls we therefore use one literal pointer click after the same fresh
    /// AX route/frame/hit-test verification. Safari keeps native AX actions.
    public static let verifiedPointerBundles: Set<String> = ["com.google.Chrome", "com.microsoft.edgemac",
        "com.brave.Browser", "org.chromium.Chromium"]
    public static let maximumNodes = 900
    // Google Sheets can expose well over 900 non-content UI nodes around its
    // custom-menu layer. Keep browser identity at 900, but give only the Sheet
    // menu phase bounded extra room; time/query/depth/child caps still fail closed.
    public static let maximumMenuNodes = 1600
    public static let maximumDepth = 24
    public static let pageSize = 4
    public static let freshness = 2.5
    // Stop before fetching children or text inside these content-bearing nodes.
    public static let contentRoles: Set<String> = ["AXTable", "AXGrid", "AXRow", "AXCell",
        "AXColumn", "AXTextArea", "AXTextField", "AXStaticText", "AXOutline", "AXList",
        "AXImage", "AXCanvas", "AXScrollBar"]
    // Formatting toolbars and tab selectors are not custom-menu inventories.
    // Apply ONLY inside the document, never to the browser-window identity scan
    // or to descendants of an actual menu container.
    public static let chromeRoles: Set<String> = ["AXToolbar", "AXTabGroup", "AXRadioGroup"]
    public static let leafRoles: Set<String> = ["AXLink", "AXCheckBox", "AXRadioButton", "AXSlider",
        "AXProgressIndicator", "AXBusyIndicator", "AXSplitter", "AXColorWell", "AXIncrementor"]
    public static let itemRoles: Set<String> = ["AXMenuItem", "AXMenuBarItem", "AXPopUpButton", "AXButton"]
    public static let standardMenus: Set<String> = ["file", "edit", "view", "insert", "format", "data",
        "tools", "extensions", "help", "accessibility"]
    public static func site(_ raw: String) -> NativeSite {
        guard raw.count <= 4096, let u = URLComponents(string: raw), u.scheme?.lowercased() == "https",
              u.user == nil, u.password == nil, u.port == nil || u.port == 443,
              let host = u.host?.lowercased() else { return .other }
        if host == "chatgpt.com" || host == "chat.openai.com" { return .chatgpt }
        if host == "claude.ai" { return .claude }
        if host == "script.google.com" { return .sheets }
        guard host == "docs.google.com" else { return .other }
        let path = u.percentEncodedPath
        guard !path.contains("%"), !path.contains("//") else { return .other }
        let lower = path.lowercased()
        if lower.contains("/spreadsheets/d/") || lower.contains("/spreadsheets/u/") {
            return .sheets
        }
        return .other
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

    public var isAppsScript: Bool {
        !NativeMenuPolicy.standardMenus.contains(label.lowercased()) || path.lowercased().contains("extensions")
    }
}
public struct NativeMenuSnapshot<Node: Hashable> {
    public var route: NativeRoute<Node>?
    public var focus: Node?
    public var roots: [NativeControl<Node>] = []
    public var openItems: [NativeControl<Node>] = []
    public var status = "Waiting for a supported browser."
    public var sampledAt: Double
    public var nodesVisited = 0
    public var readMetrics = NativeReadMetrics()
    public var scanPhase = "browser identity"
    public var failure: NativeScanFailure = .none
    public var deepestLevel = 0
    public var prunedContentNodes = 0
    public var prunedChromeNodes = 0
    public var menuContainersSeen = 0
    public var candidatesSeen = 0
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

    public func scan(pid: Int32, bundle: String, expandingMenu: Bool = false, fallbackURL: String? = nil) -> NativeMenuSnapshot<N> {
        source.beginRead()
        var result = scanBody(pid: pid, bundle: bundle, expandingMenu: expandingMenu, fallbackURL: fallbackURL)
        result.readMetrics = source.metrics
        if result.readMetrics.failure != .none { result.failure = result.readMetrics.failure }
        if result.failure != .none {
            // Never publish partially scanned or expired actions, even if some
            // candidate labels were found before a budget or API failure.
            result.roots = []; result.openItems = []
            result.status = "\(result.scanPhase): \(result.failure.explanation); actions disabled."
        }
        return result
    }

    private func scanBody(pid: Int32, bundle: String, expandingMenu: Bool, fallbackURL: String? = nil) -> NativeMenuSnapshot<N> {
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
            result.deepestLevel = max(result.deepestLevel, depth)
            if seen.count > NativeMenuPolicy.maximumNodes || depth > NativeMenuPolicy.maximumDepth || source.limited {
                result.failure = source.limited ? source.metrics.failure :
                    (depth > NativeMenuPolicy.maximumDepth ? .depth : .nodes)
                incomplete = true; break
            }
            let header = source.header(node)
            guard header.hidden != true else { continue }
            guard let role = header.role else { incomplete = true; result.failure = .readFailed; continue }
            if role == "AXSheet" || role == "AXDialog" || header.subrole == "AXDialog" {
                modal = true; continue
            }
            if role == "AXWebArea" {
                if let r = source.rect(node), r.intersects(windowRect) { areas.append(node) }
                continue // Do not mistake an iframe for another browser tab.
            }
            if NativeMenuPolicy.contentRoles.contains(role) || role == "AXMenuBar" { continue }
            guard let children = source.children(node) else { incomplete = true; result.failure = .readFailed; continue }
            queue.append(contentsOf: children.map { ($0, depth+1) })
        }
        result.nodesVisited = seen.count
        guard !incomplete, !source.limited else {
            if result.failure == .none { result.failure = .readFailed }; return result
        }
        guard !modal else { result.status = "Close the browser dialog to show Sheet menus."; return result }
        
        var chosenWeb: N?
        var chosenURL: String?

        // 1. If any web area has a Google Sheets URL directly on AXURL, choose it
        for web in areas {
            if let u = source.string(web, .url), !u.isEmpty {
                let site = NativeMenuPolicy.site(u)
                if site == .sheets {
                    chosenWeb = web
                    chosenURL = u
                    break
                }
            }
        }

        // 2. If not matched by URL, sort by screen area and pick the largest web area (main spreadsheet document)
        if chosenWeb == nil {
            let sortedByArea = areas.compactMap { web -> (N, Double)? in
                guard let r = source.rect(web) else { return nil }
                return (web, r.width * r.height)
            }.sorted(by: { $0.1 > $1.1 })

            if let largest = sortedByArea.first?.0 {
                chosenWeb = largest
                chosenURL = source.string(largest, .url)
            } else if let first = areas.first {
                chosenWeb = first
                chosenURL = source.string(first, .url)
            }
        }

        // 3. If AXURL was missing or empty, use fallbackURL from the active browser tab
        if (chosenURL == nil || chosenURL?.isEmpty == true), let fallback = fallbackURL, !fallback.isEmpty {
            chosenURL = fallback
        }

        guard let web = chosenWeb, let url = chosenURL, url.count <= 4096 else {
            result.status = areas.isEmpty ? "Browser has not exposed any web area." : "Browser has not exposed the page URL."
            return result
        }
        let route = NativeRoute(pid: pid, bundle: bundle, window: window, webArea: web, url: url)
        result.route = route
        guard route.site == .sheets else { result.status = "Native browser context available."; return result }
        result.scanPhase = "Sheet menu discovery"
        // Menu traversal is still bounded and complete-or-disabled. Cheap shape
        // headers prune content and formatting branches before child IPC.
        var stack: [(N,Int,String,Bool,Bool)] = [(web,0,"",false,false)]
        seen.removeAll(); var roots: [NativeControl<N>] = [], groups: [(Int,[NativeControl<N>])] = []
        while let (node, depth, path, inBar, inMenu) = stack.popLast() {
            guard seen.insert(node).inserted else { continue }
            result.deepestLevel = max(result.deepestLevel, depth)
            if seen.count > NativeMenuPolicy.maximumMenuNodes || depth > NativeMenuPolicy.maximumDepth || source.limited {
                result.failure = source.limited ? source.metrics.failure :
                    (depth > NativeMenuPolicy.maximumDepth ? .depth : .nodes)
                incomplete = true; break
            }
            let header = source.header(node)
            guard header.hidden != true else { continue }
            guard let role = header.role else { incomplete = true; result.failure = .readFailed; continue }
            if node != web && role == "AXWebArea" { continue }
            if role == "AXSheet" || role == "AXDialog" || header.subrole == "AXDialog" { modal = true; continue }
            // During the short read-only window after a user opens a menu, let
            // AXList wrappers through. Chromium can expose a web popup as an
            // accessible list rather than AXMenu. We still never read list
            // labels/values unless a descendant has a menu-item role.
            let contentRole = NativeMenuPolicy.contentRoles.contains(role)
            if (contentRole && !(expandingMenu && role == "AXList")) || NativeMenuPolicy.leafRoles.contains(role) {
                result.prunedContentNodes += 1; continue
            }
            if !inBar && !inMenu && NativeMenuPolicy.chromeRoles.contains(role) {
                result.prunedChromeNodes += 1; continue
            }
            // The cell canvas is usually a scroll area; don't fetch its contents.
            if role == "AXScrollArea" { result.prunedContentNodes += 1; continue }
            let isBar = role == "AXMenuBar"
            let isPopup = role == "AXMenu"
            if isBar || isPopup { result.menuContainersSeen += 1 }
            if (isBar || isPopup), !(source.rect(node)?.valid ?? false) { continue }
            guard let children = source.children(node) else { incomplete = true; result.failure = .readFailed; continue }
            var nextPath = path
            // AXMenuItem itself is a strong signal. Some Chromium web menus put
            // those items under generic AXGroup/AXList wrappers rather than an
            // AXMenu node, so an open custom Apps Script menu would otherwise
            // be invisible even though every action is exposed.
            let strongOpenItem = !inBar && (role == "AXMenuItem" || role == "AXMenuBarItem")
            if NativeMenuPolicy.itemRoles.contains(role), (inBar || inMenu || (expandingMenu && strongOpenItem)),
               let control = control(node, role: role, path: path, root: inBar, children: children) {
                result.candidatesSeen += 1
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
        guard !incomplete, !source.limited else {
            if result.failure == .none { result.failure = .readFailed }; return result
        }
        guard !modal else { result.status = "A Sheet dialog is open; actions disabled."; return result }
        result.scanPhase = "document revalidation"
        let revalURL = source.string(web, .url)
        let urlValid = (revalURL == nil || revalURL == url)
        guard source.frontmostPID() == pid, source.element(app, .focusedWindow) == window, urlValid else {
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
        // Chromium sometimes omits AXEnabled for a web menu trigger while still
        // exposing a supported AXPress/AXShowMenu action. Treat only an explicit
        // false as disabled for menu navigation; leaf actions remain strict.
        let enabledFlag = source.flag(node, .enabled)
        let enabled = actions.contains(action) && (isMenu ? enabledFlag != false : enabledFlag == true)
        return NativeControl(node: node, label: label, path: path, role: role, isMenu: isMenu,
            action: action, enabled: enabled, frame: frame)
    }

    public func request(_ control: NativeControl<N>, expected: NativeMenuSnapshot<N>) -> NativeDispatchResult {
        guard let route = expected.route, route.site == .sheets, expected.ready,
              (expected.roots + expected.openItems).contains(control), control.enabled,
              source.now >= expected.sampledAt, source.now - expected.sampledAt <= NativeMenuPolicy.freshness else {
            return .refused("Expired or unavailable button. Tap the current control again.")
        }
        // If this control came from the short menu-expansion view, revalidate
        // using the same popup-shape policy. Otherwise a valid AXMenuItem under
        // Chromium's generic AXGroup/AXList wrapper could be displayed but then
        // refused solely because the normal scan intentionally prunes that wrapper.
        let fresh = scan(pid: route.pid, bundle: route.bundle,
            expandingMenu: expected.openItems.contains(control), fallbackURL: route.url)
        guard fresh.ready, fresh.route?.site == route.site,
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
        let reqURL = source.string(route.webArea, .url)
        let reqURLValid = (reqURL == nil || reqURL == route.url)
        guard hitMatches, !source.limited, source.trusted, source.frontmostPID() == route.pid,
              source.element(app, .focusedWindow) == route.window,
              reqURLValid,
              (control.isMenu ? source.flag(control.node, .enabled) != false : source.flag(control.node, .enabled) == true),
              source.actions(control.node).contains(control.action) else {
            return .refused("The target is covered, changed, or no longer in the foreground.")
        }
        // Chromium's web accessibility actions are asynchronous and some Google
        // Sheets menu controls expose AXPress while failing to behave like a
        // literal click. After the exact target has been freshly revalidated and
        // hit-tested above, send ONE primary-button click at its center. There is
        // no fallback/retry: an uncertain delivery must be checked by the user.
        if NativeMenuPolicy.verifiedPointerBundles.contains(route.bundle) {
            return source.pointerClick(x: x, y: y) ? .requested : .uncertain
        }
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

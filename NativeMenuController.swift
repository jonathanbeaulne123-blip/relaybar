import Cocoa

@MainActor
final class NativeMenuController {
    typealias Snapshot = NativeMenuSnapshot<NativeAXNode>
    typealias Control = NativeControl<NativeAXNode>
    var onChange: (() -> Void)?
    var onStatus: ((String) -> Void)?
    private(set) var snapshot: Snapshot?
    private(set) var revision = 0
    private(set) var gate = NativeTapGate()
    private(set) var forceRoots = false
    var askBeforeActions = true
    private let queue = DispatchQueue(label: "local.relaybar.native-menus", qos: .userInitiated)
    private var work: NativeCancellation?
    private var working = false
    private var lastRead: Double = 0
    private var appID = ""
    private var prepared = Set<Int32>()
    // A menu request is navigation, not a script action. For a brief period
    // after a successful menu press, discovery may relax only popup-container
    // shape handling so lazily exposed web menu items can populate the bar.
    private var menuExpansionUntil: Double = 0
    private var lastMenuExpansion = "none"
    var controls: [Control] {
        guard let snapshot = snapshot else { return [] }
        return !forceRoots && !snapshot.openItems.isEmpty ? snapshot.openItems : snapshot.roots
    }
    var pendingLabel: String? {
        guard let p = gate.pending, controls.indices.contains(p.index) else { return nil }
        let c = controls[p.index]
        return c.path.isEmpty ? c.label : c.path + " › " + c.label
    }
    func observe(pid: Int32, bundle: String, enabled: Bool) {
        let key = "\(pid):\(bundle)"
        if !enabled || !NativeMenuPolicy.browserBundles.contains(bundle) {
            if snapshot != nil || working || gate.pending != nil { clear() }
            appID = key; return
        }
        if key != appID { clear(); appID = key }
        let now = ProcessInfo.processInfo.systemUptime
        if gate.expire(revision: revision, now: now) { onChange?() }
        guard !working, gate.executing == nil, now - lastRead >= 0.65 else { return }
        lastRead = now; working = true
        let token = NativeCancellation(); work = token
        let shouldPrepare = !prepared.contains(pid)
        // Only mark a process prepared after permission is granted; a refused
        // initial read must not prevent enabling it after the System Settings step.
        if RBBridge.accessibilityTrusted() { prepared.insert(pid) }
        if prepared.count > 32 { prepared = [pid] }
        let expandingMenu = now <= menuExpansionUntil
        let fallbackURL = ChromeTabBridge.shared.activeTab?.url
        queue.async { [weak self] in
            let source = NativeAXSource(cancellation: token)
            if shouldPrepare { source.prepareBrowser(pid: pid, bundle: bundle) }
            let result = NativeMenuEngine(source: source).scan(pid: pid, bundle: bundle, expandingMenu: expandingMenu, fallbackURL: fallbackURL)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.work === token, !token.cancelled else { return }
                self.working = false
                guard self.appID == key, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                let changed = self.snapshot.map { !result.sameContent(as: $0) } ?? true
                if changed {
                    let routeChanged = self.snapshot?.route != nil && self.snapshot?.route != result.route
                    self.revision += 1; self.gate.cancel()
                    let popupChanged = self.snapshot?.openItems != result.openItems && !result.openItems.isEmpty
                    if routeChanged || popupChanged { self.forceRoots = false }
                }
                self.snapshot = result
                if expandingMenu {
                    if !result.openItems.isEmpty {
                        self.lastMenuExpansion = "found \(result.openItems.count) controls"
                        self.menuExpansionUntil = 0
                    } else if result.failure != .none {
                        self.lastMenuExpansion = "scan failed: \(result.failure.explanation)"
                    } else {
                        self.lastMenuExpansion = "waiting for exposed menu controls"
                    }
                } else if self.menuExpansionUntil > 0 && now > self.menuExpansionUntil {
                    self.lastMenuExpansion = "expired with 0 controls"
                    self.menuExpansionUntil = 0
                }
                if changed { self.onChange?() }
            }
        }
    }
    func showMenus() {
        cancelInteraction(); forceRoots = true; revision += 1; onChange?()
    }
    func tap(index: Int, expectedRevision: Int) {
        guard gate.executing == nil, expectedRevision == revision, let snapshot = snapshot, snapshot.ready,
              controls.indices.contains(index), controls[index].enabled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.route?.pid else {
            onStatus?("Return to the Sheet and use its current Touch Bar controls."); return
        }
        // Cancel an in-progress read before reserving a user action. No queued
        // read callback can change this button binding while confirmation is up.
        if working { work?.cancel(); working = false }
        let control = controls[index]
        handle(gate.tap(index: index, revision: revision, now: ProcessInfo.processInfo.systemUptime,
                        isMenu: control.isMenu, ask: askBeforeActions))
    }
    func confirm(expectedRevision: Int) {
        guard gate.executing == nil else { return }
        guard expectedRevision == revision else { cancelInteraction(); onChange?(); return }
        if working { work?.cancel(); working = false }
        handle(gate.confirm(revision: revision, now: ProcessInfo.processInfo.systemUptime))
    }
    func cancelInteraction() {
        work?.cancel(); work = nil; working = false; gate.cancel()
        if menuExpansionUntil > 0 { lastMenuExpansion = "cancelled" }
        menuExpansionUntil = 0
    }
    func cancelConfirmation() { cancelInteraction(); revision += 1; onChange?() }
    func clear() {
        cancelInteraction(); snapshot = nil; forceRoots = false; menuExpansionUntil = 0; lastMenuExpansion = "none"; revision += 1; lastRead = 0
    }
    func suspend() { cancelInteraction() } // Preserve context for the screenshot page/report.
    private func handle(_ decision: NativeTapDecision) {
        switch decision {
        case .ignore: onChange?()
        case .confirm:
            onStatus?("Confirm on the Touch Bar to request this action. It may change data or send messages.")
            onChange?()
        case .execute(let request):
            guard let expected = snapshot, controls.indices.contains(request.index) else { gate.cancel(); return }
            let control = controls[request.index]
            let pointerDispatch = expected.route.map { NativeMenuPolicy.verifiedPointerBundles.contains($0.bundle) } ?? false
            let token = NativeCancellation(); work = token; working = true
            onChange?()
            queue.async { [weak self] in
                let source = NativeAXSource(cancellation: token)
                let result = NativeMenuEngine(source: source).request(control, expected: expected)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.work === token, !token.cancelled else { return }
                    self.working = false; self.gate.finish(request.id)
                    switch result {
                    case .requested:
                        if control.isMenu {
                            self.forceRoots = false
                            self.menuExpansionUntil = ProcessInfo.processInfo.systemUptime + 2.2
                            self.lastMenuExpansion = "waiting after menu request"
                            self.onStatus?(pointerDispatch ?
                                "Clicked “\(control.label)”. Reading its available tools…" :
                                "Opened “\(control.label)”. Reading its available tools…")
                        } else {
                            self.onStatus?(pointerDispatch ?
                                "Clicked “\(control.label)”. Check Sheets; script completion is not verified." :
                                "Requested “\(control.label)”. Check Sheets; script completion is not verified.")
                        }
                    case .refused(let message): self.onStatus?(message)
                    case .uncertain:
                        self.onStatus?("The browser did not confirm receipt. Do not repeat until you check the Sheet; it may already have acted.")
                    }
                    // Invalidate old targets after every attempted dispatch, then
                    // discover again read-only. Never automatically replay a click.
                    self.snapshot = nil; self.revision += 1; self.lastRead = 0
                    self.onChange?()
                }
            }
        }
    }
    var connectionReport: String {
        let s = snapshot
        return "RelayBar 0.9.1 · Native Sheets engine 0.5.4 · Menu Cascade + Lean Scan + Verified Click + Persistent Shell\n" +
            "Accessibility: \(RBBridge.accessibilityTrusted() ? "granted" : "not granted")\n" +
            "Browser bundle: \(s?.route?.bundle ?? "not identified")\n" +
            "Page kind: \(s?.route?.site.rawValue ?? "not identified")\n" +
            "Dispatch transport: \((s?.route.map { NativeMenuPolicy.verifiedPointerBundles.contains($0.bundle) } ?? false) ? "verified pointer click" : "accessibility action")\n" +
            "Top-level controls: \(s?.roots.count ?? 0)\nOpen-menu controls: \(s?.openItems.count ?? 0)\n" +
            "Visited UI nodes: \(s?.nodesVisited ?? 0)\n" +
            "Menu node budget: \(NativeMenuPolicy.maximumMenuNodes)\n" +
            "AX queries: \(s?.readMetrics.queries ?? 0) / \(NativeReadBudget.maximumQueries)\n" +
            "Scan duration ms: \(s?.readMetrics.milliseconds ?? 0) / 850\n" +
            "Metadata batches / fallbacks: \(s?.readMetrics.headerBatches ?? 0) / \(s?.readMetrics.headerFallbacks ?? 0)\n" +
            "Child pages / widest branch: \(s?.readMetrics.childPages ?? 0) / \(s?.readMetrics.widestBranch ?? 0)\n" +
            "Deepest UI level: \(s?.deepestLevel ?? 0) / \(NativeMenuPolicy.maximumDepth)\n" +
            "Skipped content / formatting branches: \(s?.prunedContentNodes ?? 0) / \(s?.prunedChromeNodes ?? 0)\n" +
            "Menu containers / candidates seen: \(s?.menuContainersSeen ?? 0) / \(s?.candidatesSeen ?? 0)\n" +
            "Last menu expansion: \(lastMenuExpansion)\n" +
            "Scan phase: \(s?.scanPhase ?? "not started")\n" +
            "Stop reason: \(s?.failure.explanation ?? "none")\n" +
            "Status: \(s?.status ?? "Waiting for an active browser")\n" +
            "No page URL, document title, cells, script source or screenshots are included in this report."
    }
}

import Cocoa

@main
@MainActor
struct RelayBarMain {
    static func main() {
        // Extension/native-messaging entry points have been removed in 0.5.
        if CommandLine.arguments.contains("--browser-native") || CommandLine.arguments.contains("--register-browser-host") {
            fputs("RelayBar uses native Accessibility; no browser extension is required or served.\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--diagnostics") {
            let result: [String: Any] = [
                "version": "1.0.0",
                "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                "overlaySelectorsAvailable": RBBridge.overlayAvailable(),
                "accessibilityGranted": RBBridge.accessibilityTrusted(),
                "overlayRenderingVerified": false,
                "notes": "Read-only diagnostic. No selection, clipboard, project data, or messages were read."
            ]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
            return
        }
        if CommandLine.arguments.contains("--button-families-self-test") {
            app.setActivationPolicy(.prohibited)
            exit(RelayAppDelegate().runButtonFamiliesSelfTest())
        }
        if CommandLine.arguments.contains("--pinned-chats-self-test") {
            app.setActivationPolicy(.prohibited)
            exit(PinnedChatsNativeChecks.run())
        }
        if CommandLine.arguments.contains("--context-stack-self-test") {
            app.setActivationPolicy(.prohibited)
            exit(ContextStackNativeChecks.run())
        }
        if CommandLine.arguments.contains("--claim-ledger-self-test") {
            app.setActivationPolicy(.prohibited)
            exit(ClaimLedgerNativeChecks.run())
        }
        if CommandLine.arguments.contains("--screenshot-self-test") {
            app.setActivationPolicy(.prohibited)
            exit(ScreenshotNativeChecks.run())
        }
        if CommandLine.arguments.contains("--smoke-test") {
            app.setActivationPolicy(.prohibited)
            let driver = TouchBarDriver()
            driver.update([.init(key: "test", title: "Test", help: "Native component smoke test", action: {})])
            let item = driver.touchBar(driver.bar, makeItemForIdentifier: NSTouchBarItem.Identifier("local.relaybar.test"))
            guard item is NSCustomTouchBarItem else { fputs("Native item construction failed\n", stderr); exit(1) }
            let (_, text) = textEditor(height: 100)
            text.string = "Smoke test"
            guard text.string == "Smoke test" else { exit(1) }
            print("PASS: native Touch Bar item and text editor constructed. This does not verify hardware rendering or app routing.")
            return
        }
        let delegate = RelayAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class RelayAppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSTextFieldDelegate, NSWindowDelegate {
    private var configuration = AppConfiguration()
    private var store: LocalStore?
    private var configurationWritable = true
    private var capture = Capture.empty
    private var draft: PromptDraft?
    private var currentAction: PromptAction = .nextSlice
    private var lastExternalApp: NSRunningApplication?
    private var suppressEdits = false
    private var shellState = PersistentShellState(enabled: UserDefaults.standard.object(forKey: "persistentShell.enabled") as? Bool ?? true)
    private var overlayEnabled = false
    private var persistentPauseMenuItem: NSMenuItem?
    private var returnRelayMenuItem: NSMenuItem?
    private var macTouchBarMenuItem: NSMenuItem?
    private var loginItemMenuItem: NSMenuItem?
    private var loginEnabled = UserDefaults.standard.object(forKey: "persistentShell.loginEnabled") as? Bool ?? true
    private var observer: NSObjectProtocol?
    private let bridge = RBBridge()
    private let panelBar = TouchBarDriver()
    private let overlayBar = TouchBarDriver()
    private var panel: RelayPanel!
    private var statusItem: NSStatusItem!
    private var targetPicker = NSPopUpButton()
    private var projectPicker = NSPopUpButton()
    private var modePicker = NSPopUpButton()
    private var actionPicker = NSPopUpButton()
    private var taskField = NSTextField()
    private var referenceView: NSTextView!
    private var draftView: NSTextView!
    private var originLabel = label("No reference captured", secondary: true)
    private var statusLabel = label("Ready. Compose locally; review before copying.", secondary: true)
    private var contextLabel = label("Auto · no reference", secondary: true)
    private var draftLabel = label("DRAFT · nothing has been sent", size: 11, weight: .semibold)
    private var mirror = NSStackView()
    private var prefillButton: ActionButton!
    private var overlayMenuItem: NSMenuItem!
    private var followMenuItem: NSMenuItem!
    private var desktopMenuItem: NSMenuItem!
    private var screenshotShelf: ScreenshotShelfController?
    private var screenshotPresentation = ScreenshotPresentationState()
    private var realityTimeline: RealityTimelinePanel?
    private var realityFilesPanel: RealityFileChangesPanel?
    private let sessionJournal = SessionJournal()
    private var lastRealityRoot: String?
    private var realitySelectionID: UUID?
    private var screenshotArrivalDate: Date = .distantPast
    private var showingScreenshots: Bool { screenshotPresentation.page == .screenshots }
    private let autoOpenKey = "screenshotShelf.autoOpen"
    private var screenshotAutoOpenMenuItem: NSMenuItem?
    private var screenshotLabel = label("Set up your screenshot folder to keep the five most recent images.", secondary: true)
    private var screenshotWatchMenuItem: NSMenuItem?
    private var screenshotPageMenuItem: NSMenuItem?
    private var appAwareEnabled = UserDefaults.standard.object(forKey: "appAware.enabled") as? Bool ?? true
    private var appAwareMenuItem: NSMenuItem?
    private var appContextMenuItem: NSMenuItem?
    private var appContextLabel = label("Active app: waiting", secondary: true)
    private var contextTimer: Timer?
    private let nativeMenus = NativeMenuController()
    private var nativeMenusEnabled = UserDefaults.standard.object(forKey: "nativeMenus.enabled") as? Bool ?? true
    private var lastActiveURL = ""
    private var nativeAskActions = UserDefaults.standard.object(forKey: "nativeMenus.askActions") as? Bool ?? true
    private var nativePauseMenuItem: NSMenuItem?
    private var nativeAskMenuItem: NSMenuItem?
    private var lastKnownNativeRoute: NativeRoute<NativeAXNode>?
    private var lastNativeRevision = -1
    private var liveBundle = ""
    private var liveProfile = "assistant"
    private var liveAppName = "RelayBar"
    private var scriptPage = 0
    private var manualAITools = false
    private let chromeBridge = ChromeTabBridge.shared
    private let sheetsTools = SheetsToolsController.shared
    private let youTube = YouTubeController.shared
    private var tabPageIndex = 0
    private var contextStack: ContextStackController?
    private var claimLedger: ClaimLedgerController?
    private var navigation = RelayNavigation()
    private var familyPathLabel = label("Home", size: 12, weight: .semibold)
    private var showingContextStack = false
    private var showingPinnedChats = false
    private var pinnedChats: PinnedChatsController?
    private var stackCollectMenuItem: NSMenuItem?
    private var stackSummaryMenuItem: NSMenuItem?
    // Your Sites, the local Toolbox and the page→prompt reference. All three are
    // local engines; AppMain only decides where their controls appear.
    private let siteControls = SiteControlsController()
    private let toolbox = ToolboxController()
    private var siteRulesEditor: SiteRulesEditor?
    private var pageContextMenuItems: [PageContextMode: NSMenuItem] = [:]
    private var pageContextMode: PageContextMode =
        PageContextMode(rawValue: UserDefaults.standard.string(forKey: "pageContext.mode") ?? "") ?? .link
    private var quickActionRunner: ActionRunner?
    private var actionOutputPanel: ActionOutputPanel?
    private var pluginManager: PluginManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var startupError: String?
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            store = try LocalStore(directory: support.appendingPathComponent("RelayBar", isDirectory: true))
            configuration = try store!.loadConfiguration()
        } catch {
            configurationWritable = false
            startupError = "Local configuration could not be loaded: \(error.localizedDescription)\n\nThe original data is untouched. This session uses temporary starter settings. Fix or rename the configuration file before saving new settings."
        }
        screenshotPresentation.setAutoOpenEnabled(UserDefaults.standard.object(forKey: autoOpenKey) as? Bool ?? true)
        screenshotPresentation.showTools() // First launch opens the five families, not an empty screenshot shelf.
        shellState.enabled = UserDefaults.standard.object(forKey: "persistentShell.enabled") as? Bool ?? true
        overlayEnabled = shellState.relayVisible
        lastExternalApp = NSWorkspace.shared.frontmostApplication
        if loginEnabled { try? PersistentShellMac.setLoginItemEnabled(true) }
        buildMenu()
        buildPanel()
        realityTimeline = RealityTimelinePanel()
        realityFilesPanel = RealityFileChangesPanel()
        realityTimeline?.onRestore = { [weak self] reality in self?.restoreReality(reality) }
        realityTimeline?.onFork = { [weak self] reality in self?.forkRealityFromSnapshot(reality) }
        realityTimeline?.onSelect = { [weak self] reality in
            self?.realitySelectionID = reality.id
            self?.setStatus("Selected \(reality.name). Review the Git and RelayBar state before restoring.")
        }
        realityTimeline?.onWhatChanged = { [weak self] reality in self?.showWhatChanged(for: reality) }
        realityTimeline?.onFilesChanged = { [weak self] reality in self?.showFileChanges(for: reality) }
        realityFilesPanel?.onApply = { [weak self] source, target, hunks, paths in self?.applySelectedChanges(from: source, to: target, hunks: hunks, paths: paths) }
        sessionJournal.startSession()
        contextStack = ContextStackController(projectID: configuration.selectedProject.id, projectName: configuration.selectedProject.name)
        contextStack?.onChange = { [weak self] in self?.refreshStackUI() }
        contextStack?.onReturnToWork = { [weak self] in self?.hidePanel() }
        // The claim ledger keeps its own store access so a receipt is written
        // where checkpoints and realities already live.
        claimLedger = ClaimLedgerController(
            projectID: configuration.selectedProject.id,
            projectName: configuration.selectedProject.name,
            storeProvider: { [weak self] in self?.store }
        )
        claimLedger?.verifyCommands = configuration.verifyCommands
        claimLedger?.onChange = { [weak self] in self?.refreshClaimLedgerUI() }
        claimLedger?.onJournal = { [weak self] kind in self?.sessionJournal.record(kind, app: "RelayBar") }
        claimLedger?.onReturnToWork = { [weak self] in self?.hidePanel() }
        claimLedger?.onVerifyCommandsChanged = { [weak self] commands in
            guard let self = self else { return }
            self.configuration.verifyCommands = commands
            self.saveConfiguration()
        }
        pinnedChats = PinnedChatsController()
        pinnedChats?.onChange = { [weak self] in
            guard let self = self else { return }
            self.rebuildBars(); self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
        }
        pinnedChats?.onSwitchProvider = { [weak self] provider in self?.openPinnedAssistant(provider) }
        refreshControls()
        if let store = store {
            screenshotShelf = ScreenshotShelfController(directory: store.directory.appendingPathComponent("ScreenshotShelf", isDirectory: true))
            screenshotShelf?.onChange = { [weak self] didAdd in
                guard let self = self else { return }
                if didAdd {
                    self.sessionJournal.record(.screenshotTaken(index: self.screenshotShelf?.entries.count ?? 0), app: self.liveAppName)
                    self.recordAutomaticReality("Screenshot milestone")
                    self.screenshotArrivalDate = Date()
                    self.nativeMenus.cancelInteraction()
                    self.shellState.returnToRelayBar()
                    self.overlayEnabled = true
                }
                let ticket = didAdd ? self.screenshotPresentation.screenshotAdded() : nil
                // New screenshots keep their established presentation priority.
                // Stack text and collection state are retained, not discarded.
                if ticket != nil {
                    self.navigation.screenshotArrived(autoOpen: true)
                    self.showingContextStack = false; self.stopPinnedChats()
                }
                self.refreshScreenshotUI()
                if let ticket = ticket { self.scheduleScreenshotRecovery(ticket: ticket) }
            }
        } else {
            screenshotLabel.stringValue = "Screenshot storage is unavailable. Existing files were not changed."
        }
        bridge.launcherHandler = { [weak self] in self?.returnToRelayBar(showPanel: true) }
        let hotkeyOK = bridge.registerLauncherHotKey()
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                     object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            DispatchQueue.main.async { [weak self] in self?.activeApplicationChanged(app) }
        }
        nativeMenus.askBeforeActions = nativeAskActions
        nativeMenus.onChange = { [weak self] in
            guard let self = self else { return }
            self.refreshAppContext(); self.rebuildBars()
            self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
        }
        chromeBridge.onChange = { [weak self] in
            guard let self = self else { return }
            self.refreshAppContext()
            self.rebuildBars()
            self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
        }
        youTube.onStateChange = { [weak self] in
            guard let self = self else { return }
            self.rebuildBars()
            self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
        }
        wireSiteControls()
        nativeMenus.onStatus = { [weak self] message in self?.setStatus(message) }
        contextTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshAppContext() }
        }
        if !RBBridge.accessibilityTrusted() {
            RBBridge.requestAccessibility()
        }
        refreshAppContext()
        rebuildBars()
        refreshShellMenuState()
        updateOverlay(for: NSWorkspace.shared.frontmostApplication)
        if !hotkeyOK { setStatus("The shortcut is already in use or unavailable. Open RelayBar from its RB menu-bar icon.") }
        if let message = startupError { showError(message) }
        else if !UserDefaults.standard.bool(forKey: "nativeMenus.introduced") {
            setStatus("RelayBar is persistent. Enable native controls from RB → Settings → Native controls when you want Sheets and pinned-chat detection.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        contextTimer?.invalidate(); contextTimer = nil
        nativeMenus.clear()
        screenshotPresentation.cancelRecovery()
        screenshotShelf?.stopForTermination()
        contextStack?.stopForTermination()
        pinnedChats?.stopForTermination()
        claimLedger?.stopForTermination()
        bridge.dismissOverlay()
        bridge.unregisterLauncherHotKey()
        if let observer = observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        sessionJournal.endSession()
        capture = .empty; draft = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePanel()
        return false
    }

    private func buildMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = self; menu.addItem(item); return item
        }
        _ = add("Open RelayBar   ⌃⌥⌘Space", #selector(showFromMenu))
        _ = add("Edit Site Rules…", #selector(editSiteRulesFromMenu))
        _ = add("Local Toolbox", #selector(showToolboxFromMenu))
        _ = add("Fork Current Reality…", #selector(forkCurrentReality))
        _ = add("Show Reality Timeline", #selector(showRealityTimeline))
        returnRelayMenuItem = add("Return RelayBar Touch Bar", #selector(returnRelayBarFromMenu))
        macTouchBarMenuItem = add("Use macOS Touch Bar", #selector(useMacTouchBarFromMenu))
        persistentPauseMenuItem = add("Pause Persistent Touch Bar", #selector(togglePersistentShellPause))
        loginItemMenuItem = add("Launch RelayBar at Login", #selector(toggleLaunchAtLogin))
        menu.addItem(.separator())
        menu.addItem(FamilyMenuItem("Home — all button families") { [weak self] in self?.navigate(to: .home) })
        menu.addItem(.separator())
        for item in RelayHierarchy.items(on: .home) {
            if case .page(let page) = item { menu.addItem(familyMenu(page)) }
        }
        menu.addItem(.separator())
        appContextMenuItem = NSMenuItem(title: "Active app: waiting", action: nil, keyEquivalent: "")
        if let item = appContextMenuItem { menu.addItem(item) }
        _ = add("Quit RelayBar", #selector(quit), key: "q")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "RB"
        statusItem.button?.toolTip = "RelayBar — native app-aware controls"
        statusItem.menu = menu

        // Standard Edit menu is necessary for Cmd-C/V/A inside a programmatic AppKit app.
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit RelayBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationMenu.addItem(quitItem); applicationItem.submenu = applicationMenu; main.addItem(applicationItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        editItem.submenu = editMenu; main.addItem(editItem); NSApp.mainMenu = main
    }

    private func buildPanel(selfTest: Bool = false) {
        panel = RelayPanel(contentRect: NSRect(x: 0, y: 0, width: 940, height: 790),
                           styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        panel.title = "RelayBar · Button Families"
        panel.minSize = NSSize(width: 820, height: 550)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.onEscape = { [weak self] in
            guard let self = self else { return }
            if self.navigation.page == .home { self.hidePanel() } else { self.navigateBack() }
        }
        panel.touchBar = panelBar.bar
        panel.center()
        if !selfTest { panel.setFrameAutosaveName("RelayBarPanel") }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let document = FlippedDocumentView()
        scroll.documentView = document
        panel.contentView = scroll
        document.translatesAutoresizingMaskIntoConstraints = false
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        let body = NSStackView()
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 12
        body.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            body.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            body.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])
        func full(_ view: NSView) {
            body.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        body.addArrangedSubview(label("RELAYBAR", size: 26, weight: .bold))
        body.addArrangedSubview(label("Native app controls. Local screenshots. No browser extension.", size: 14, secondary: true))
        full(appContextLabel)

        body.addArrangedSubview(label("WORKSPACE · PROJECT & DESTINATION", size: 11, weight: .semibold))
        targetPicker.addItems(withTitles: AssistantTarget.allCases.map(\.rawValue))
        modePicker.addItems(withTitles: WorkflowMode.allCases.map(\.rawValue))
        targetPicker.target = self; targetPicker.action = #selector(targetChanged)
        projectPicker.target = self; projectPicker.action = #selector(projectChanged)
        modePicker.target = self; modePicker.action = #selector(modeChanged)
        projectPicker.widthAnchor.constraint(equalToConstant: 150).isActive = true
        full(row([label("To"), targetPicker, label("Project"), projectPicker, label("Mode"), modePicker,
                  ActionButton("Edit brief…") { [weak self] in self?.editProject(isNew: false) }]))

        mirror.orientation = .horizontal; mirror.spacing = 6; mirror.alignment = .centerY
        mirror.wantsLayer = true; mirror.layer?.cornerRadius = 10
        mirror.layer?.backgroundColor = NSColor.black.cgColor
        mirror.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        full(familyPathLabel)
        full(mirror)
        full(screenshotLabel)
        full(contextLabel)

        let captureButton = ActionButton("Capture selection", help: "Read only selected text from the last active app; optional Accessibility permission.") { [weak self] in self?.captureSelection() }
        body.addArrangedSubview(label("CONTEXT · CAPTURE", size: 11, weight: .semibold))
        full(row([captureButton,
                  ActionButton("Use clipboard", help: "Read plain text from the clipboard once, only on this click.") { [weak self] in self?.captureClipboard() },
                  ActionButton("Clear session…") { [weak self] in self?.confirmClearSession() }, originLabel]))
        let (referenceScroll, reference) = textEditor(height: 115)
        referenceView = reference; reference.delegate = self; reference.touchBar = panelBar.bar
        reference.setAccessibilityLabel("Explicit reference text; editable and not automatically saved")
        full(referenceScroll)

        taskField.placeholderString = "Specific task or next step — optional"
        taskField.font = .systemFont(ofSize: 13); taskField.delegate = self
        taskField.setAccessibilityLabel("Specific task or next step")
        full(taskField)

        body.addArrangedSubview(label("PROMPTING · COMPOSE", size: 11, weight: .semibold))
        actionPicker.addItems(withTitles: PromptAction.allCases.map(\.title))
        actionPicker.target = self; actionPicker.action = #selector(actionChanged)
        full(row([label("Action"), actionPicker,
                  ActionButton("Compose draft") { [weak self] in self?.composeSelected() },
                  ActionButton("Prompting ›") { [weak self] in self?.navigate(to: .prompting) }]))
        full(draftLabel)
        let (draftScroll, draftText) = textEditor(height: 195, mono: true)
        draftView = draftText; draftText.delegate = self; draftText.touchBar = panelBar.bar
        draftText.setAccessibilityLabel("Review and edit the generated draft before copying or opening an assistant")
        full(draftScroll)
        prefillButton = ActionButton("Prefill Claude…", help: "Explicitly open a NEW Claude chat with this draft. Never sends it.") { [weak self] in self?.prefillClaude() }
        full(row([
            ActionButton("Copy draft") { [weak self] in self?.copyDraft() },
            ActionButton("Copy + Open") { [weak self] in self?.copyAndOpen() },
            prefillButton,
            ActionButton("Save checkpoint…") { [weak self] in self?.saveCheckpoint() }
        ]))
        full(statusLabel)
        full(label("⌃⌥⌘Space opens this panel. Screenshot watching is opt-in. Context Stack collects only after Start and stays in memory. Reference capture is on-demand; drafts stay in memory unless checkpointed. Esc goes Back; at Home it hides the panel. The RB menu remains available.", size: 11, secondary: true))
    }

    private func refreshControls() {
        guard panel != nil else { return }
        contextStack?.syncProject(id: configuration.selectedProject.id, name: configuration.selectedProject.name)
        suppressEdits = true
        targetPicker.selectItem(withTitle: configuration.target.rawValue)
        projectPicker.removeAllItems(); projectPicker.addItems(withTitles: configuration.projects.map(\.name))
        projectPicker.selectItem(at: configuration.projects.firstIndex(where: { $0.id == configuration.selectedProjectID }) ?? 0)
        modePicker.selectItem(withTitle: configuration.mode.rawValue)
        actionPicker.selectItem(withTitle: currentAction.title)
        followMenuItem.state = configuration.followDesktopAssistant ? .on : .off
        desktopMenuItem.state = configuration.preferDesktop ? .on : .off
        overlayMenuItem.state = overlayEnabled ? .on : .off
        let kind = ContextEngine.classify(capture.text)
        contextLabel.stringValue = "\(configuration.mode.rawValue) · suggested from \(kind.rawValue) text · \(capture.text.count.formatted()) / 24,000 reference characters · drafts only"
        if capture.text.isEmpty { originLabel.stringValue = "No reference captured" }
        else {
            let time = DateFormatter.localizedString(from: capture.capturedAt, dateStyle: .none, timeStyle: .short)
            originLabel.stringValue = "\(capture.origin) · \(time)"
        }
        prefillButton.isEnabled = configuration.target == .claude
        draftLabel.stringValue = draft == nil ? "DRAFT · nothing has been sent" : "DRAFT → \(draft!.target.rawValue.uppercased()) · \(currentAction.title.uppercased()) · review before copying"
        suppressEdits = false
        rebuildBars()
    }

    private func screenshotSlots() -> [TouchBarDriver.Slot] {
        var slots: [TouchBarDriver.Slot] = [
            .init(key: "shotTools", title: appAwareEnabled && liveProfile == "sheets" ? "Sheets" : "Tools", help: "Return to this app’s contextual buttons", width: 56) { [weak self] in self?.showToolsPage() }
        ]
        slots.append(.init(key: "stack-open", title: "Stack", help: "Open the text Context Stack", width: 52) { [weak self] in self?.showStackFromMenu() })
        slots.append(pinnedChatsSlot())
        let entries = screenshotShelf?.entries ?? []
        for index in 0..<ScreenshotPolicy.capacity {
            if index < entries.count {
                let entry = entries[index]
                let image = screenshotShelf?.thumbnails[entry.id]?.copy() as? NSImage
                if let image = image {
                    let factor = min(48 / max(1, image.size.width), 28 / max(1, image.size.height))
                    image.size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
                    image.isTemplate = false
                }
                let date = DateFormatter.localizedString(from: entry.capturedAt, dateStyle: .short, timeStyle: .short)
                let title = screenshotShelf?.copiedID == entry.id ? "✓" : "\(index + 1)"
                slots.append(.init(key: "shot-\(entry.id.uuidString)", title: title,
                    help: "Screenshot \(index + 1), \(entry.name), \(date), \(entry.width) × \(entry.height). Tap to copy the image.",
                    image: image, width: 78) { [weak self] in self?.copyScreenshot(id: entry.id) })
            } else {
                let setup = index == 0 && screenshotShelf?.watching != true
                slots.append(.init(key: "emptyShot\(index)", title: setup ? "Set up" : "—",
                    help: setup ? "Choose the folder where macOS saves screenshots" : "Empty screenshot slot \(index + 1)",
                    isEnabled: setup, width: 78) { [weak self] in self?.chooseScreenshotFolder() })
            }
        }
        slots.append(.init(key: "hide", title: "×", help: "Hide panel and disable the experimental cross-app bar", width: 32) { [weak self] in self?.disableOverlay(); self?.hidePanel() })
        return slots
    }

    private func rebuildBars() {
        let slots = familySlots()
        familyPathLabel.stringValue = navigation.page.breadcrumb
        let previousIdentifiers = overlayBar.bar.defaultItemIdentifiers
        panelBar.update(slots); overlayBar.update(slots)
        panel?.touchBar = panelBar.bar
        referenceView?.touchBar = panelBar.bar
        draftView?.touchBar = panelBar.bar
        contextStack?.bindTouchBar(panelBar.bar)
        if previousIdentifiers != overlayBar.bar.defaultItemIdentifiers {
            screenshotPresentation.layoutChanged()
        }
        for view in mirror.arrangedSubviews { mirror.removeArrangedSubview(view); view.removeFromSuperview() }
        for slot in slots where slot.key != TouchBarDriver.flexibleSpaceKey {
            let button = ActionButton(slot.title, help: slot.help, handler: slot.action)
            button.bezelStyle = .rounded; button.isEnabled = slot.isEnabled
            button.image = slot.image; button.imagePosition = slot.image == nil ? .noImage : .imageLeft
            button.imageScaling = .scaleProportionallyDown
            if let width = slot.width { button.widthAnchor.constraint(equalToConstant: width).isActive = true }
            if slot.key == "target" { button.contentTintColor = .systemIndigo }
            mirror.addArrangedSubview(button)
        }
    }

    private func refreshScreenshotUI() {
        screenshotLabel.stringValue = screenshotShelf?.message ?? "Screenshot storage is unavailable."
        screenshotPageMenuItem?.state = showingScreenshots ? .on : .off
        screenshotAutoOpenMenuItem?.state = screenshotPresentation.autoOpenEnabled ? .on : .off
        screenshotWatchMenuItem?.title = screenshotShelf?.watching == true ? "Stop screenshot collection" : "Start screenshot collection"
        statusItem?.button?.toolTip = "RelayBar · " + screenshotLabel.stringValue
        rebuildBars()
        updateOverlay(for: NSWorkspace.shared.frontmostApplication)
    }
    @objc private func editSiteRulesFromMenu() { editSiteRules() }
    @objc private func showToolboxFromMenu() {
        if !shellState.relayVisible { returnToRelayBar(showPanel: false) }
        navigate(to: .toolbox)
    }
    @objc private func showScreenshotsFromMenu() {
        if !shellState.relayVisible { returnToRelayBar(showPanel: false) }
        navigate(to: .screenshots)
    }
    private func showToolsPage() {
        screenshotArrivalDate = .distantPast
        navigate(to: .home)
    }
    @objc private func toggleScreenshotAutoOpen() {
        screenshotPresentation.setAutoOpenEnabled(!screenshotPresentation.autoOpenEnabled)
        UserDefaults.standard.set(screenshotPresentation.autoOpenEnabled, forKey: autoOpenKey)
        refreshScreenshotUI()
    }
    private func copyScreenshot(id: UUID) {
        // The user has reached the viewer; don't re-present it during their tap.
        screenshotArrivalDate = .distantPast
        screenshotPresentation.cancelRecovery()
        screenshotShelf?.copy(id: id)
    }
    private func scheduleScreenshotRecovery(ticket: UUID) {
        for delay in ScreenshotPresentationState.recoveryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.overlayEnabled,
                      self.screenshotPresentation.requestRecovery(ticket: ticket) else { return }
                // No activation, key injection or window opening. Check the live
                // frontmost app again: capture UI may have displaced the modal bar.
                self.shellState.returnToRelayBar()
                self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
            }
        }
    }
    @objc private func chooseScreenshotFolder() {
        navigate(to: .screenshotOptions)
        showPanel(); screenshotShelf?.chooseFolder(); refreshScreenshotUI()
    }
    @objc private func toggleScreenshotWatching() {
        if screenshotShelf?.folderURL == nil { showPanel() }
        screenshotShelf?.toggleWatching()
    }
    @objc private func addScreenshotClipboard() { screenshotShelf?.addClipboardImage() }
    @objc private func clearScreenshotShelf() { showPanel(); screenshotShelf?.clear() }

    private func saveConfiguration() {
        guard configurationWritable, let store = store else { setStatus("Settings are temporary: local storage could not be loaded. Existing data remains untouched."); return }
        do { try store.saveConfiguration(configuration) }
        catch { showError("Could not save settings: \(error.localizedDescription)") }
    }

    private func ownApp(_ app: NSRunningApplication) -> Bool { app.processIdentifier == ProcessInfo.processInfo.processIdentifier }

    private func detectedAssistant(_ app: NSRunningApplication) -> AssistantTarget? {
        for target in AssistantTarget.allCases {
            if let path = configuration.appPaths[target.rawValue], app.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path { return target }
        }
        // Desktop detection uses explicit identities. Native browser routing
        // uses the exposed page URL, never a window-title guess.
        let name = (app.localizedName ?? "").lowercased()
        let bundle = app.bundleIdentifier ?? ""
        if name == "chatgpt" || name == "chatgpt classic" || bundle == "com.openai.chat" { return .chatgpt }
        if name == "claude" || bundle == "com.anthropic.claudefordesktop" { return .claude }
        return nil
    }

    private func activeApplicationChanged(_: NSRunningApplication) {
        // Notifications arrive asynchronously; route against the current app,
        // not an earlier activation that may already have been superseded.
        guard let app = NSWorkspace.shared.frontmostApplication else { bridge.dismissOverlay(); return }
        guard !ownApp(app) else { nativeMenus.suspend(); bridge.dismissOverlay(); return }
        nativeMenus.suspend()
        if isCaptureHelper(app) { updateOverlay(for: app); return }
        lastExternalApp = app
        // Never silently reroute an already composed draft.
        if configuration.followDesktopAssistant, draft == nil,
           let target = detectedAssistant(app), target != configuration.target {
            configuration.target = target; saveConfiguration(); refreshControls()
        }
        refreshAppContext()
        updateOverlay(for: app)
    }

    private func updateOverlay(for app: NSRunningApplication?) {
        let eligible = app.map { shellState.shouldPresent(frontmostIsRelay: ownApp($0), captureHelper: isCaptureHelper($0)) } ?? false
        let shellActive = overlayEnabled && shellState.relayVisible
        switch screenshotPresentation.overlayAction(overlayEnabled: shellActive, eligibleApp: eligible) {
        case .dismiss:
            bridge.dismissOverlay(); return
        case .reopen:
            // The original bridge intentionally caches an identical NSTouchBar.
            // Explicitly dismiss before presenting so a new capture can recover
            // a bar displaced by Screenshot even when object identity is unchanged.
            bridge.dismissOverlay()
        case .present:
            break
        }
        if bridge.presentOverlay(overlayBar.bar) {
            screenshotPresentation.overlayPresented()
        } else {
            shellState.pause()
            overlayEnabled = false
            screenshotPresentation.overlayDisabled()
            refreshShellMenuState()
            setStatus("RelayBar could not present the persistent Touch Bar on this macOS build. The stock macOS Touch Bar remains available; resume from the RB menu to retry.")
        }
    }

    private func showPanel() {
        screenshotPresentation.cancelRecovery()
        if let front = NSWorkspace.shared.frontmostApplication, !ownApp(front) { lastExternalApp = front }
        bridge.dismissOverlay()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanel() {
        panel.orderOut(nil)
        if let previous = lastExternalApp, !previous.isTerminated {
            previous.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func invalidateDraft(_ message: String? = nil) {
        draft = nil
        suppressEdits = true; draftView.string = ""; suppressEdits = false
        if let message = message { setStatus(message) }
    }

    private func clearSession() {
        capture = .empty
        suppressEdits = true; referenceView.string = ""; taskField.stringValue = ""; suppressEdits = false
        invalidateDraft("Session text cleared from RelayBar. Existing checkpoints and the system clipboard are unchanged.")
        refreshControls()
    }

    private func setTarget(_ target: AssistantTarget) {
        guard target != configuration.target else { return }
        configuration.target = target
        invalidateDraft("Destination changed. Compose a fresh draft for \(target.rawValue).")
        saveConfiguration(); refreshControls()
    }
    private func cycleTarget() { setTarget(configuration.target.other) }
    private func cycleProject() {
        let index = configuration.projects.firstIndex(where: { $0.id == configuration.selectedProjectID }) ?? 0
        changeProject(to: configuration.projects[(index + 1) % configuration.projects.count].id)
    }
    private func changeProject(to id: String) {
        guard id != configuration.selectedProjectID else { return }
        configuration.selectedProjectID = id
        claimLedger?.syncProject(id: id, name: configuration.selectedProject.name)
        clearSession(); saveConfiguration(); refreshControls()
        setStatus("Switched to \(configuration.selectedProject.name). The previous session reference and draft were cleared to prevent cross-project leakage.")
    }

    private func applyCapture(_ text: String, origin: String) {
        let candidate = Capture(text: text, origin: origin)
        do {
            try Limits.validate(capture: candidate, task: taskField.stringValue)
            capture = candidate
            suppressEdits = true; referenceView.string = text; suppressEdits = false
            invalidateDraft()
            refreshControls()
            showPanel()
            setStatus("Captured only the supplied passage. Choose an action, review the draft, then copy or open.")
        } catch { showError(error.localizedDescription) }
    }

    private func captureSelection() {
        let front = NSWorkspace.shared.frontmostApplication
        let source = front.flatMap { ownApp($0) ? nil : $0 } ?? lastExternalApp
        guard let source = source, !source.isTerminated, !ownApp(source) else {
            showError("Select text in ChatGPT, Claude, a browser, or editor first. You can also paste text into the reference box."); return
        }
        let result = RBBridge.selectedText(forPID: source.processIdentifier)
        if let text = result["text"] { applyCapture(text, origin: String((source.localizedName ?? "Selected text").prefix(250))) }
        else {
            showPanel()
            setStatus(result["error"] ?? "No selected text was available.")
            if !RBBridge.accessibilityTrusted() {
                let alert = NSAlert()
                alert.messageText = "Enable selected-text capture?"
                alert.informativeText = "RelayBar asks macOS for the currently selected text only when you press Capture. It does not read whole conversations. Accessibility permission is optional; Copy → Use clipboard works without it."
                alert.addButton(withTitle: "Use clipboard instead"); alert.addButton(withTitle: "Enable Accessibility")
                if alert.runModal() == .alertSecondButtonReturn { RBBridge.requestAccessibility() }
            }
        }
    }

    private func captureClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { showError("The clipboard does not contain plain text."); return }
        applyCapture(text, origin: "Clipboard (explicit import; source unknown)")
    }

    private func performAction(_ action: PromptAction) {
        currentAction = action
        if action == .handoff { configuration.target = configuration.target.other; saveConfiguration() }
        composeSelected()
    }

    private func composeSelected() {
        do {
            // A ledger for a different project is never attached: a receipt
            // describes one repository at one commit.
            let attachedLedger = claimLedger?.ledger.flatMap { $0.projectID == configuration.selectedProject.id ? $0 : nil }
            draft = try PromptEngine.compose(action: currentAction, project: configuration.selectedProject,
                                             capture: capture, task: taskField.stringValue, target: configuration.target,
                                             ledger: attachedLedger)
            suppressEdits = true; draftView.string = draft!.text; suppressEdits = false
            navigate(to: .draft)
            refreshControls(); showPanel()
            sessionJournal.record(.note(text: "Prepared \(currentAction.title) draft"), app: liveAppName)
            recordAutomaticReality("After \(currentAction.title)")
            setStatus("Draft prepared locally for \(configuration.target.rawValue). Nothing was copied, opened, or sent.")
        } catch { showError(error.localizedDescription) }
    }

    private func askAIAboutYouTube() {
        guard let s = youTube.session else { return }
        let quote = youTube.transcriptEntries.last(where: { $0.timestamp <= s.currentTime })?.text ?? ""
        let quotePart = quote.isEmpty ? "" : "\nExcerpt at \(s.formattedTime): “\(quote)”"
        let prompt = """
        I am watching: "\(s.cleanTitle)" at \(s.formattedTime) (\(s.url)&t=\(Int(s.currentTime))s).\(quotePart)

        Can you explain what is being discussed here and key takeaways?
        """
        currentAction = .explain
        draft = PromptDraft(text: prompt, action: .explain, projectID: configuration.selectedProjectID, target: configuration.target, createdAt: Date())
        suppressEdits = true
        draftView.string = prompt
        suppressEdits = false
        navigate(to: .draft)
        refreshControls()
        showPanel()
        setStatus("YouTube query prepared locally for \(configuration.target.rawValue).")
    }

    private func currentDraft() throws -> PromptDraft {
        guard var result = draft, !draftView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayError.invalid("Compose a draft first.")
        }
        guard draftView.string.count <= Limits.draft else { throw RelayError.invalid("The edited draft exceeds 64,000 characters.") }
        guard result.projectID == configuration.selectedProjectID, result.target == configuration.target else {
            throw RelayError.invalid("The draft destination or project changed. Compose it again.")
        }
        result.text = draftView.string
        return result
    }

    @discardableResult private func putOnClipboard(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
    private func copyDraft() {
        do {
            let draft = try currentDraft()
            guard putOnClipboard(draft.text) else { throw RelayError.invalid("The clipboard could not be written.") }
            setStatus("Draft copied. The clipboard now contains your packet. Nothing was sent.")
        } catch { showError(error.localizedDescription) }
    }

    private func appURL(for target: AssistantTarget) -> URL? {
        if let path = configuration.appPaths[target.rawValue], FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: { detectedAssistant($0) == target }), let url = running.bundleURL { return url }
        let identifiers = target == .chatgpt ? ["com.openai.chat"] : ["com.anthropic.claudefordesktop"]
        for identifier in identifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) { return url }
        }
        let names = target == .chatgpt ? ["ChatGPT.app", "ChatGPT Classic.app"] : ["Claude.app"]
        for folder in ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path] {
            for name in names {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    private func copyAndOpen() {
        do {
            let packet = try currentDraft()
            guard putOnClipboard(packet.text) else { throw RelayError.invalid("The clipboard could not be written.") }
            if configuration.preferDesktop, let url = appURL(for: packet.target) {
                let options = NSWorkspace.OpenConfiguration(); options.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: options) { [weak self] _, error in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if let error = error { self.showError("The draft was copied but the app could not open: \(error.localizedDescription). Paste it manually, or choose the correct application from the RB menu.") }
                        else { self.panel.orderOut(nil); self.setStatus("Copied for \(packet.target.rawValue). Click the desired chat's composer and press ⌘V. Nothing was sent.") }
                    }
                }
            } else {
                guard NSWorkspace.shared.open(packet.target.webURL) else { throw RelayError.invalid("The draft was copied but the browser could not open.") }
                panel.orderOut(nil)
                setStatus("Draft copied. Paste it into the intended browser chat with ⌘V; nothing was sent.")
            }
        } catch { showError(error.localizedDescription) }
    }

    private func prefillClaude() {
        do {
            let packet = try currentDraft()
            guard packet.target == .claude else { throw RelayError.invalid("Choose Claude as the destination first.") }
            let url = try RouteBuilder.claudePrefillURL(prompt: packet.text)
            guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { throw RelayError.invalid("No app handles Claude links. Use Copy + Open instead.") }
            let alert = NSAlert()
            alert.messageText = "Open a new Claude chat with this draft?"
            alert.informativeText = "The complete draft will be passed to the installed claude:// handler through macOS. Claude's documented behavior is to prefill a NEW chat for your review, not send it. Do not use this route for text you do not want passed through a URL handler."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Open new draft")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            guard NSWorkspace.shared.open(url) else { throw RelayError.invalid("Claude could not open the draft link. Use Copy + Open instead.") }
            panel.orderOut(nil)
            setStatus("Claude prefill requested. Review the new chat; no send action was issued.")
        } catch { showError(error.localizedDescription) }
    }

    @objc private func showRealityTimeline() {
        guard let store = store else { showError("Local storage is unavailable."); return }
        do {
            let realities = try store.listRealities()
            realityTimeline?.show(realities: realities)
            if let selected = realitySelectionID { realityTimeline?.select(id: selected, realities: realities) }
        } catch {
            showError("Could not load the reality timeline: \(error.localizedDescription)")
        }
    }

    private func showWhatChanged(for reality: RealitySnapshot) {
        do {
            guard let store = store else { throw RelayError.invalid("Local storage is unavailable.") }
            let realities = try store.listRealities()
            guard let current = realities.first(where: { $0.id != reality.id }) ?? realities.first else {
                setStatus("There is no second saved reality to compare yet.")
                return
            }
            let report = RealityDiff.compare(reality, current)
            let alert = NSAlert()
            alert.messageText = report.title
            alert.informativeText = report.text
            alert.addButton(withTitle: "Close")
            alert.runModal()
        } catch { showError("Could not compare realities: \(error.localizedDescription)") }
    }

    private func showFileChanges(for reality: RealitySnapshot) {
        do {
            guard let store = store else { throw RelayError.invalid("Local storage is unavailable.") }
            let realities = try store.listRealities()
            guard let other = realities.first(where: { $0.id != reality.id }) ?? realities.first else {
                setStatus("There is no second saved reality to inspect yet.")
                return
            }
            realityFilesPanel?.show(from: reality, to: other)
        } catch { showError("Could not inspect file changes: \(error.localizedDescription)") }
    }

    private func applySelectedChanges(from source: RealitySnapshot, to target: RealitySnapshot, hunks: Set<String>, paths: Set<String>) {
        do {
            guard let destination = target.worktreePath, !destination.isEmpty else { throw RealityTransferError.destinationUnavailable }
            let alert = NSAlert()
            alert.messageText = "Apply selected changes?"
            alert.informativeText = "RelayBar will apply \(hunks.count) selected hunk\(hunks.count == 1 ? "" : "s") and \(paths.count) untracked file\(paths.count == 1 ? "" : "s") to \(destination). It will preflight the patch and roll it back if materialization fails."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Apply selected")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            try RealityPatchTransfer().apply(selectedHunks: hunks, untrackedPaths: paths, from: source, to: destination)
            realityFilesPanel?.orderOut(nil)
            setStatus("Applied selected changes to \(target.name). The source reality was unchanged.")
        } catch { showError(error.localizedDescription) }
    }

    private func restoreReality(_ reality: RealitySnapshot) {
        do {
            try reality.validate()
            let alert = NSAlert()
            alert.messageText = "Restore \(reality.name)?"
            alert.informativeText = "This restores RelayBar’s saved project, reference, task, and draft. If supported browser tabs were saved, RelayBar will explicitly open those HTTP(S) tabs and select the saved tab. It does not reset Git or replace the clipboard."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Restore RelayBar state")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            if let index = configuration.projects.firstIndex(where: { $0.id == reality.project.id }) { configuration.projects[index] = reality.project }
            else if configuration.projects.count < 100 { configuration.projects.append(reality.project) }
            configuration.selectedProjectID = reality.project.id
            configuration.target = reality.checkpoint.draft.target
            capture = reality.checkpoint.capture
            draft = reality.checkpoint.draft
            if !reality.browserTabs.isEmpty {
                chromeBridge.restore(reality.browserTabs) { [weak self] message in self?.setStatus(message) }
            }
            currentAction = reality.checkpoint.draft.action
            suppressEdits = true
            referenceView.string = capture.text
            draftView.string = draft?.text ?? ""
            taskField.stringValue = reality.checkpoint.task
            suppressEdits = false
            saveConfiguration(); refreshControls()
            realityTimeline?.orderOut(nil)
            setStatus("Restored RelayBar state from \(reality.name). Browser restoration was requested only for saved supported tabs; Git and the clipboard were left untouched.")
        } catch {
            showError("Could not restore this reality: \(error.localizedDescription)")
        }
    }

    private func forkRealityFromSnapshot(_ reality: RealitySnapshot) {
        do {
            guard let store = store else { throw RelayError.invalid("Local storage is unavailable.") }
            let picker = NSOpenPanel()
            picker.title = "Choose a parent folder for the forked reality"
            picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.canCreateDirectories = true
            guard picker.runModal() == .OK, let parent = picker.url else { return }
            let destination = parent.appendingPathComponent(SafeFilename.slug(reality.name) + "-fork", isDirectory: true)
            let branch = "reality/\(SafeFilename.slug(reality.name))"
            var forked = reality
            _ = try RealityForker().fork(snapshot: reality, destinationRoot: destination.path, branchName: branch)
            forked.branchName = branch
            forked.worktreePath = destination.path
            _ = try store.saveReality(forked)
            showRealityTimeline()
            setStatus("Forked \(reality.name) into \(destination.path). Both realities remain available.")
        } catch {
            showError("Could not fork \(reality.name): \(error.localizedDescription)")
        }
    }

    @objc private func forkCurrentReality() {
        do {
            guard let store = store else { throw RelayError.invalid("Local storage is unavailable.") }
            let packet = try currentDraft()

            let sourcePicker = NSOpenPanel()
            sourcePicker.title = "Choose the Git project to fork"
            sourcePicker.message = "RelayBar captures tracked and untracked changes into a bounded private snapshot before creating the separate worktree."
            sourcePicker.canChooseFiles = false
            sourcePicker.canChooseDirectories = true
            sourcePicker.canCreateDirectories = false
            guard sourcePicker.runModal() == .OK, let sourceURL = sourcePicker.url else { return }

            let destinationPicker = NSOpenPanel()
            destinationPicker.title = "Choose a parent folder for the forked reality"
            destinationPicker.canChooseFiles = false
            destinationPicker.canChooseDirectories = true
            destinationPicker.canCreateDirectories = true
            guard destinationPicker.runModal() == .OK, let destinationParent = destinationPicker.url else { return }

            let nameField = NSTextField(string: "experiment-\(Int(Date().timeIntervalSince1970))")
            nameField.placeholderString = "Reality name"
            let branchField = NSTextField(string: "reality/experiment")
            branchField.placeholderString = "Git branch name"
            let form = NSStackView(views: [label("Name"), nameField, label("Branch"), branchField])
            form.orientation = .vertical; form.alignment = .leading; form.spacing = 8
            form.frame = NSRect(x: 0, y: 0, width: 360, height: 90)
            nameField.widthAnchor.constraint(equalToConstant: 360).isActive = true
            branchField.widthAnchor.constraint(equalToConstant: 360).isActive = true
            let alert = NSAlert()
            alert.messageText = "Fork this reality?"
            alert.informativeText = "RelayBar will save the reviewed draft locally, then create a new Git worktree. The current project will not be reset or changed."
            alert.accessoryView = form
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Fork")
            guard alert.runModal() == .alertSecondButtonReturn else { return }

            lastRealityRoot = sourceURL.path
            let git = try readGitSnapshot(at: sourceURL.path)
            let checkpoint = Checkpoint(project: configuration.selectedProject, capture: capture, task: taskField.stringValue, draft: packet)
            let reality = RealitySnapshot(name: nameField.stringValue, project: configuration.selectedProject,
                                          checkpoint: checkpoint, gitRoot: sourceURL.path,
                                          gitSnapshot: GitSnapshotRecord(snapshot: git.snapshot, commit: git.commit),
                                          browserTabs: capturedBrowserTabs(),
                                          dirtyWorkingTree: git.dirty)
            let savedURL = try store.saveReality(reality)
            let worktreeURL = destinationParent.appendingPathComponent(SafeFilename.slug(nameField.stringValue), isDirectory: true)
            _ = try RealityForker().fork(snapshot: reality, destinationRoot: worktreeURL.path, branchName: branchField.stringValue)
            lastRealityRoot = sourceURL.path
            setStatus("Reality forked at \(worktreeURL.path). Snapshot saved as \(savedURL.lastPathComponent). The original worktree was untouched.")
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func readGitSnapshot(at root: String) throws -> (snapshot: GitSnapshot, commit: String, dirty: RealityDirtyWorkingTree?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--verify", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: root)
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        do { try process.run(); process.waitUntilExit() } catch { throw RelayError.invalid("Git could not inspect this project: \(error.localizedDescription)") }
        guard process.terminationStatus == 0 else { throw RelayError.invalid("Choose a Git working tree with an initial commit.") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let commit = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !commit.isEmpty else {
            throw RelayError.invalid("Git did not return a commit for this project.")
        }
        let monitor = GitMonitor(); monitor.refresh(at: root)
        guard !monitor.snapshot.branch.isEmpty else { throw RelayError.invalid("Git branch information is unavailable.") }
        let dirty = try RealityDirtyWorkingTree.capture(at: root)
        return (monitor.snapshot, commit, dirty)
    }

    private func saveCheckpoint() {
        do {
            guard let store = store else { throw RelayError.invalid("Local storage is unavailable.") }
            let packet = try currentDraft()
            let alert = NSAlert()
            alert.messageText = "Save this session on this Mac?"
            alert.informativeText = "The project brief, task, captured reference, and reviewed draft will be saved as unencrypted local JSON in RelayBar's Application Support folder. They are not a verified transcript or test report. Only save content you intend to keep."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Save locally")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            let url = try store.saveCheckpoint(Checkpoint(project: configuration.selectedProject, capture: capture, task: taskField.stringValue, draft: packet))
            setStatus("Checkpoint saved: \(url.lastPathComponent). Load it later from the RB menu.")
        } catch { showError(error.localizedDescription) }
    }

    @objc private func loadCheckpointFromMenu() {
        guard let store = store else { showError("Local storage is unavailable."); return }
        showPanel()
        let picker = NSOpenPanel(); picker.title = "Load a RelayBar checkpoint"
        picker.allowedFileTypes = ["json"]; picker.allowsMultipleSelection = false
        picker.directoryURL = store.checkpointsURL
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let checkpoint = try store.loadCheckpoint(from: url)
            let alert = NSAlert(); alert.messageText = "Restore \(checkpoint.project.name)?"
            alert.informativeText = "This will replace the current in-memory reference and draft, and restore this checkpoint's project brief. The saved content is user-supplied and unverified. Existing checkpoint files will not be altered."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Restore session")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            if let index = configuration.projects.firstIndex(where: { $0.id == checkpoint.project.id }) { configuration.projects[index] = checkpoint.project }
            else {
                guard configuration.projects.count < 100 else { throw RelayError.invalid("The 100-project limit has been reached. This checkpoint was not imported.") }
                configuration.projects.append(checkpoint.project)
            }
            configuration.selectedProjectID = checkpoint.project.id
            configuration.target = checkpoint.draft.target
            capture = checkpoint.capture; draft = checkpoint.draft; currentAction = checkpoint.draft.action
            suppressEdits = true
            referenceView.string = capture.text; draftView.string = checkpoint.draft.text; taskField.stringValue = checkpoint.task
            suppressEdits = false
            saveConfiguration(); refreshControls()
            setStatus("Checkpoint restored. Reported results remain unverified. Review before reusing it.")
        } catch { showError(error.localizedDescription) }
    }

    private func editProject(isNew: Bool) {
        showPanel()
        let original = isNew ? ProjectBrief(id: UUID().uuidString, name: "", brief: "", constraints: "") : configuration.selectedProject
        let alert = NSAlert(); alert.messageText = isNew ? "New project brief" : "Edit \(original.name)"
        alert.informativeText = "This is a user-maintained brief, not a live repository link. Do not put secrets here. It is saved locally and included in generated drafts."
        let content = NSStackView(); content.orientation = .vertical; content.alignment = .leading; content.spacing = 8
        content.frame = NSRect(x: 0, y: 0, width: 560, height: 365)
        let name = NSTextField(string: original.name); name.placeholderString = "Project name"
        let (briefScroll, brief) = textEditor(height: 135); brief.string = original.brief
        let (constraintsScroll, constraints) = textEditor(height: 100); constraints.string = original.constraints
        for view in [label("Name (80 characters maximum)"), name, label("Brief (8,000 maximum)"), briefScroll, label("Constraints (4,000 maximum)"), constraintsScroll] {
            content.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        alert.accessoryView = content
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Save brief")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let revised = ProjectBrief(id: original.id, name: name.stringValue, brief: brief.string, constraints: constraints.string)
        do {
            try Limits.validate(project: revised)
            if isNew {
                guard configuration.projects.count < 100 else { throw RelayError.invalid("The 100-project limit has been reached.") }
                configuration.projects.append(revised); configuration.selectedProjectID = revised.id; clearSession()
            } else if let index = configuration.projects.firstIndex(where: { $0.id == revised.id }) {
                configuration.projects[index] = revised; invalidateDraft()
            }
            saveConfiguration(); refreshControls()
        } catch { showError(error.localizedDescription) }
    }

    private func chooseApp(_ target: AssistantTarget) {
        showPanel()
        let picker = NSOpenPanel(); picker.title = "Choose the \(target.rawValue) app you actually use"
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.allowedFileTypes = ["app"]; picker.canChooseDirectories = false; picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        guard url.pathExtension == "app", Bundle(url: url) != nil else { showError("Choose an application bundle."); return }
        configuration.appPaths[target.rawValue] = url.path
        saveConfiguration(); setStatus("\(target.rawValue) will open \(url.lastPathComponent). No files inside it were modified.")
    }

    func textDidChange(_ notification: Notification) {
        guard !suppressEdits, let view = notification.object as? NSTextView else { return }
        if view === referenceView {
            capture = Capture(text: view.string, origin: "Manually edited reference")
            invalidateDraft(); refreshControls()
        } else if view === draftView {
            if draft != nil { draft?.text = view.string }
            rebuildBars()
        }
    }
    func controlTextDidChange(_ notification: Notification) {
        guard !suppressEdits else { return }
        if (notification.object as? NSTextField) === taskField { invalidateDraft(); refreshControls() }
    }

    private func setStatus(_ text: String) { statusLabel.stringValue = text }
    private func showError(_ text: String) {
        showPanel(); setStatus(text)
        let alert = NSAlert(); alert.messageText = "RelayBar"; alert.informativeText = text; alert.alertStyle = .warning
        alert.addButton(withTitle: "OK"); alert.runModal()
    }

    @objc private func targetChanged() { if let title = targetPicker.titleOfSelectedItem, let target = AssistantTarget(rawValue: title) { setTarget(target) } }
    @objc private func projectChanged() { let index = projectPicker.indexOfSelectedItem; if configuration.projects.indices.contains(index) { changeProject(to: configuration.projects[index].id) } }
    @objc private func modeChanged() {
        if let title = modePicker.titleOfSelectedItem, let mode = WorkflowMode(rawValue: title) { configuration.mode = mode; saveConfiguration(); refreshControls() }
    }
    @objc private func actionChanged() {
        let index = actionPicker.indexOfSelectedItem
        guard PromptAction.allCases.indices.contains(index) else { return }
        currentAction = PromptAction.allCases[index]; invalidateDraft(); refreshControls()
    }
    @objc private func toggleFollow() { configuration.followDesktopAssistant.toggle(); saveConfiguration(); refreshControls() }
    @objc private func toggleDesktop() { configuration.preferDesktop.toggle(); saveConfiguration(); refreshControls() }
    @objc private func showFromMenu() { returnToRelayBar(showPanel: true) }
    @objc private func returnRelayBarFromMenu() { returnToRelayBar(showPanel: false) }
    @objc private func useMacTouchBarFromMenu() { enterMacTouchBarMode() }
    @objc private func togglePersistentShellPause() {
        if shellState.paused || shellState.mode == .mac {
            returnToRelayBar(showPanel: false)
            return
        }
        shellState.pause()
        overlayEnabled = false
        navigation.leaveUnavailablePins(); stopPinnedChats()
        contextStack?.pause("Collection paused because RelayBar Touch Bar is not visible.")
        nativeMenus.clear()
        screenshotPresentation.overlayDisabled()
        bridge.dismissOverlay()
        refreshShellMenuState()
        setStatus("Persistent Touch Bar paused. The stock macOS Touch Bar stays active until you explicitly return to RelayBar.")
    }
    @objc private func toggleLaunchAtLogin() {
        let next = !loginEnabled
        do {
            try PersistentShellMac.setLoginItemEnabled(next)
            loginEnabled = next
            UserDefaults.standard.set(next, forKey: "persistentShell.loginEnabled")
            refreshShellMenuState()
            setStatus(next ? "RelayBar will launch at login." : "RelayBar login launch disabled. The currently running app is unchanged.")
        } catch { showError("Could not update the RelayBar login item: \(error.localizedDescription)") }
    }
    private func enterMacTouchBarMode() {
        screenshotPresentation.cancelRecovery()
        navigation.leaveUnavailablePins(); stopPinnedChats()
        contextStack?.pause("Collection paused because the stock macOS Touch Bar is active.")
        nativeMenus.clear()
        shellState.enterMacMode()
        overlayEnabled = false
        screenshotPresentation.overlayDisabled()
        bridge.dismissOverlay()
        refreshShellMenuState()
        setStatus("macOS Touch Bar active. RelayBar will not reclaim it on app switches; choose Return RelayBar Touch Bar from the RB menu when you want it back.")
    }
    private func returnToRelayBar(showPanel shouldShowPanel: Bool) {
        shellState.returnToRelayBar()
        UserDefaults.standard.set(true, forKey: "persistentShell.enabled")
        overlayEnabled = true
        refreshShellMenuState()
        rebuildBars()
        refreshAppContext()
        if shouldShowPanel { showPanel() }
        else { updateOverlay(for: NSWorkspace.shared.frontmostApplication) }
        setStatus("Persistent RelayBar Touch Bar active.")
    }
    private func refreshShellMenuState() {
        persistentPauseMenuItem?.title = shellState.paused ? "Resume Persistent Touch Bar" : "Pause Persistent Touch Bar"
        persistentPauseMenuItem?.state = shellState.paused ? .on : .off
        returnRelayMenuItem?.isEnabled = !shellState.relayVisible
        macTouchBarMenuItem?.isEnabled = shellState.relayVisible
        loginItemMenuItem?.state = loginEnabled ? .on : .off
        overlayMenuItem?.state = overlayEnabled ? .on : .off
    }
    @objc private func captureFromMenu() { captureSelection() }
    @objc private func editFromMenu() { editProject(isNew: false) }
    @objc private func newProjectFromMenu() { editProject(isNew: true) }
    @objc private func chooseChatGPT() { chooseApp(.chatgpt) }
    @objc private func chooseClaude() { chooseApp(.claude) }
    @objc private func requestAccessibility() { RBBridge.requestAccessibility() }
    @objc private func revealData() { if let store = store { NSWorkspace.shared.open(store.directory) } }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func disableOverlay() {
        guard shellState.relayVisible else { return }
        togglePersistentShellPause()
    }
    @objc private func toggleOverlay() {
        if shellState.relayVisible { togglePersistentShellPause() }
        else { returnToRelayBar(showPanel: false) }
    }

    private func isCaptureHelper(_ app: NSRunningApplication) -> Bool {
        ["com.apple.screencaptureui", "com.apple.screencapture", "com.apple.Screenshot", "com.apple.systemuiserver"].contains(app.bundleIdentifier ?? "") ||
            (app.localizedName ?? "").lowercased() == "screenshot"
    }

    private var isRefreshingAppContext = false

    /// Browser metadata is read only while the user-enabled cross-app mode is on.
    private func refreshAppContext() {
        guard !isRefreshingAppContext else { return }
        isRefreshingAppContext = true
        defer { isRefreshingAppContext = false }
        refreshPinnedContext()
        guard let front = NSWorkspace.shared.frontmostApplication, !ownApp(front), !isCaptureHelper(front) else { return }
        let bundle = front.bundleIdentifier ?? "unknown-\(front.processIdentifier)"
        let appChanged = liveBundle != bundle
        if appChanged {
            liveBundle = bundle; lastKnownNativeRoute = nil; scriptPage = 0; manualAITools = false
            tabPageIndex = 0
            if appAwareEnabled && Date().timeIntervalSince(self.screenshotArrivalDate) > 6.0 {
                let previousPage = navigation.page
                navigation.externalContextChanged(appAware: true)
                if navigation.page != previousPage { reconcileNavigation() }
            }
        }
        nativeMenus.observe(pid: front.processIdentifier, bundle: bundle,
                            enabled: appAwareEnabled && nativeMenusEnabled && overlayEnabled)
        if chromeBridge.isSupported(bundle: bundle) {
            chromeBridge.refreshTabs(for: bundle)
            youTube.poll(currentTabs: chromeBridge.tabs, activeTab: chromeBridge.activeTab, bundle: bundle)
        } else {
            chromeBridge.clear()
        }
        let snapshot = nativeMenus.snapshot
        let route = snapshot?.route
        var nativeRouteChanged = false
        if let route = route {
            if let old = lastKnownNativeRoute, old != route {
                nativeRouteChanged = true
                scriptPage = 0; manualAITools = false
                if appAwareEnabled && Date().timeIntervalSince(self.screenshotArrivalDate) > 6.0 {
                    let previousPage = navigation.page
                    navigation.externalContextChanged(appAware: true)
                    if navigation.page != previousPage { reconcileNavigation() }
                }
            }
            lastKnownNativeRoute = route
        }
        let activeURL = chromeBridge.activeTab?.url ?? route?.url ?? lastKnownNativeRoute?.url ?? ""
        let urlChanged = !activeURL.isEmpty && activeURL != lastActiveURL
        if !activeURL.isEmpty { lastActiveURL = activeURL }
        let websiteTarget = WebsiteDispatcher.target(for: activeURL)
        let knownSite = route?.site ?? lastKnownNativeRoute?.site
        let oldProfile = liveProfile
        liveAppName = front.localizedName ?? "Application"
        if detectedAssistant(front) != nil || knownSite == .chatgpt || knownSite == .claude {
            liveProfile = "assistant"
        } else if websiteTarget == .sheets || knownSite == .sheets {
            liveProfile = "sheets"
        } else if chromeBridge.isSupported(bundle: bundle) || NativeMenuPolicy.browserBundles.contains(bundle) || ["org.mozilla.firefox", "company.thebrowser.Browser"].contains(bundle) {
            liveProfile = "browser"
        } else {
            liveProfile = "other"
        }
        // App-aware routing:
        // 1. Google Sheets -> appControls (Google Sheets command center)
        if appAwareEnabled && overlayEnabled && liveProfile == "sheets" &&
           (oldProfile != "sheets" || urlChanged || nativeRouteChanged) && navigation.page != .appControls &&
           navigation.page != .sheetsTools && navigation.page != .screenshots && navigation.page != .screenshotOptions {
            nativeMenus.cancelInteraction(); navigation.open(.appControls); reconcileNavigation()
        }
        // 2. Default browser website -> websiteTabs (Website Tabs view)
        else if appAwareEnabled && overlayEnabled && liveProfile == "browser" &&           // A deliberate visit to Site tools or the Toolbox is not interrupted
           // by an ordinary tab switch.
           (oldProfile != "browser" || appChanged || urlChanged) && navigation.page != .websiteTabs &&
           navigation.page != .siteTools && navigation.page != .toolbox &&
           navigation.page != .screenshots && navigation.page != .screenshotOptions {
           navigation.open(.websiteTabs); reconcileNavigation()
        }
        // 3. Leaving sheets or browser -> return home
        else if appAwareEnabled && (oldProfile == "sheets" || oldProfile == "browser") &&
           (liveProfile != "sheets" && liveProfile != "browser") &&
           (navigation.page == .appControls || navigation.page == .sheetsTools || navigation.page == .websiteTabs || navigation.page == .siteTools) {
            nativeMenus.cancelInteraction(); navigation.open(.home); reconcileNavigation()
        }
        if showingPinnedChats && (liveProfile == "other" || route?.site == .sheets) {
            navigation.leaveUnavailablePins(); stopPinnedChats(); reconcileNavigation()
        }
        if configuration.followDesktopAssistant, draft == nil, knownSite == .chatgpt || knownSite == .claude {
            let target: AssistantTarget = knownSite == .chatgpt ? .chatgpt : .claude
            if configuration.target != target { configuration.target = target; saveConfiguration(); refreshControls() }
        }
        let details: String
        if !appAwareEnabled { details = "App-aware detection paused · button families retained" }
        else if liveProfile == "sheets" {
            details = "\(liveAppName) · Google Sheets · " + (snapshot?.status ?? "Apps Script & spreadsheet tools")
        } else if liveProfile == "browser" {
            let count = chromeBridge.tabs.count
            let site = siteControls.matchedRule.map { " · site: \($0.name)" } ?? ""
            details = "\(liveAppName) · \(count) open tab\(count == 1 ? "" : "s")\(site) · tap to switch"
        } else if liveProfile == "other" { details = "\(liveAppName) · RelayBar persistent shell" }
        else { details = "\(liveAppName) · button families" }
        let statusChanged = details != appContextLabel.stringValue
        appContextLabel.stringValue = details
        appContextMenuItem?.title = String(details.prefix(160))
        let changedControls = lastNativeRevision != nativeMenus.revision
        if changedControls { lastNativeRevision = nativeMenus.revision; scriptPage = 0 }
        // Site rules are re-resolved on the same cadence as app routing. A
        // re-resolution only redraws the strip; it never runs anything.
        let siteContextChanged = refreshSiteControls()
        if appChanged || oldProfile != liveProfile || changedControls || statusChanged || siteContextChanged { rebuildBars() }
        updateOverlay(for: front)
    }

    private func appAwareSlots(fallback: [TouchBarDriver.Slot]) -> [TouchBarDriver.Slot] {
        guard appAwareEnabled, liveProfile != "assistant" else { return fallback }
        let stack = TouchBarDriver.Slot(key: "stack-open", title: "Stack", help: "Open the Context Stack", width: 44) { [weak self] in self?.showStackFromMenu() }
        let shots = TouchBarDriver.Slot(key: "screenshots", title: "Shots", help: "Show the latest screenshots", width: 44) { [weak self] in self?.showScreenshotsFromMenu() }
        let hide = TouchBarDriver.Slot(key: "hide", title: "×", help: "Hide RelayBar and disable cross-app controls", width: 30) { [weak self] in self?.disableOverlay(); self?.hidePanel() }
        let rev = nativeMenus.revision
        if let pending = nativeMenus.pendingLabel {
            return [shots,
                .init(key: "native-confirm-\(rev)", title: "Run: " + String(pending.suffix(35)), help: "Request “\(pending)”. This action may change data or send messages.", width: 340) { [weak self] in
                    self?.nativeMenus.confirm(expectedRevision: rev)
                },
                .init(key: "native-cancel-\(rev)", title: "Cancel", help: "Cancel without running the menu action", width: 85) { [weak self] in self?.nativeMenus.cancelConfirmation() }, hide]
        }
        if liveProfile == "sheets" {
            let umbrella = TouchBarDriver.Slot(
                key: "sheets-tools-umbrella",
                title: "📊 Sheets Tools ›",
                help: "Spreadsheet tools: formatting, formulas, freeze rows, filters, Apps Script",
                width: 110
            ) { [weak self] in
                self?.navigate(to: .sheetsTools)
            }

            if !nativeMenus.controls.isEmpty {
                let controls = nativeMenus.controls
                // Group Apps Script custom menus first so they are prominent on the Touch Bar
                let appsScriptControls = controls.filter(\.isAppsScript)
                let standardControls = controls.filter { !$0.isAppsScript }
                let displayControls = appsScriptControls.isEmpty ? standardControls : (appsScriptControls + standardControls)

                let pages = NativeMenuPolicy.pageCount(displayControls.count)
                scriptPage = min(scriptPage, pages-1)
                let first = scriptPage * NativeMenuPolicy.pageSize
                let end = min(first + NativeMenuPolicy.pageSize, displayControls.count)
                var slots = [stack, shots, umbrella,
                    TouchBarDriver.Slot(key: "native-roots", title: "Menus", help: "Return to the top-level Sheet menus without sending a key", width: 46) { [weak self] in self?.nativeMenus.showMenus() }]
                for index in first..<end {
                    let c = displayControls[index]
                    let actualIndex = controls.firstIndex(of: c) ?? index
                    let full = c.path.isEmpty ? c.label : c.path + " › " + c.label
                    let prefix = c.isAppsScript ? "⚡ " : ""
                    slots.append(.init(key: "native-\(rev)-\(actualIndex)", title: prefix + String(c.label.prefix(13)) + (c.isMenu ? " ›" : ""),
                        help: full + (c.isAppsScript ? " · run Apps Script tool" : (c.isMenu ? " · open menu" : " · request existing action")),
                        isEnabled: c.enabled && nativeMenus.gate.executing == nil, width: c.isAppsScript ? 90 : 80) { [weak self] in
                        self?.screenshotPresentation.cancelRecovery()
                        self?.nativeMenus.tap(index: actualIndex, expectedRevision: rev)
                    })
                }
                slots.append(.init(key: "native-page-\(rev)", title: "\(scriptPage+1)/\(pages) ›", help: "Next page of Sheet controls; wraps back to the first", isEnabled: pages > 1, width: 54) { [weak self] in
                    guard let self = self else { return }; self.scriptPage = (self.scriptPage + 1) % pages
                    self.rebuildBars(); self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
                })
                slots.append(hide); return slots
            } else {
                var slots = [stack, shots, umbrella]
                if !nativeMenusEnabled || !RBBridge.accessibilityTrusted() {
                    slots.append(.init(key: "native-enable", title: "Enable Apps Script tools", help: "Enable Accessibility in RB to detect custom Apps Script menus", width: 170) { [weak self] in self?.enableNativeControls() })
                } else {
                    slots.append(.init(key: "native-status", title: "Scanning menus…", help: nativeMenus.snapshot?.status ?? "Waiting for Sheet menus", isEnabled: false, width: 130, action: {}))
                    slots.append(.init(key: "native-report", title: "Check link", help: "Show a local connection report", width: 80) { [weak self] in self?.showNativeReport() })
                }
                slots.append(hide); return slots
            }
        }
        if liveProfile == "browser" {
            let tabCount = chromeBridge.tabs.count
            // Shots and Stack are intentionally omitted while browsing so the tab
            // strip is not competing with them for width. Both remain on the Home
            // family and in the RB menu.
            var slots: [TouchBarDriver.Slot] = []
            slots.append(.init(key: "goto-tabs", title: "🌐 Tabs (\(tabCount)) ›", help: "View and switch open browser tabs", width: 120) { [weak self] in
                self?.navigate(to: .websiteTabs)
            })
            slots.append(hide)
            return slots
        }
        var slots = [pinnedChatsSlot(), stack, shots]
        slots.append(.init(key: "native-label", title: String(liveAppName.prefix(18)), help: "This app retains its native Touch Bar", isEnabled: false, width: 160, action: {}))
        slots.append(.init(key: "manual-ai", title: "AI tools", help: "Use AI tools until the next app or document switch", width: 80) { [weak self] in
            guard let self = self else { return }; self.navigate(to: .home)
        })
        slots.append(hide); return slots
    }

    @objc private func toggleAppAware() {
        stopPinnedChats()
        appAwareEnabled.toggle(); UserDefaults.standard.set(appAwareEnabled, forKey: "appAware.enabled")
        appAwareMenuItem?.state = appAwareEnabled ? .on : .off
        nativeMenus.clear(); lastKnownNativeRoute = nil; manualAITools = false
        screenshotPresentation.showTools(); rebuildBars(); refreshAppContext()
    }
    private func refreshStackUI() {
        guard let stack = contextStack else { return }
        let session = stack.session
        stackCollectMenuItem?.title = session.collecting ? "Pause collecting copied text" : "Start collecting copied text…"
        stackCollectMenuItem?.state = session.collecting ? .on : .off
        stackSummaryMenuItem?.title = "\(session.stack.projectName) · \(session.stack.clips.count) clips · memory only"
        statusItem?.button?.title = session.collecting ? "RB ●\(session.stack.clips.count)" : "RB"
        statusItem?.button?.toolTip = "Context Stack · " + session.message
        setStatus(session.message)
        rebuildBars(); updateOverlay(for: NSWorkspace.shared.frontmostApplication)
    }
    @objc private func showStackFromMenu() {
        if !shellState.relayVisible { returnToRelayBar(showPanel: false) }
        navigate(to: .stack)
    }
    @objc private func toggleStackCollection() {
        if !navigation.isStackPage { navigate(to: .stack) }
        nativeMenus.cancelInteraction()
        contextStack?.toggleCollection(); refreshStackUI()
    }
    @objc private func pasteStackClip() { contextStack?.pasteClip(); showStackFromMenu() }
    @objc private func reviewStack() {
        if !navigation.isStackPage { navigate(to: .stack) }
        nativeMenus.cancelInteraction()
        // Preserve the current external app for Back to work.
        if let front = NSWorkspace.shared.frontmostApplication, !ownApp(front) { lastExternalApp = front }
        contextStack?.showReview()
    }
    @objc private func clearStack() { contextStack?.clearCurrent() }

    // MARK: Pinned Chats — extension-free native sidebar navigation
    private func pinnedChatsSlot() -> TouchBarDriver.Slot {
        .init(key: "pins-open", title: "Pins", help: "Navigate real pinned / starred chats in the active assistant", width: 44) { [weak self] in self?.showPinnedChats() }
    }
    private func stopPinnedChats() {
        guard showingPinnedChats else { return }
        showingPinnedChats = false; pinnedChats?.stop()
    }
    private func pinnedNativeProvider(_ app: NSRunningApplication) -> PinProvider? {
        // Names/window titles are not an app identity. Respect an explicitly
        // selected app path, otherwise require the known desktop bundle ID.
        for target in AssistantTarget.allCases {
            if let path = configuration.appPaths[target.rawValue],
               app.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path {
                return target == .chatgpt ? .chatgpt : .claude
            }
        }
        switch app.bundleIdentifier {
        case "com.openai.chat": return .chatgpt
        case "com.anthropic.claudefordesktop": return .claude
        default: return nil
        }
    }
    private func refreshPinnedContext(force: Bool = false) {
        guard showingPinnedChats else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let native = front.flatMap { pinnedNativeProvider($0) }
        pinnedChats?.update(front: front, nativeProvider: native, force: force)
    }
    @objc private func showPinnedChats() {
        navigate(to: .pins)
    }
    @objc private func refreshPinnedChats() {
        if !showingPinnedChats { showPinnedChats() }
        pinnedChats?.refresh(); refreshPinnedContext(force: true)
    }
    @objc private func showPinnedStatus() { pinnedChats?.showStatus() }
    private func openPinnedAssistant(_ provider: PinProvider) {
        let target: AssistantTarget = provider == .chatgpt ? .chatgpt : .claude
        guard let url = appURL(for: target) else {
            setStatus("Choose the \(provider.title) application in the RB menu, or focus its browser tab yourself.")
            pinnedChats?.showStatus(); return
        }
        let options = NSWorkspace.OpenConfiguration(); options.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: options) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error { self?.setStatus("Could not open \(provider.title): \(error.localizedDescription)") }
                self?.refreshPinnedContext(force: true)
            }
        }
    }

    @objc private func enableNativeControls() {
        showPanel()
        if !UserDefaults.standard.bool(forKey: "nativeMenus.introduced") || !nativeMenusEnabled {
            let alert = NSAlert(); alert.messageText = "Native app controls — no browser extension"
            alert.informativeText = "RelayBar can read the current browser’s exposed page identity and Sheet menus through macOS Accessibility, then activate a menu control when you tap. No spreadsheet files, sidebars, API keys or browser extensions are needed.\n\nIt requests the browser’s accessibility tree where supported. This may increase browser resource use. RelayBar does not read cells, type keys, or run JavaScript. Menu actions ask for confirmation on the Touch Bar by default.\n\nRelayBar 0.9 uses a persistent Touch Bar shell by default. Enabling native controls returns to that shell if you were temporarily using the stock macOS Touch Bar."
            alert.addButton(withTitle: "Enable native controls"); alert.addButton(withTitle: "Not now")
            UserDefaults.standard.set(true, forKey: "nativeMenus.introduced")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        guard RBBridge.overlayAvailable() else { showError("This Mac does not expose RelayBar’s experimental Touch Bar overlay. No permissions or browser settings were changed."); return }
        nativeMenusEnabled = true; appAwareEnabled = true
        UserDefaults.standard.set(true, forKey: "nativeMenus.enabled")
        UserDefaults.standard.set(true, forKey: "appAware.enabled")
        nativePauseMenuItem?.state = .on; appAwareMenuItem?.state = .on
        shellState.returnToRelayBar()
        overlayEnabled = true
        refreshShellMenuState()
        if !RBBridge.accessibilityTrusted() {
            RBBridge.requestAccessibility()
            // An explicit click opens Settings; permission is never bypassed.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            panel.orderOut(nil)
            setStatus("Enable RelayBar in Privacy & Security → Accessibility, then return to your Sheet. No workbook setup is required.")
        } else { hidePanel() }
        refreshAppContext()
    }
    @objc private func toggleNativeDetection() {
        if !nativeMenusEnabled { enableNativeControls(); return }
        nativeMenusEnabled = false; UserDefaults.standard.set(false, forKey: "nativeMenus.enabled")
        nativePauseMenuItem?.state = .off; nativeMenus.clear(); lastKnownNativeRoute = nil
        refreshAppContext(); rebuildBars()
    }
    @objc private func toggleNativeConfirmation() {
        if nativeAskActions {
            showPanel()
            let alert = NSAlert(); alert.messageText = "Use one-tap menu actions?"
            alert.informativeText = "A single tap may run an existing script, change spreadsheet data or send messages using that script’s permissions. RelayBar cannot determine an action’s effects. This is a global setting for all spreadsheets."
            alert.addButton(withTitle: "Keep confirmation"); alert.addButton(withTitle: "Use one tap")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        nativeAskActions.toggle(); nativeMenus.askBeforeActions = nativeAskActions
        UserDefaults.standard.set(nativeAskActions, forKey: "nativeMenus.askActions")
        nativeAskMenuItem?.state = nativeAskActions ? .on : .off
        nativeMenus.cancelConfirmation(); hidePanel()
    }
    @objc private func showNativeReport() {
        // Capture before activating our panel: the report concerns the browser.
        let report = nativeMenus.connectionReport
        showPanel()
        let alert = NSAlert(); alert.messageText = "Native connection report"
        alert.informativeText = report + "\n\nGoogle Sheets must expose its menus and an exact page URL. Canvas-only drawings and hidden script functions cannot be mirrored. This build has not been verified against live Sheets or physical Touch Bar hardware."
        alert.addButton(withTitle: "Done"); alert.addButton(withTitle: "Copy report")
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report, forType: .string)
            setStatus("Connection report copied by request. No document content is included.")
        }
    }
    @objc private func showAbout() {
        showPanel()
        let alert = NSAlert(); alert.messageText = "RelayBar 0.9.1 · Persistent Shell"
        alert.informativeText = "RelayBar keeps its contextual Touch Bar active across apps and reserves the far-right controls for Chrome, Claude, ChatGPT and the stock macOS Touch Bar. The  button explicitly hands the strip back to macOS and RelayBar does not reclaim it on ordinary app switches; return from the RB menu.\n\nPinned Chats, Native Sheets Verified Click, Context Stack, Screenshot Shelf, Button Families and prompt tools remain local features with their existing confirmation and privacy boundaries. Native Sheets is extension-free and asks before leaf actions by default. Accessibility is a broad system permission.\n\nRelayBar is configured to launch at login by default. These sources still require Mac SDK compilation and physical Touch Bar validation on the installed Mac."
        alert.addButton(withTitle: "OK"); alert.runModal()
    }
}

// MARK: - Button Families (presentation adapter; existing feature engines unchanged)
extension RelayAppDelegate {
    private func familyMenu(_ page: RelayPage) -> NSMenuItem {
        let root = NSMenuItem(title: page.title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: page.title)
        let show = FamilyMenuItem("Show " + page.title + " on Touch Bar", help: page.breadcrumb) { [weak self] in
            guard let self = self else { return }
            if !self.shellState.relayVisible { self.returnToRelayBar(showPanel: false) }
            self.navigate(to: page)
        }
        menu.addItem(show)
        if page == .screenshots { screenshotPageMenuItem = show }
        if page == .stack {
            stackSummaryMenuItem = NSMenuItem(title: "No clips · memory only", action: nil, keyEquivalent: "")
            menu.addItem(stackSummaryMenuItem!)
        }
        menu.addItem(.separator())
        for item in RelayHierarchy.items(on: page) {
            switch item {
            case .page(let child): menu.addItem(familyMenu(child))
            case .command(let command):
                let control = FamilyMenuItem(command.title, help: command.help) { [weak self] in self?.runFamilyCommand(command) }
                menu.addItem(control)
                switch command {
                case .collectStack: stackCollectMenuItem = control
                case .watchScreenshots: screenshotWatchMenuItem = control
                case .autoScreenshots:
                    screenshotAutoOpenMenuItem = control
                    control.state = screenshotPresentation.autoOpenEnabled ? .on : .off
                case .appAware:
                    appAwareMenuItem = control; control.state = appAwareEnabled ? .on : .off
                case .overlay: overlayMenuItem = control
                case .nativeDetection:
                    nativePauseMenuItem = control; control.state = nativeMenusEnabled ? .on : .off
                case .nativeConfirmation:
                    nativeAskMenuItem = control; control.state = nativeAskActions ? .on : .off
                case .followAssistant: followMenuItem = control
                case .preferDesktop: desktopMenuItem = control
                default: break
                }
            }
        }
        if page == .pins {
            menu.addItem(FamilyMenuItem("Refresh the active sidebar") { [weak self] in self?.refreshPinnedChats() })
            menu.addItem(FamilyMenuItem("Setup / detection status…") { [weak self] in self?.showPinnedStatus() })
        }
        if page == .modes {
            for mode in WorkflowMode.allCases {
                menu.addItem(FamilyMenuItem(mode.rawValue) { [weak self] in
                    guard let self = self else { return }
                    self.configuration.mode = mode; self.saveConfiguration(); self.refreshControls()
                })
            }
        }
        if page == .appControls {
            menu.addItem(FamilyMenuItem("Native connection report…") { [weak self] in self?.showNativeReport() })
        }
        if page == .capture {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Page context — what Ask about page includes", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for mode in PageContextMode.allCases {
                let item = FamilyMenuItem(mode.title, help: mode.help) { [weak self] in self?.setPageContextMode(mode) }
                item.state = pageContextMode == mode ? .on : .off
                pageContextMenuItems[mode] = item
                menu.addItem(item)
            }
        }
        if page == .siteTools {
            menu.addItem(.separator())
            menu.addItem(FamilyMenuItem("Edit site rules…") { [weak self] in self?.editSiteRules() })
            menu.addItem(FamilyMenuItem("Reload the current page's rule") { [weak self] in
                guard let self = self else { return }
                self.refreshSiteControls()
                self.setStatus(self.siteControls.status)
            })
        }
        root.submenu = menu; return root
    }
    private func navigate(to destination: RelayPage) {
        screenshotArrivalDate = .distantPast
        nativeMenus.cancelInteraction()
        // Leaving the page abandons an unconfirmed site button. It is never
        // queued for later.
        siteControls.cancelPending()
        navigation.open(destination)
        reconcileNavigation()
        if destination == .pins, panel?.isKeyWindow == true { hidePanel() }
        rebuildBars(); updateOverlay(for: NSWorkspace.shared.frontmostApplication)
    }
    private func navigateBack() {
        screenshotArrivalDate = .distantPast
        // Cancel is local. Back never presses a key or an item in Google Sheets.
        if navigation.page == .appControls {
            let decision = RelayHierarchy.nativeBack(pending: nativeMenus.pendingLabel != nil,
                showingOpenMenu: !nativeMenus.forceRoots && !(nativeMenus.snapshot?.openItems.isEmpty ?? true))
            switch decision {
            case .cancelConfirmation:
                nativeMenus.cancelConfirmation(); rebuildBars(); return
            case .menuRoots:
                nativeMenus.showMenus(); rebuildBars(); return
            case .parent: break
            }
        }
        nativeMenus.cancelInteraction()
        siteControls.cancelPending()
        navigation.back(); reconcileNavigation()
        rebuildBars(); updateOverlay(for: NSWorkspace.shared.frontmostApplication)
    }
    private func reconcileNavigation() {
        showingContextStack = navigation.isStackPage
        if navigation.page == .pins {
            if !showingPinnedChats { showingPinnedChats = true; pinnedChats?.start() }
            refreshPinnedContext(force: true)
        } else { stopPinnedChats() }
        if navigation.page == .screenshots { screenshotPresentation.showScreenshots() }
        else { screenshotPresentation.showTools() }
    }

    /// The only place determining the visible Touch Bar hierarchy.
    /// The same slots feed the native panel, text editors, review window and overlay.
    private func familySlots() -> [TouchBarDriver.Slot] {
        var body: [TouchBarDriver.Slot]
        switch navigation.page {
        case .pins:
            body = (pinnedChats?.slots(back: {}, hide: {}) ?? []).filter { !["pins-tools", "hide"].contains($0.key) }.map {
                var item = $0
                if item.key.hasPrefix("pin-") { item.width = 96 }
                return item
            }
        case .screenshots:
            body = screenshotSlots().filter { $0.key.hasPrefix("shot-") || $0.key.hasPrefix("emptyShot") }
            body.append(groupSlot(.screenshotOptions, compact: "More ›"))
        case .stack:
            let original = contextStack?.slots(back: {}, hide: {}) ?? []
            body = [commandSlot(.collectStack), groupSlot(.stackClips)]
            if let pack = original.first(where: { $0.key.hasPrefix("stack-pack-") }) { body.append(pack) }
            body += [commandSlot(.reviewStack), groupSlot(.stackOptions, compact: "More ›")]
        case .stackClips:
            body = (contextStack?.slots(back: {}, hide: {}) ?? []).filter { $0.key.hasPrefix("stack-clip-") || $0.key.hasPrefix("stack-empty-") }
            body.append(commandSlot(.reviewStack))
        case .projects:
            let count = configuration.projects.count
            let page = min(navigation.projectPage, RelayHierarchy.projectPageCount(count) - 1)
            let range = RelayHierarchy.projectRange(count: count, page: page)
            body = range.map { index in
                let project = configuration.projects[index]
                return TouchBarDriver.Slot(key: "choose-project-\(project.id)", title: (project.id == configuration.selectedProjectID ? "✓ " : "") + String(project.name.prefix(12)),
                    help: "Select \(project.name). This clears the prior reference/draft, not its separate Context Stack.", width: 86) { [weak self] in
                        guard let self = self, self.configuration.projects.contains(where: { $0.id == project.id }) else { return }
                        self.changeProject(to: project.id)
                    }
            }
            let pages = RelayHierarchy.projectPageCount(count)
            body.append(.init(key: "projects-page-\(page)-\(count)", title: "\(page+1)/\(pages) ›", help: "Next project page; all projects remain reachable", isEnabled: pages > 1, width: 46) { [weak self] in
                guard let self = self else { return }
                self.navigation.setProjectPage((page+1) % pages, count: self.configuration.projects.count)
                self.rebuildBars(); self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
            })
            body.append(groupSlot(.projectOptions, compact: "Manage ›"))
        case .modes:
            body = WorkflowMode.allCases.map { mode in
                .init(key: "mode-\(mode.rawValue)", title: (configuration.mode == mode ? "✓ " : "") + mode.rawValue,
                      help: "Use \(mode.rawValue) prompt suggestions. Does not generate, copy or send anything.", width: 95) { [weak self] in
                    guard let self = self else { return }
                    self.configuration.mode = mode; self.saveConfiguration(); self.refreshControls()
                }
            }
        case .appControls:
            // Keep native revision, confirmation and request closures unchanged.
            // Only strip unrelated global shortcuts from this child page.
            let original = appAwareSlots(fallback: [
                .init(key: "app-no-actions", title: "No Sheet active", help: "Focus a supported browser's Google Sheet to use its exposed menus.", isEnabled: false, width: 210, action: {}),
                commandSlot(.nativeReport)
            ])
            body = original.filter { !["pins-open", "stack-open", "screenshots", "hide", "manual-ai"].contains($0.key) }
        case .websiteTabs:
            let allTabs = chromeBridge.tabs
            let activeTab = chromeBridge.activeTab
            let activeURL = activeTab?.url ?? ""
            let activeTitle = activeTab?.title ?? ""
            let contextKind = TabContextRouter.detectContext(url: activeURL, title: activeTitle)

            var toolSlots: [TouchBarDriver.Slot] = []
            // A user rule for this page takes precedence over the built-in
            // contexts. A Google Sheet keeps its dedicated native menu path.
            if siteControls.pending == nil, WebsiteDispatcher.target(for: activeURL) != .sheets,
               let rule = siteControls.matchedRule, let ruleID = siteControls.detection.ruleID {
                toolSlots = SiteControlsPolicy.inlineButtons(rule.buttons).map {
                    siteButtonSlot($0, ruleID: ruleID, widthCap: 124)
                }
                if siteControls.hasOverflow { toolSlots.append(siteGroupSlot(rule)) }
            } else if siteControls.pending == nil {
                switch contextKind {
            case .youtube:
                toolSlots = youTube.contextSlots { [weak self] in
                    self?.askAIAboutYouTube()
                }
            case .sheets:
                toolSlots.append(TouchBarDriver.Slot(
                    key: "tab-tool-sheets",
                    title: "📊 Sheets ›",
                    help: "Open Sheets spreadsheet tools & formulas",
                    width: 85
                ) { [weak self] in
                    self?.navigate(to: .sheetsTools)
                })
                toolSlots.append(TouchBarDriver.Slot(
                    key: "tab-tool-cur",
                    title: "$ Currency",
                    help: "Format cells as currency",
                    width: 72
                ) {
                    TabContextRouter.execute(actionID: "sheets.currency", activeURL: activeURL)
                })
            case .github:
                toolSlots.append(TouchBarDriver.Slot(
                    key: "tab-tool-prs",
                    title: "🐙 PRs",
                    help: "Open Pull Requests",
                    width: 65
                ) {
                    TabContextRouter.execute(actionID: "github.prs", activeURL: activeURL)
                })
                toolSlots.append(TouchBarDriver.Slot(
                    key: "tab-tool-iss",
                    title: "📋 Issues",
                    help: "Open Issues",
                    width: 65
                ) {
                    TabContextRouter.execute(actionID: "github.issues", activeURL: activeURL)
                })
            case .docs:
                toolSlots.append(TouchBarDriver.Slot(
                    key: "tab-tool-bold",
                    title: "B Bold",
                    help: "Toggle bold",
                    width: 55
                ) {
                    TabContextRouter.execute(actionID: "docs.bold", activeURL: activeURL)
                })
                toolSlots.append(TouchBarDriver.Slot(
                    key: "tab-tool-note",
                    title: "💬 Note",
                    help: "Add comment",
                    width: 55
                ) {
                    TabContextRouter.execute(actionID: "docs.note", activeURL: activeURL)
                })
            case .general:
                toolSlots = []
                }
            }

            if siteControls.pending != nil {
                // A pending confirmation owns the strip so it can never be
                // clipped: nothing behind it stays tappable.
                body = siteConfirmationSlots()
            } else if allTabs.isEmpty {
                body = toolSlots + [
                    .init(key: "no-tabs", title: "No tabs found", help: "Open or focus a tab in Chrome", isEnabled: false, width: 130, action: {})
                ]
            } else {
                let bundle = chromeBridge.currentBundle
                // Tabs take every point left over after Back and this site's own
                // tools. Home, Shots and Stack deliberately do not appear here so
                // the strip is as wide as the bar allows.
                let toolWidth = toolSlots.reduce(CGFloat(0)) { $0 + ($1.width ?? 0) }
                let tabsWidth = max(170, min(520, 650 - 52 - toolWidth - CGFloat(toolSlots.count) * 6))
                let scrollTabs = ScrollableTabsView(tabs: allTabs, bundle: bundle, width: tabsWidth) { [weak self] index, b in
                    self?.chromeBridge.activateTab(index: index, bundle: b)
                }
                let activeID = activeTab?.id ?? 0
                body = toolSlots + [
                    TouchBarDriver.Slot(
                        key: "scrollable-tabs-\(activeID)-\(allTabs.count)",
                        title: "Tabs",
                        help: "Slide your finger to scroll through open Chrome tabs",
                        width: tabsWidth,
                        customView: scrollTabs,
                        action: {}
                    )
                ]
            }
        case .sheetsTools:
            let items = sheetsTools.itemsForCurrentPage()
            let activeURL = chromeBridge.activeTab?.url ?? nativeMenus.snapshot?.route?.url
            body = items.map { item in
                TouchBarDriver.Slot(
                    key: "sheets-tool-\(item.rawValue)",
                    title: item.title,
                    help: item.help,
                    width: item.width
                ) { [weak self] in
                    self?.sheetsTools.execute(item, currentURL: activeURL)
                }
            }
            body.append(TouchBarDriver.Slot(
                key: "sheets-tools-page",
                title: "\(sheetsTools.currentPage + 1)/\(SheetsToolsController.totalPages) ›",
                help: "More spreadsheet tools",
                width: 48
            ) { [weak self] in
                guard let self = self else { return }
                self.sheetsTools.nextPage()
                self.rebuildBars()
                self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
            })
        case .home:
            body = RelayHierarchy.items(on: .home).map { item in
                switch item { case .page(let page): return groupSlot(page); case .command(let command): return commandSlot(command) }
            }
            // A desktop rule adds exactly one compact group button. Home's width
            // budget cannot hold a full site row beside five families and the shell.
            if let rule = desktopSiteRule { body.append(siteGroupSlot(rule)) }
        case .siteTools:
            guard let ruleID = siteControls.detection.ruleID, let rule = siteControls.matchedRule else {
                body = [.init(key: "site-none", title: "No site matched", help: "Focus a page or application your rules cover, then open Site tools again.", isEnabled: false, width: 200, action: {}),
                        commandSlot(.editSites)]
                break
            }
            var items = siteControls.buttonsForCurrentPage.map { siteButtonSlot($0, ruleID: ruleID, widthCap: 124) }
            let pages = SiteControlsPolicy.pageCount(siteControls.overflowButtons.count)
            items.append(.init(key: "site-page-\(siteControls.page)-\(pages)", title: "\(siteControls.page + 1)/\(pages) ›",
                               help: "More buttons for \(rule.name); every button stays reachable", isEnabled: pages > 1, width: 40) { [weak self] in
                guard let self = self else { return }
                self.siteControls.nextPage()
                self.rebuildBars(); self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
            })
            items.append(commandSlot(.editSites))
            body = items
        case .toolbox:
            var tools = toolbox.toolsForCurrentPage().map { tool in
                TouchBarDriver.Slot(key: "toolbox-\(tool.rawValue)", title: tool.title, help: tool.help,
                                    width: CGFloat(min(100, max(56, 30 + Double(tool.title.count) * 6.6)))) { [weak self] in
                    self?.toolbox.run(tool)
                }
            }
            tools.append(.init(key: "toolbox-page-\(toolbox.page)", title: "\(toolbox.page + 1)/\(toolbox.pageCount) ›",
                               help: "More local tools; every tool stays reachable", isEnabled: toolbox.pageCount > 1, width: 44) { [weak self] in
                guard let self = self else { return }
                self.toolbox.nextPage()
                self.rebuildBars(); self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
            })
            tools.append(.init(key: "toolbox-undo", title: "↩ Undo", help: "Restore the clipboard text from before the last tool. RelayBar holds at most \(ToolboxPolicy.undoDepth) steps in memory.", isEnabled: toolbox.canUndo, width: 66) { [weak self] in
                self?.toolbox.undo()
            })
            body = tools
        default:
            body = RelayHierarchy.items(on: navigation.page).map { item in
                switch item { case .page(let page): return groupSlot(page); case .command(let command): return commandSlot(command) }
            }
        }
        var slots: [TouchBarDriver.Slot] = []
        if navigation.page != .home {
            let parent = navigation.backDestination?.title ?? "Home"
            slots.append(.init(key: "family-back", title: "‹ Back", help: "Back to \(parent). Cancel pending menu actions; do not hide the bar.", width: 52) { [weak self] in self?.navigateBack() })
            if navigation.page != .websiteTabs {
                slots.append(.init(key: "family-home", title: "⌂", help: "Home — all five button families", width: 32) { [weak self] in self?.navigate(to: .home) })
            }
        }
        slots += body
        slots += realityTouchBarSlots()
        // The evidence chip rides beside the fixed shell controls on every page,
        // so a settled or unsettled receipt stays visible across app switches.
        slots += claimLedger?.chipSlots() ?? []
        // A retired contextual view can never run even if AppKit delivers a delayed tap.
        let ticket = navigation.generation
        let contextual = slots.map { item -> TouchBarDriver.Slot in
            var bound = item
            bound.key = "family-\(ticket.uuidString)-\(item.key)"
            let action = item.action
            bound.action = { [weak self] in
                guard let self = self, self.navigation.accepts(ticket), item.isEnabled else { return }
                self.screenshotPresentation.cancelRecovery()
                action()
            }
            return bound
        }
        return persistentShellSlots(contextual: contextual)
    }
    private func realityTouchBarSlots() -> [TouchBarDriver.Slot] {
        guard let store = store, let realities = try? store.listRealities(), !realities.isEmpty else { return [] }
        let index = realitySelectionIndex(in: realities)
        let current = realities[index]
        let time = DateFormatter.localizedString(from: current.savedAt, dateStyle: .none, timeStyle: .short)
        return [
            .init(key: "reality-previous-\(index)", title: "‹", help: "Select the previous saved reality", isEnabled: index < realities.count - 1, width: 30) { [weak self] in
                self?.moveRealitySelection(by: 1)
            },
            .init(key: "reality-current-\(current.id.uuidString)", title: "◉ \(time)", help: current.name, width: 82) { [weak self] in
                self?.showRealityTimeline()
            },
            .init(key: "reality-next-\(index)", title: "›", help: "Select the next saved reality", isEnabled: index > 0, width: 30) { [weak self] in
                self?.moveRealitySelection(by: -1)
            },
            .init(key: "reality-fork", title: "FORK", help: "Open the timeline to fork the selected reality", width: 48) { [weak self] in
                self?.showRealityTimeline()
            }
        ]
    }

    private func realitySelectionIndex(in realities: [RealitySnapshot]) -> Int {
        guard let id = realitySelectionID, let index = realities.firstIndex(where: { $0.id == id }) else { return 0 }
        return index
    }

    private func moveRealitySelection(by offset: Int) {
        guard let store = store, let realities = try? store.listRealities(), !realities.isEmpty else { return }
        let index = realitySelectionIndex(in: realities)
        let next = min(max(0, index + offset), realities.count - 1)
        realitySelectionID = realities[next].id
        realityTimeline?.select(id: realities[next].id, realities: realities)
        setStatus("Selected \(realities[next].name). Open the timeline to restore or compare it.")
        rebuildBars()
    }

    private func recordAutomaticReality(_ name: String) {
        guard let store = store, draft != nil else { return }
        let root = lastRealityRoot ?? inferExternalWorkingDirectory()
        guard let root = root, let git = try? readGitSnapshot(at: root) else { return }
        do {
            let packet = try currentDraft()
            let checkpoint = Checkpoint(project: configuration.selectedProject, capture: capture, task: taskField.stringValue, draft: packet)
            let reality = RealitySnapshot(name: name, project: configuration.selectedProject, checkpoint: checkpoint,
                                          gitRoot: root, gitSnapshot: GitSnapshotRecord(snapshot: git.snapshot, commit: git.commit),
                                          parentID: realitySelectionID, activeAppBundle: liveBundle,
                                          browserTabs: capturedBrowserTabs(), dirtyWorkingTree: git.dirty)
            _ = try store.saveReality(reality)
            realitySelectionID = reality.id
        } catch {
            // Automatic capture is best effort. It never interrupts composing.
        }
    }

    private func capturedBrowserTabs() -> [RealityBrowserTab] {
        guard !chromeBridge.currentBundle.isEmpty, ChromeTabBridge.supportedBrowsers.contains(chromeBridge.currentBundle) else { return [] }
        return chromeBridge.tabs.map { tab in
            RealityBrowserTab(browserBundle: chromeBridge.currentBundle, windowIndex: 0, tabIndex: tab.index,
                              title: tab.title, url: tab.url, isSelected: tab.isSelected)
        }
    }

    private func inferExternalWorkingDirectory() -> String? {
        guard let app = lastExternalApp, !app.isTerminated else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-d", "cwd", "-p", "\(app.processIdentifier)", "-Fn"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = nil
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        guard let line = output.split(separator: "\\n").first(where: { $0.hasPrefix("n") }) else { return nil }
        let project = ProjectDetector.detect(from: String(line.dropFirst()))
        return project.root.isEmpty ? nil : project.root
    }

    private func persistentShellSlots(contextual: [TouchBarDriver.Slot]) -> [TouchBarDriver.Slot] {
        guard shellState.relayVisible else { return contextual }
        var result = contextual
        result.append(.init(key: TouchBarDriver.flexibleSpaceKey, title: "", help: "", isEnabled: false, action: {}))
        // The mini-player is always pinned. Only when the active browser tab is
        // the YouTube watch page does the small volume slider also appear.
        let activeURL = chromeBridge.activeTab?.url ?? ""
        let ytForeground = activeURL.contains("youtube.com/watch") || activeURL.contains("youtu.be/")
        if let ytMini = youTube.persistentSlots(expanded: ytForeground) {
            result.append(contentsOf: ytMini)
        }
        if let slot = shellAppSlot(.chrome) { result.append(slot) }
        if let slot = shellAppSlot(.claude) { result.append(slot) }
        if let slot = shellAppSlot(.chatgpt) { result.append(slot) }
        result.append(.init(key: "shell-mac", title: "", help: "Use the default macOS Touch Bar. RelayBar will not reclaim it on ordinary app switches.", width: 34) { [weak self] in
            self?.enterMacTouchBarMode()
        })
        return result
    }

    private func shellAppURL(_ app: PersistentShellApp) -> URL? {
        let configured: URL?
        switch app {
        case .chatgpt: configured = appURL(for: .chatgpt)
        case .claude: configured = appURL(for: .claude)
        case .chrome: configured = nil
        }
        return PersistentShellMac.applicationURL(for: app, configuredAssistantURL: configured)
    }

    private func shellAppSlot(_ app: PersistentShellApp) -> TouchBarDriver.Slot? {
        let configured: URL?
        switch app {
        case .chatgpt: configured = appURL(for: .chatgpt)
        case .claude: configured = appURL(for: .claude)
        case .chrome: configured = nil
        }
        guard AppSwitcher.isRunning(app, configuredAssistantURL: configured) else { return nil }
        let url = shellAppURL(app)
        let icon = PersistentShellMac.icon(for: url)
        let installed = url != nil
        let fallback: String
        switch app { case .chrome: fallback = "C"; case .claude: fallback = "A"; case .chatgpt: fallback = "G" }
        return .init(key: "shell-app-\(app.rawValue)", title: icon == nil ? fallback : "",
                     help: installed ? "Open \(app.displayName) and switch RelayBar to that app’s controls." : "\(app.displayName) is not installed or could not be located.",
                     image: icon, isEnabled: installed, width: 36) { [weak self] in
            self?.activateShellApp(app)
        }
    }

    private func activateShellApp(_ app: PersistentShellApp) {
        guard shellState.relayVisible, let url = shellAppURL(app) else { return }
        screenshotPresentation.cancelRecovery()
        nativeMenus.cancelInteraction()
        stopPinnedChats()
        if app == .chrome && liveProfile == "sheets" { navigation.open(.appControls) }
        else { navigation.home() }
        reconcileNavigation()
        rebuildBars()

        let standardized = url.standardizedFileURL.path
        if let running = NSWorkspace.shared.runningApplications.first(where: { running in
            app.bundleIdentifiers.contains(running.bundleIdentifier ?? "") || running.bundleURL?.standardizedFileURL.path == standardized
        }), !running.isTerminated {
            running.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.async { [weak self] in
                self?.refreshAppContext(); self?.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
            }
            return
        }
        let options = NSWorkspace.OpenConfiguration(); options.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: options) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.setStatus("Could not open \(app.displayName): \(error.localizedDescription)")
                } else {
                    self.refreshAppContext(); self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
                }
            }
        }
    }

    private func groupSlot(_ page: RelayPage, compact: String? = nil) -> TouchBarDriver.Slot {
        let shortNames: [RelayPage: String] = [.stack: "Stack ›", .stackClips: "Clips ›", .modes: "Mode ›",
            .connections: "Connections ›", .assistantSettings: "Assistants ›", .promptLibrary: "More ›",
            .buildPrompts: "Build / review ›", .writePrompts: "Writing ›"]
        var title = compact ?? shortNames[page] ?? page.title + " ›"
        if page == .appControls { title = liveProfile == "sheets" ? "Sheets ›" : "App controls ›" }
        return .init(key: "group-\(page.rawValue)", title: title,
                     help: "Open \(page.breadcrumb). This group does not execute any child action.", width: navigation.page == .home ? 106 : (compact != nil ? 60 : 96)) { [weak self] in
            self?.navigate(to: page)
        }
    }
    private func commandSlot(_ command: RelayCommand) -> TouchBarDriver.Slot {
        var title = command.title
        var enabled = true
        switch command {
        case .prompt(let action):
            // Suggestions are marked in place, never moved or substituted under a finger.
            if ContextEngine.actions(mode: configuration.mode, text: capture.text).contains(action) { title = "★ " + title }
        case .collectStack: title = contextStack?.session.collecting == true ? "Ⅱ Pause" : "● Collect"
        case .selectGPT: title = (configuration.target == .chatgpt ? "✓ " : "") + title
        case .selectClaude: title = (configuration.target == .claude ? "✓ " : "") + title
        case .reviewDraft, .copyDraft, .copyAndOpen, .saveCheckpoint: enabled = draft != nil && !(draftView?.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        case .prefillClaude: enabled = draft != nil && configuration.target == .claude && !(draftView?.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        case .watchScreenshots: title = screenshotShelf?.watching == true ? "Ⅱ Stop images" : "● Collect images"
        case .autoScreenshots: title = "Auto-open: " + (screenshotPresentation.autoOpenEnabled ? "On" : "Off")
        case .appAware: title = "App-aware: " + (appAwareEnabled ? "On" : "Off")
        case .overlay: title = shellState.relayVisible ? "Shell: On" : "Resume shell"
        case .nativeDetection: title = nativeMenusEnabled ? "Sheets: On" : "Sheets: Off"
        case .nativeConfirmation: title = nativeAskActions ? "Confirm: On" : "Confirm: Off"
        case .followAssistant: title = "Follow: " + (configuration.followDesktopAssistant ? "On" : "Off")
        case .preferDesktop: title = "Desktop: " + (configuration.preferDesktop ? "On" : "Off")
        default: break
        }
        return .init(key: command.id, title: title, help: command.help, isEnabled: enabled, width: 96) { [weak self] in self?.runFamilyCommand(command) }
    }
    private func runFamilyCommand(_ command: RelayCommand) {
        switch command {
        case .prompt(let action): performAction(action)
        case .captureSelection: captureSelection()
        case .captureClipboard: captureClipboard()
        case .editReference: showPanel(); panel.makeFirstResponder(referenceView)
        case .clearSession: confirmClearSession()
        case .collectStack: toggleStackCollection()
        case .pasteStack: pasteStackClip()
        case .reviewStack: reviewStack()
        case .clearStack: clearStack()
        case .chooseScreenshotFolder: chooseScreenshotFolder()
        case .watchScreenshots: toggleScreenshotWatching()
        case .autoScreenshots: toggleScreenshotAutoOpen()
        case .addClipboardImage: addScreenshotClipboard()
        case .clearScreenshots: clearScreenshotShelf()
        case .selectGPT: setTarget(.chatgpt)
        case .selectClaude: setTarget(.claude)
        case .openGPT: openPinnedAssistant(.chatgpt)
        case .openClaude: openPinnedAssistant(.claude)
        case .pinsStatus: showPinnedStatus()
        case .reviewDraft: showPanel(); panel.makeFirstResponder(draftView)
        case .copyDraft: copyDraft()
        case .copyAndOpen: copyAndOpen()
        case .prefillClaude: showPanel(); prefillClaude()
        case .saveCheckpoint: showPanel(); saveCheckpoint()
        case .loadCheckpoint: loadCheckpointFromMenu()
        case .editProject: editProject(isNew: false)
        case .newProject: editProject(isNew: true)
        case .revealData: revealData()
        case .appAware: toggleAppAware()
        case .overlay: toggleOverlay()
        case .disableOverlay: disableOverlay()
        case .enableNative: enableNativeControls()
        case .nativeDetection: toggleNativeDetection()
        case .nativeConfirmation: toggleNativeConfirmation()
        case .nativeReport: showNativeReport()
        case .accessibility: requestAccessibility()
        case .followAssistant: toggleFollow()
        case .preferDesktop: toggleDesktop()
        case .chooseGPTApp: chooseApp(.chatgpt)
        case .chooseClaudeApp: chooseApp(.claude)
        case .about: showAbout()
        case .verifyLedger: reviewClaimsForTheDraft()
        case .auditReply: auditClipboardReply()
        case .showClaimLedger: showClaimLedger()
        case .declareVerifyCommand: claimLedger?.presentVerifyCommandEditor()
        case .askAboutPage: askAboutPage()
        case .editSites: editSiteRules()
        }
        rebuildBars(); updateOverlay(for: NSWorkspace.shared.frontmostApplication)
    }
    private func confirmClearSession() {
        showPanel()
        let alert = NSAlert(); alert.messageText = "Clear this session's text?"
        alert.informativeText = "This clears only the current in-memory reference, task and draft. Context Stack clips, screenshots, saved checkpoints and the system clipboard are unchanged."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Clear session")
        if alert.runModal() == .alertSecondButtonReturn { clearSession() }
    }
}

// MARK: - Native family construction checks (explicit Mac-only command; never run on launch)
extension RelayAppDelegate {
    func runButtonFamiliesSelfTest() -> Int32 {
        var passed = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            passed += 1; print("PASS: \(name)")
        }
        buildPanel(selfTest: true) // Construct only; do not order front, save window state or activate an app.
        let board = NSPasteboard(name: NSPasteboard.Name("local.relaybar.families-test.\(UUID().uuidString)"))
        contextStack = ContextStackController(projectID: "test", projectName: "Test", board: board)
        pinnedChats = PinnedChatsController() // No start / update / sidebar scan.
        defer {
            contextStack?.stopForTermination(); pinnedChats?.stopForTermination()
            board.releaseGlobally(); panel.close()
        }
        for page in RelayPage.allCases {
            navigation.open(page)
            let slots = familySlots()
            check(Set(slots.map(\.key)).count == slots.count, "Unique items: \(page.title)")
            let contextual = slots.filter { $0.key.hasPrefix("family-") }
            check(contextual.reduce(CGFloat(0)) { $0 + ($1.width ?? 0) } + CGFloat(max(0, contextual.count-1)) * 6 <= 650, "Contextual budget: \(page.title)")
            check(slots.reduce(CGFloat(0)) { $0 + ($1.width ?? 0) } + CGFloat(max(0, slots.count-1)) * 6 <= 820, "Total bar budget: \(page.title)")
            panelBar.update(slots)
            for id in panelBar.bar.defaultItemIdentifiers where id != .flexibleSpace {
                check(panelBar.touchBar(panelBar.bar, makeItemForIdentifier: id) is NSCustomTouchBarItem, "Native item: \(page.title) / \(id.rawValue)")
            }
        }
        let before = configuration.target
        navigation.home()
        let old = familySlots().first { $0.key.hasSuffix("group-prompting") }!
        navigation.open(.context); old.action()
        check(navigation.page == .context && configuration.target == before, "Retired button is inert")
        check(contextStack?.session.collecting == false, "Constructing Stack did not start collection")
        for page in [RelayPage.prompting, .context, .chats, .workspace, .settings] {
            check(familyMenu(page).submenu != nil, "Native menu family: \(page.title)")
        }
        print("PASS: \(passed) native construction checks. No assistant read, general clipboard access, overlay presentation, copy, paste or send. Hardware rendering is still a manual check.")
        return 0
    }
}

// MARK: - Your Sites, Toolbox and page→prompt integration
//
// AppMain owns presentation and the app-level effects a site button can name
// (Quick Action, plugin command, navigation, page reference). The matching,
// validation, confirmation gating and transforms live in the engines.
extension RelayAppDelegate {
    /// The live identity a site rule is matched against. Browser page identity
    /// comes from the exposed tab URL, never from a window title guess.
    private func currentSiteTarget() -> SiteTarget {
        let front = NSWorkspace.shared.frontmostApplication
        let bundle = front?.bundleIdentifier ?? liveBundle
        let isBrowser = !bundle.isEmpty && (chromeBridge.isSupported(bundle: bundle) || NativeMenuPolicy.browserBundles.contains(bundle))
        let tab = isBrowser ? chromeBridge.activeTab : nil
        return SiteTarget(url: tab?.url ?? "", title: tab?.title ?? (front?.localizedName ?? liveAppName),
                          bundleID: bundle, isBrowser: isBrowser)
    }

    /// One explicit read, requested only by a button that names {selection}.
    private func currentSelection() -> String {
        guard let front = NSWorkspace.shared.frontmostApplication, !ownApp(front) else { return "" }
        return RBBridge.selectedText(forPID: front.processIdentifier)["text"] ?? ""
    }

    @discardableResult private func refreshSiteControls() -> Bool {
        siteControls.rules = configuration.siteRules
        return siteControls.refresh()
    }

    private func wireSiteControls() {
        siteControls.rules = configuration.siteRules
        siteControls.currentTarget = { [weak self] in self?.currentSiteTarget() ?? SiteTarget() }
        siteControls.selectionProvider = { [weak self] in self?.currentSelection() ?? "" }
        siteControls.onStatus = { [weak self] message in self?.setStatus(message) }
        siteControls.onRelay = { [weak self] destination in self?.navigate(to: destination) }
        siteControls.onPrompt = { [weak self] action in self?.askAboutPage(action: action) }
        siteControls.onQuickAction = { [weak self] id in self?.runQuickAction(id: id) }
        siteControls.onPluginCommand = { [weak self] plugin, command in self?.runPluginCommand(plugin: plugin, command: command) }
        toolbox.onStatus = { [weak self] message in self?.setStatus(message) }
        if let store = store {
            pluginManager = PluginManager(baseDirectory: store.directory)
            pluginManager?.scan()
        }
    }

    func displayTitle(_ button: SiteButton) -> String { SiteControlsPolicy.displayTitle(button) }

    private func siteButtonSlot(_ button: SiteButton, ruleID: String, widthCap: Double) -> TouchBarDriver.Slot {
        let confirmation = button.requiresConfirmation
        let help = "\(button.effect.kindName) for this site. "
            + (confirmation ? "RelayBar asks before running it." : "This effect cannot change another application's data.")
        return TouchBarDriver.Slot(key: "site-\(ruleID)-\(button.id)", title: SiteControlsPolicy.displayTitle(button),
                                   help: help, width: CGFloat(min(widthCap, SiteControlsPolicy.width(for: button)))) { [weak self] in
            guard let self = self else { return }
            self.siteControls.request(button, ruleID: ruleID)
            self.rebuildBars(); self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
        }
    }

    private func siteGroupSlot(_ rule: SiteRule) -> TouchBarDriver.Slot {
        TouchBarDriver.Slot(key: "site-group-\(rule.id)", title: "Site ›",
            help: "Open all \(rule.buttons.count) buttons for \(rule.name). Opening the group runs nothing.",
            width: 58) { [weak self] in self?.navigate(to: .siteTools) }
    }

    /// A pending confirmation replaces the contextual body so it can never be
    /// clipped off the strip: nothing else from that page remains tappable.
    private func siteConfirmationSlots() -> [TouchBarDriver.Slot] {
        guard let pending = siteControls.pending else { return [] }
        let ticket = siteControls.ticket.uuidString
        return [
            .init(key: "site-confirm-\(ticket)", title: "Run: " + String(pending.label.suffix(34)),
                  help: "Run “\(pending.label)”. This can change another application's data or send input. Nothing has run yet.",
                  width: 300) { [weak self] in
                guard let self = self else { return }
                self.siteControls.confirmPending()
                self.rebuildBars(); self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
            },
            .init(key: "site-cancel-\(ticket)", title: "Cancel",
                  help: "Cancel without running the site button.", width: 80) { [weak self] in
                guard let self = self else { return }
                self.siteControls.cancelPending()
                self.rebuildBars(); self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
            }
        ]
    }

    /// True when a desktop application rule owns the frontmost app. Browser
    /// pages are handled by the Tabs page instead.
    private var desktopSiteRule: SiteRule? {
        guard case .matched(let match) = siteControls.detection, match.basis == .app else { return nil }
        return siteControls.matchedRule
    }

    // MARK: - Ask about this page

    private func askAboutPage(action: PromptAction = .explain) {
        let target = currentSiteTarget()
        let input = PageContextInput(url: target.url, title: target.title)
        switch pageContextMode {
        case .link:
            finishAskAboutPage(input: input, action: action, mode: .link)
        case .selection:
            var withSelection = input
            withSelection.selection = currentSelection()
            finishAskAboutPage(input: withSelection, action: action, mode: .selection)
        case .excerpt:
            guard target.isBrowser, let page = target.page else {
                showError("Excerpt mode needs an identified https page in a supported browser. Switch the page context to Link only from RB → Context → Capture.")
                return
            }
            guard PageContextPolicy.allowsExcerpt(host: page.host) else {
                showError("RelayBar refuses to read page text on \(page.host). Switch the page context to Link only.")
                return
            }
            guard let front = NSWorkspace.shared.frontmostApplication, !ownApp(front),
                  let bundle = front.bundleIdentifier else {
                showError("Focus the page you want to reference, then ask again.")
                return
            }
            let pid = front.processIdentifier
            PageTextReader.shared.read(pid: pid, bundle: bundle) { [weak self] excerpt in
                guard let self = self else { return }
                guard let excerpt = excerpt else {
                    self.showError("The page excerpt could not be read inside RelayBar's bounded budget. Nothing was captured or guessed; Link only still works.")
                    return
                }
                var withExcerpt = input
                withExcerpt.excerpt = excerpt
                self.finishAskAboutPage(input: withExcerpt, action: action, mode: .excerpt)
            }
        }
    }

    private func finishAskAboutPage(input: PageContextInput, action: PromptAction, mode: PageContextMode) {
        do {
            let reference = try PageContextPolicy.build(input, mode: mode)
            applyCapture(reference.text, origin: reference.origin)
            currentAction = action
            composeSelected()
            setStatus("Page reference ready (\(mode.title)). Review the draft, then copy or open it; nothing was sent.")
        } catch { showError(error.localizedDescription) }
    }

    private func setPageContextMode(_ mode: PageContextMode) {
        pageContextMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "pageContext.mode")
        for (key, item) in pageContextMenuItems { item.state = key == mode ? .on : .off }
        setStatus("Page context: \(mode.title). \(mode.help)")
    }

    // MARK: - Site buttons that name a local command

    private func runQuickAction(id: UUID) {
        guard let action = configuration.quickActions.first(where: { $0.id == id }) else {
            setStatus("That site button names a Quick Action that no longer exists. Nothing was run.")
            return
        }
        let runner = quickActionRunner ?? ActionRunner()
        quickActionRunner = runner
        guard !runner.isRunning else { setStatus("A Quick Action is already running; wait for it to finish. Nothing new was started."); return }
        let panel = actionOutputPanel ?? ActionOutputPanel()
        actionOutputPanel = panel
        if action.showOutput {
            panel.start(actionName: action.name, command: action.command)
            runner.onOutput = { [weak panel] text in panel?.appendOutput(text) }
        }
        runner.onComplete = { [weak self] result in
            self?.actionOutputPanel?.finish(result: result)
            self?.setStatus(result.summary)
        }
        runner.run(action, projectRoot: lastRealityRoot)
    }

    private func runPluginCommand(plugin: String, command: String) {
        guard let manager = pluginManager,
              let installed = manager.plugins.first(where: { $0.id == plugin && $0.isEnabled }),
              let entry = installed.manifest.commands.first(where: { $0.name == command }) else {
            setStatus("That site button names a plugin command that is not installed and enabled. Nothing was run.")
            return
        }
        manager.execute(plugin: installed, command: entry, projectRoot: lastRealityRoot) { [weak self] output, code in
            guard let self = self else { return }
            let panel = self.actionOutputPanel ?? ActionOutputPanel()
            self.actionOutputPanel = panel
            let finishedAt = Date()
            panel.start(actionName: "\(installed.manifest.name): \(entry.name)", command: entry.script)
            panel.appendOutput(output)
            panel.finish(result: ActionResult(actionID: UUID(), output: output, exitCode: code,
                                              startedAt: finishedAt, finishedAt: finishedAt, command: entry.script))
            self.setStatus(code == 0 ? "Plugin command finished. Review the output window." : "Plugin command exited with code \(code). Review the output window.")
        }
    }

    // MARK: - Editor

    private func editSiteRules() {
        let editor = siteRulesEditor ?? SiteRulesEditor()
        siteRulesEditor = editor
        editor.onSave = { [weak self] rules in
            guard let self = self else { return }
            self.configuration.siteRules = rules
            self.saveConfiguration()
            self.siteControls.rules = rules
            self.siteControls.refresh()
            self.setStatus("Saved \(rules.count) site rule\(rules.count == 1 ? "" : "s") in your local configuration.")
            self.rebuildBars(); self.updateOverlay(for: NSWorkspace.shared.frontmostApplication)
        }
        editor.load(rules: configuration.siteRules, quickActions: configuration.quickActions,
                    plugins: pluginManager?.plugins ?? [],
                    currentTarget: { [weak self] in self?.currentSiteTarget() ?? SiteTarget() })
        showPanel()
        editor.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Claim ledger (presentation adapter; the feature engine stays in Core)
extension RelayAppDelegate {
    private func refreshClaimLedgerUI() {
        rebuildBars()
        updateOverlay(for: NSWorkspace.shared.frontmostApplication)
    }

    /// The ledger checks one repository at one revision. The root comes from the
    /// reality timeline's project or the focused app's working directory, and is
    /// never guessed from the reviewed text.
    private func claimGitRoot() -> String? {
        if let root = lastRealityRoot, !root.isEmpty { return root }
        return inferExternalWorkingDirectory()
    }

    private func reviewClaimsForTheDraft() {
        let draftText = draftView?.string ?? ""
        let referenceText = referenceView?.string ?? ""
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? referenceText : draftText
        let source: ClaimSource = draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .reference : .draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("There is no reference or draft text to review. Capture a reference first; nothing was executed.")
            return
        }
        guard let root = claimGitRoot() else {
            setStatus("RelayBar needs this project's root to check claims against. Focus the project in a terminal or open a saved reality for it; nothing was executed.")
            claimLedger?.showLedger()
            return
        }
        if let error = claimLedger?.review(text, source: source, gitRoot: root) {
            setStatus(error)
        } else {
            setStatus(claimLedger?.message ?? "Reviewed the text as claims. Nothing has been executed.")
        }
        navigate(to: .verify)
    }

    private func auditClipboardReply() {
        if claimLedger?.ledger == nil {
            setStatus("Review and verify some text first, so there is a receipt to compare the reply against. Nothing was sent.")
            return
        }
        claimLedger?.auditClipboardReply()
        let findings = claimLedger?.findings.count ?? 0
        setStatus(findings == 0
            ? "Audited the clipboard text: nothing it says was left unverified by this receipt."
            : "Audited the clipboard text: \(findings) statement(s) this receipt does not support. RelayBar re-checked nothing.")
        if findings > 0 { claimLedger?.showLedger() }
    }

    private func showClaimLedger() {
        claimLedger?.showLedger()
    }
}

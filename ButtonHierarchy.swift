import Foundation

/// Presentation-only taxonomy. Feature engines own their data, permissions and effects.
/// A group button changes a page; it must never execute a child action implicitly.
public enum RelayPage: String, CaseIterable, Codable {
    case home, prompting, promptLibrary, buildPrompts, writePrompts, draft
    case context, capture, stack, stackClips, stackOptions, screenshots, screenshotOptions
    case chats, pins, destinations
    case workspace, projects, projectOptions, modes, checkpoints, appControls
    case settings, layout, connections, assistantSettings
    case verify
    case websiteTabs, sheetsTools, siteTools
    case toolbox

    public var title: String {
        switch self {
        case .home: return "Home"
        case .prompting: return "Prompting"
        case .promptLibrary: return "More prompts"
        case .buildPrompts: return "Build & review"
        case .writePrompts: return "Write & refine"
        case .draft: return "Draft"
        case .context: return "Context"
        case .capture: return "Capture"
        case .stack: return "Context Stack"
        case .stackClips: return "Recent clips"
        case .stackOptions: return "Stack options"
        case .screenshots: return "Screenshots"
        case .screenshotOptions: return "Screenshot options"
        case .chats: return "Chats"
        case .pins: return "Pinned chats"
        case .destinations: return "Destination"
        case .workspace: return "Workspace"
        case .projects: return "Projects"
        case .projectOptions: return "Project options"
        case .modes: return "Workflow mode"
        case .checkpoints: return "Checkpoints"
        case .appControls: return "App controls"
        case .settings: return "Settings"
        case .layout: return "Layout & bar"
        case .connections: return "Native controls"
        case .assistantSettings: return "Assistant settings"
        case .verify: return "Verify"
        case .websiteTabs: return "Tabs"
        case .sheetsTools: return "Sheets Tools"
        case .siteTools: return "Site tools"
        case .toolbox: return "Toolbox"
        }
    }
    public var parent: RelayPage? {
        switch self {
        case .home: return nil
        case .prompting, .context, .chats, .workspace, .settings, .websiteTabs: return .home
        case .sheetsTools: return .appControls
        case .siteTools: return .websiteTabs
        case .promptLibrary, .draft: return .prompting
        case .buildPrompts, .writePrompts: return .promptLibrary
        case .capture, .stack, .verify, .screenshots: return .context
        case .stackClips, .stackOptions: return .stack
        case .screenshotOptions: return .screenshots
        case .pins, .destinations: return .chats
        case .projects, .modes, .checkpoints, .appControls, .toolbox: return .workspace
        case .projectOptions: return .projects
        case .layout, .connections, .assistantSettings: return .settings
        }
    }
    public var path: [RelayPage] { (parent?.path ?? []) + [self] }
    public var breadcrumb: String { path.map(\.title).joined(separator: " › ") }
}

public enum RelayCommand: Equatable, Hashable {
    case prompt(PromptAction)
    case captureSelection, captureClipboard, editReference, clearSession
    case collectStack, pasteStack, reviewStack, clearStack
    case chooseScreenshotFolder, watchScreenshots, autoScreenshots, addClipboardImage, clearScreenshots
    case selectGPT, selectClaude, openGPT, openClaude, pinsStatus
    case reviewDraft, copyDraft, copyAndOpen, prefillClaude, saveCheckpoint, loadCheckpoint
    case editProject, newProject, revealData
    case appAware, overlay, disableOverlay, enableNative, nativeDetection, nativeConfirmation, nativeReport, accessibility
    case followAssistant, preferDesktop, chooseGPTApp, chooseClaudeApp, about
    case verifyLedger, auditReply, showClaimLedger, declareVerifyCommand
    case askAboutPage, editSites

    public var id: String {
        if case .prompt(let action) = self { return "prompt-" + action.rawValue }
        return String(describing: self)
    }
    public var title: String {
        switch self {
        case .prompt(let action): return action.title
        case .captureSelection: return "Selection"
        case .captureClipboard: return "Clipboard text"
        case .editReference: return "Edit reference"
        case .clearSession: return "Clear session…"
        case .collectStack: return "Collect"
        case .pasteStack: return "Paste clip"
        case .reviewStack: return "Review stack"
        case .clearStack: return "Clear stack…"
        case .chooseScreenshotFolder: return "Save folder…"
        case .watchScreenshots: return "Collect images"
        case .autoScreenshots: return "Auto-open"
        case .addClipboardImage: return "Clipboard image"
        case .clearScreenshots: return "Clear shelf…"
        case .selectGPT: return "ChatGPT"
        case .selectClaude: return "Claude"
        case .openGPT: return "Open GPT"
        case .openClaude: return "Open Claude"
        case .pinsStatus: return "Pins status"
        case .reviewDraft: return "Review draft"
        case .copyDraft: return "Copy draft"
        case .copyAndOpen: return "Copy + Open"
        case .prefillClaude: return "Prefill Claude…"
        case .saveCheckpoint: return "Save…"
        case .loadCheckpoint: return "Load…"
        case .editProject: return "Edit brief…"
        case .newProject: return "New project…"
        case .revealData: return "Local data"
        case .appAware: return "App-aware"
        case .overlay: return "Persistent shell"
        case .disableOverlay: return "Pause shell"
        case .enableNative: return "Enable native…"
        case .nativeDetection: return "Sheets detection"
        case .nativeConfirmation: return "Ask before run"
        case .nativeReport: return "Connection report"
        case .accessibility: return "Permission…"
        case .followAssistant: return "Follow assistant"
        case .preferDesktop: return "Prefer desktop"
        case .chooseGPTApp: return "GPT app…"
        case .chooseClaudeApp: return "Claude app…"
        case .about: return "About / privacy"
        case .askAboutPage: return "Ask about page"
        case .editSites: return "Edit sites…"
        case .verifyLedger: return "Verify claims"
        case .auditReply: return "Audit reply"
        case .showClaimLedger: return "Claim ledger"
        case .declareVerifyCommand: return "Verify command…"
        }
    }
    public var help: String {
        switch self {
        case .prompt(let action): return "Compose \(action.title) from your explicit reference. Review first; nothing is sent."
        case .clearSession: return "Confirm before clearing the in-memory reference, task and draft. Checkpoints and clipboard are untouched."
        case .selectGPT, .selectClaude: return "Change the prompt destination, not the open chat. Changing destination invalidates the current draft."
        case .openGPT, .openClaude: return "Open the configured desktop assistant. Does not copy, type or send. The Follow assistant setting may update the prompt destination on activation."
        case .copyDraft, .copyAndOpen: return "Use the reviewed draft. No paste or send action is issued."
        case .prefillClaude: return "Confirm before passing a draft to Claude's new-chat URL handler; no send action."
        case .collectStack: return "Explicitly start or pause future clipboard-text collection. No collection is started by opening a group."
        case .nativeConfirmation: return "Change the global action-confirmation setting. Turning it off requires acknowledgement."
        case .askAboutPage: return "Build a local reference from the identified page (URL and title, plus the selected passage when that context is on) and compose a draft. Nothing is sent."
        case .editSites: return "Open the site rule editor for your own sites. Rules are validated before they can reach the Touch Bar."
        case .verifyLedger: return "Review the claims in the composed draft and check only what RelayBar can observe locally. Nothing is executed while planning."
        case .auditReply: return "Compare a pasted reply against the saved ledger and show statements the receipt does not support. RelayBar re-checks nothing here."
        case .showClaimLedger: return "Open the saved claim ledger: verdicts, observed evidence, hashes, and what the receipt does not cover."
        case .declareVerifyCommand: return "Declare the local command that settles test, build, or lint claims. RelayBar never derives a command from prose."
        default: return title
        }
    }
}

public enum RelayHierarchyItem: Equatable {
    case page(RelayPage)
    case command(RelayCommand)
    public var id: String {
        switch self { case .page(let p): return "group-" + p.rawValue; case .command(let c): return c.id }
    }
    public var title: String {
        switch self { case .page(let p): return p.title + " ›"; case .command(let c): return c.title }
    }
}

public enum RelayHierarchy {
    public static func items(on page: RelayPage) -> [RelayHierarchyItem] {
        switch page {
        case .home: return [.page(.prompting), .page(.context), .page(.chats), .page(.workspace), .page(.settings)]
        case .prompting: return [.command(.prompt(.nextSlice)), .command(.prompt(.challenge)), .command(.prompt(.handoff)), .page(.promptLibrary), .page(.draft)]
        case .promptLibrary: return [.page(.buildPrompts), .page(.writePrompts)]
        case .buildPrompts: return [.command(.prompt(.explain)), .command(.prompt(.diagnose)), .command(.prompt(.tests)), .command(.prompt(.reviewUI))]
        case .writePrompts: return [.command(.prompt(.tighten)), .command(.prompt(.expand))]
        case .draft: return [.command(.reviewDraft), .command(.copyDraft), .command(.copyAndOpen), .command(.prefillClaude), .command(.saveCheckpoint)]
        case .context: return [.page(.capture), .page(.stack), .page(.verify), .page(.screenshots)]
        case .verify: return [.command(.verifyLedger), .command(.auditReply), .command(.showClaimLedger), .command(.declareVerifyCommand)]
        case .capture: return [.command(.captureSelection), .command(.captureClipboard), .command(.askAboutPage), .command(.editReference), .command(.clearSession)]
        // Pack and recent excerpt buttons come from the existing stack controller.
        case .stack: return [.command(.collectStack), .page(.stackClips), .command(.reviewStack), .page(.stackOptions)]
        case .stackClips: return []
        case .stackOptions: return [.command(.pasteStack), .command(.reviewStack), .command(.clearStack)]
        // Five full-image copy buttons come from the existing screenshot shelf.
        case .screenshots: return [.page(.screenshotOptions)]
        case .screenshotOptions: return [.command(.chooseScreenshotFolder), .command(.watchScreenshots), .command(.autoScreenshots), .command(.addClipboardImage), .command(.clearScreenshots)]
        case .chats: return [.page(.pins), .page(.destinations), .command(.openGPT), .command(.openClaude), .command(.pinsStatus)]
        case .pins: return []
        case .destinations: return [.command(.selectGPT), .command(.selectClaude)]
        case .workspace: return [.page(.projects), .page(.modes), .page(.checkpoints), .page(.appControls)]
        case .projects: return [.page(.projectOptions)]
        case .projectOptions: return [.command(.editProject), .command(.newProject)]
        case .modes: return []
        case .checkpoints: return [.command(.saveCheckpoint), .command(.loadCheckpoint), .command(.revealData)]
        case .appControls: return []
        case .websiteTabs, .sheetsTools: return []
        // The matched site's own buttons come from the site controls controller.
        case .siteTools: return [.command(.askAboutPage), .command(.editSites)]
        // Each toolbox page comes from the toolbox controller.
        case .toolbox: return []
        case .settings: return [.page(.layout), .page(.connections), .page(.assistantSettings), .command(.revealData), .command(.about)]
        case .layout: return [.command(.appAware), .command(.overlay), .command(.disableOverlay)]
        case .connections: return [.command(.enableNative), .command(.nativeDetection), .command(.nativeConfirmation), .command(.nativeReport), .command(.accessibility)]
        case .assistantSettings: return [.command(.followAssistant), .command(.preferDesktop), .command(.chooseGPTApp), .command(.chooseClaudeApp)]
        }
    }
    public enum NativeBack: Equatable { case cancelConfirmation, menuRoots, parent }
    public static func nativeBack(pending: Bool, showingOpenMenu: Bool) -> NativeBack {
        if pending { return .cancelConfirmation }
        return showingOpenMenu ? .menuRoots : .parent
    }
    public static let projectPageSize = 4
    public static func projectPageCount(_ count: Int) -> Int { max(1, (max(0, count) + projectPageSize - 1) / projectPageSize) }
    public static func projectRange(count: Int, page: Int) -> Range<Int> {
        let count = max(0, count), p = min(max(0, page), projectPageCount(count) - 1)
        let first = min(count, p * projectPageSize)
        return first..<min(count, first + projectPageSize)
    }
}

/// Only navigation state. No clipboard, app activation, pin read, storage or timer.
public struct RelayNavigation {
    public private(set) var page: RelayPage = .home
    public private(set) var generation = UUID()
    public private(set) var screenshotReturn: RelayPage?
    public private(set) var projectPage = 0
    public init() {}
    public var backDestination: RelayPage? {
        page == .screenshots ? (screenshotReturn ?? page.parent) : page.parent
    }
    public var isStackPage: Bool { [.stack, .stackClips, .stackOptions].contains(page) }
    public func accepts(_ ticket: UUID) -> Bool { ticket == generation }
    public mutating func open(_ destination: RelayPage) {
        // Every explicit navigation invalidates queued controls, even an identical page.
        // Options opened inside an interrupted viewer retain its return path.
        if destination != .screenshots && destination != .screenshotOptions { screenshotReturn = nil }
        page = destination; generation = UUID()
    }
    public mutating func home() { open(.home) }
    public mutating func back() {
        let destination = backDestination ?? .home
        open(destination)
    }
    public mutating func screenshotArrived(autoOpen: Bool) {
        guard autoOpen else { return }
        if page != .screenshots && page != .screenshotOptions { screenshotReturn = page }
        page = .screenshots; generation = UUID()
    }
    /// A real external-app/document change dismisses a viewer, not ordinary refreshes.
    /// The existing pin controller remains responsible for validating its target.
    public mutating func externalContextChanged(appAware: Bool) {
        guard appAware, page == .screenshots || page == .screenshotOptions else { return }
        open(screenshotReturn ?? .context)
    }
    public mutating func leaveUnavailablePins() {
        if page == .pins { open(.chats) }
        if screenshotReturn == .pins { screenshotReturn = .chats }
    }
    public mutating func setProjectPage(_ proposed: Int, count: Int) {
        projectPage = min(max(0, proposed), RelayHierarchy.projectPageCount(count)-1)
        generation = UUID()
    }
}

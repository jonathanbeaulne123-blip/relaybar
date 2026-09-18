import Foundation

/// Wire data contains routing metadata and button captions, never cell values,
/// script source, arbitrary URLs, clipboard data, or an executable program.
public struct SheetButton: Codable, Equatable {
    public var id: String
    public var label: String
    public var confirmation: Bool
    public init(id: String, label: String, confirmation: Bool = true) {
        self.id = id; self.label = label; self.confirmation = confirmation
    }
}
public struct BrowserContext: Codable, Equatable {
    public var version: Int
    public var kind: String
    public var focused: Bool
    public var tabID: Int
    public var windowID: Int
    public var sheetID: String
    public var pageToken: String
    public var title: String
    public var actions: [SheetButton]
    public init(kind: String = "none", focused: Bool = false, tabID: Int = -1,
                windowID: Int = -1, sheetID: String = "", pageToken: String = "",
                title: String = "", actions: [SheetButton] = []) {
        version = 1; self.kind = kind; self.focused = focused; self.tabID = tabID
        self.windowID = windowID; self.sheetID = sheetID; self.pageToken = pageToken
        self.title = title; self.actions = actions
    }
    public func validate() throws {
        guard version == 1, ["none", "browser", "sheets", "chatgpt", "claude"].contains(kind),
              tabID >= -1, windowID >= -1, tabID < Int(Int32.max), windowID < Int(Int32.max),
              title.count <= 120, !title.unicodeScalars.contains(where: { $0.value < 32 }),
              actions.count <= 120 else { throw RelayError.invalid("Invalid browser context.") }
        if focused { guard tabID >= 0, windowID >= 0, kind != "none" else { throw RelayError.invalid("Missing active tab.") } }
        if kind == "sheets" {
            guard Self.matches(sheetID, "^[A-Za-z0-9_-]{10,160}$"),
                  pageToken.isEmpty || Self.matches(pageToken, "^[A-Za-z0-9_-]{16,100}$") else {
                throw RelayError.invalid("Invalid Sheets identity.")
            }
            guard actions.isEmpty || !pageToken.isEmpty else { throw RelayError.invalid("Unpaired buttons.") }
        } else {
            guard sheetID.isEmpty, pageToken.isEmpty, actions.isEmpty else { throw RelayError.invalid("Script buttons outside Sheets.") }
        }
        var seen = Set<String>()
        for action in actions {
            guard Self.matches(action.id, "^[A-Za-z0-9_$:.-]{1,180}$"),
                  !action.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  action.label.count <= 100,
                  !action.label.unicodeScalars.contains(where: { $0.value < 32 }),
                  seen.insert(action.id).inserted else { throw RelayError.invalid("Invalid or repeated button.") }
        }
    }
    public static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
public struct BrowserReceipt: Codable, Equatable {
    public var sessionID: String
    public var browserBundle: String
    public var receivedAt: Double
    public var context: BrowserContext
    public var status: String
    public init(sessionID: String, browserBundle: String, receivedAt: Double, context: BrowserContext, status: String = "") {
        self.sessionID = sessionID; self.browserBundle = browserBundle
        self.receivedAt = receivedAt; self.context = context; self.status = String(status.prefix(240))
    }
    public var identity: String {
        "\(browserBundle)|\(sessionID)|\(context.kind)|\(context.tabID)|\(context.windowID)|\(context.sheetID)|\(context.pageToken)"
    }
    public func validate() throws {
        guard UUID(uuidString: sessionID) != nil,
              AppContextPolicy.browserBundles.contains(browserBundle), receivedAt.isFinite,
              status.count <= 240 else { throw RelayError.invalid("Invalid browser receipt.") }
        try context.validate()
    }
}
public struct BrowserCommand: Codable, Equatable {
    public var version = 1
    public var requestID: String
    public var sessionID: String
    public var browserBundle: String
    public var tabID: Int
    public var windowID: Int
    public var sheetID: String
    public var pageToken: String
    public var actionID: String
    public var expiresAt: Double
    public init(receipt: BrowserReceipt, actionID: String, now: Double) {
        requestID = UUID().uuidString; sessionID = receipt.sessionID
        browserBundle = receipt.browserBundle; tabID = receipt.context.tabID
        windowID = receipt.context.windowID; sheetID = receipt.context.sheetID
        pageToken = receipt.context.pageToken; self.actionID = actionID; expiresAt = now + 3
    }
}
public enum AppContextPolicy {
    public static let browserBundles = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "org.chromium.Chromium"]
    public static let navigationActions = ["nav.back", "nav.forward", "nav.reload"]
    public static let freshness: Double = 2.5
    public static let pageSize = 4
    /// Multiple focused profiles fail closed; never choose a background workbook.
    public static func select(_ receipts: [BrowserReceipt], for bundle: String, now: Double) -> BrowserReceipt? {
        let matching = receipts.filter {
            (try? $0.validate()) != nil && $0.browserBundle == bundle && $0.context.focused &&
            now >= $0.receivedAt && now - $0.receivedAt <= freshness
        }
        return matching.count == 1 ? matching.first : nil
    }
    public static func permits(_ command: BrowserCommand, receipt: BrowserReceipt,
                               frontmostBundle: String, now: Double) -> Bool {
        guard (try? receipt.validate()) != nil, command.version == 1,
              UUID(uuidString: command.requestID) != nil,
              frontmostBundle == receipt.browserBundle, receipt.context.focused,
              now >= receipt.receivedAt, now - receipt.receivedAt <= freshness,
              command.expiresAt.isFinite, now < command.expiresAt,
              command.expiresAt - now <= 3.1,
              command.sessionID == receipt.sessionID, command.browserBundle == receipt.browserBundle,
              command.tabID == receipt.context.tabID, command.windowID == receipt.context.windowID,
              command.sheetID == receipt.context.sheetID, command.pageToken == receipt.context.pageToken else { return false }
        if navigationActions.contains(command.actionID) { return true }
        return receipt.context.kind == "sheets" && !receipt.context.pageToken.isEmpty &&
            receipt.context.actions.contains(where: { $0.id == command.actionID })
    }
    public static func buttons(_ actions: [SheetButton], page: Int) -> [SheetButton] {
        guard page >= 0, page < pageCount(actions.count) else { return [] }
        return Array(actions.dropFirst(page * pageSize).prefix(pageSize))
    }
    public static func pageCount(_ count: Int) -> Int { max(1, (max(0, count) + pageSize - 1) / pageSize) }
}

/// A temporary browser-link outage must disable actions, not dismiss the newest
/// screenshot. Only a real app switch or confirmed different tab resets a page.
public struct ContextLayoutState {
    private var appBundle = ""
    private var confirmedBrowserIdentity: String?
    public init() {}
    public mutating func observe(appBundle bundle: String, browserIdentity: String?) -> Bool {
        let appChanged = bundle != appBundle
        if appChanged { appBundle = bundle; confirmedBrowserIdentity = nil }
        let tabChanged = browserIdentity != nil && confirmedBrowserIdentity != nil && browserIdentity != confirmedBrowserIdentity
        if let identity = browserIdentity { confirmedBrowserIdentity = identity }
        return appChanged || tabChanged
    }
}

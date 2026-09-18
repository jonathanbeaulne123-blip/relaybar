import Foundation

/// Metadata-only snapshot. The macOS reader never asks for a message body,
/// composer value, selected text, clipboard, cookies, or account credentials.
public struct PinNode: Equatable {
    public var token: String
    public var role: String
    public var subrole: String
    public var label: String
    public var identifier: String
    public var url: String?
    public var enabled: Bool
    public var hidden: Bool
    public var pressable: Bool
    public var selected: Bool
    public var children: [PinNode]
    public init(token: String, role: String = "AXGroup", subrole: String = "", label: String = "",
                identifier: String = "", url: String? = nil, enabled: Bool = true,
                hidden: Bool = false, pressable: Bool = false, selected: Bool = false,
                children: [PinNode] = []) {
        self.token = token; self.role = role; self.subrole = subrole; self.label = label
        self.identifier = identifier; self.url = url; self.enabled = enabled; self.hidden = hidden
        self.pressable = pressable; self.selected = selected; self.children = children
    }
}
public enum PinProvider: String, CaseIterable, Equatable {
    case chatgpt, claude
    public var title: String { self == .chatgpt ? "ChatGPT" : "Claude" }
    public var shortTitle: String { self == .chatgpt ? "GPT" : "Claude" }
    public var other: PinProvider { self == .chatgpt ? .claude : .chatgpt }
    public static func site(_ raw: String) -> PinProvider? {
        guard let c = URLComponents(string: raw), c.scheme?.lowercased() == "https",
              c.user == nil, c.password == nil, c.port == nil || c.port == 443 else { return nil }
        switch c.host?.lowercased() {
        case "chatgpt.com", "chat.openai.com": return .chatgpt
        case "claude.ai": return .claude
        default: return nil
        }
    }
    /// Only private conversation links. Shared links, project pages, scripts,
    /// hostile suffix domains and credentials in URLs are not chat targets.
    public func conversationURL(_ raw: String) -> String? {
        guard Self.site(raw) == self, var c = URLComponents(string: raw),
              !c.percentEncodedPath.contains("%"), !c.path.contains("//") else { return nil }
        let path = c.path.hasSuffix("/") ? String(c.path.dropLast()) : c.path
        let pattern = self == .chatgpt
            ? "^/(?:g/[A-Za-z0-9_-]+/)?c/[A-Za-z0-9_-]{8,160}$"
            : "^/chat/[A-Za-z0-9_-]{8,160}$"
        guard path.range(of: pattern, options: .regularExpression) != nil else { return nil }
        c.scheme = "https"; c.host = c.host?.lowercased(); c.port = nil
        c.path = path; c.query = nil; c.fragment = nil
        return c.string
    }
}
public struct PinnedChat: Equatable {
    public var token: String
    public var identity: String
    public var title: String
    public var url: String?
    public var selected: Bool
    public var enabled: Bool
    public var evidence: String
}
public struct PinInventory: Equatable {
    public var chats: [PinnedChat]
    public var recognizedSection: Bool
    public var limited: Bool
    public var ambiguous: Int
}
public enum PinnedChatPolicy {
    public static let pageSize = 3
    public static let maximumChats = 60
    public static let maximumNodes = 700
    public static let maximumDepth = 24
    public static let freshness: Double = 4
    public static let pinLabels: Set<String> = ["pinned", "pinned chats", "pinned conversations", "starred", "starred chats", "starred conversations", "favorites", "favourites", "favorite chats", "favourite chats"]
    public static let sidebarLabels: Set<String> = ["sidebar", "chat history", "chats sidebar", "conversations", "navigation", "main navigation"]
    public static let boundaryLabels: Set<String> = ["recents", "recent", "recent chats", "chats", "all chats", "your chats", "conversations", "projects", "your projects", "today", "yesterday", "previous 7 days", "previous 30 days"]
    public static let rejectedControls: Set<String> = ["pin", "pin chat", "unpin", "unpin chat", "star", "star chat", "unstar", "unstar chat", "remove from favorites", "remove from starred", "add to favorites", "delete", "delete chat", "archive", "archive chat", "rename", "rename chat", "share", "share chat", "more", "more options", "open menu", "chat options", "new chat", "search chats", "show more", "see all"]
    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    public static func cleanTitle(_ text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 240,
              !s.unicodeScalars.contains(where: { $0.value < 32 || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value) }) else { return nil }
        return s
    }
    public static func isSidebar(role: String, subrole: String, label: String, identifier: String) -> Bool {
        let structural = ["AXGroup", "AXOutline", "AXList", "AXScrollArea", "AXSplitGroup"].contains(role)
        guard structural else { return false }
        return ["AXLandmarkNavigation", "AXNavigation", "AXSidebar"].contains(subrole) ||
            sidebarLabels.contains(normalized(label)) ||
            ["sidebar", "history-sidebar", "chat-history", "navigation-sidebar", "app-sidebar"].contains(normalized(identifier))
    }
    public static func pageCount(_ count: Int) -> Int { max(1, (max(0, count) + pageSize - 1) / pageSize) }
    public static func page(_ items: [PinnedChat], index: Int) -> [PinnedChat] {
        guard index >= 0, index < pageCount(items.count) else { return [] }
        return Array(items.dropFirst(index * pageSize).prefix(pageSize))
    }
    private static func isSection(_ n: PinNode) -> Bool {
        pinLabels.contains(normalized(n.label)) &&
            ["AXGroup", "AXHeading", "AXStaticText", "AXDisclosureTriangle", "AXButton", "AXList"].contains(n.role) && n.url == nil
    }
    private static func isBoundary(_ n: PinNode) -> Bool {
        n.role == "AXHeading" || (n.url == nil && boundaryLabels.contains(normalized(n.label)) &&
            ["AXStaticText", "AXButton", "AXDisclosureTriangle", "AXGroup"].contains(n.role))
    }
    private static func marker(_ n: PinNode, depth: Int = 0) -> Bool {
        guard depth < 4, !n.hidden, !n.pressable else { return false }
        if ["AXImage", "AXStaticText"].contains(n.role),
           ["pinned", "starred", "favorite", "favourite"].contains(normalized(n.label)) { return true }
        return n.children.contains { marker($0, depth: depth + 1) }
    }
    /// The input MUST be an identified sidebar, not an application or document.
    /// Pin status is positive evidence: section heading/container or an explicit
    /// non-action marker in the same single-conversation row. Recency is not pinning.
    public static func inventory(sidebar: PinNode, provider: PinProvider, native: Bool) -> PinInventory {
        guard isSidebar(role: sidebar.role, subrole: sidebar.subrole, label: sidebar.label, identifier: sidebar.identifier), !sidebar.hidden else {
            return PinInventory(chats: [], recognizedSection: false, limited: false, ambiguous: 0)
        }
        var result = [PinnedChat](), visited = Set<String>(), count = 0, recognized = false, limited = false
        func walk(_ node: PinNode, pinned: Bool, inheritedEnabled: Bool, depth: Int, rowMarker: Bool = false, chatOnly: Bool = false) {
            guard !node.hidden else { return }
            guard count < maximumNodes, depth <= maximumDepth else { limited = true; return }
            guard visited.insert(node.token).inserted else { limited = true; return }
            count += 1
            guard !["AXTextArea", "AXTextField", "AXSecureTextField", "AXMenu", "AXMenuItem", "AXSheet", "AXDialog"].contains(node.role) else { return }
            let section = isSection(node)
            if section { recognized = true }
            let sectionChatOnly = chatOnly || (section && ["pinned chats", "pinned conversations", "starred chats", "starred conversations"].contains(normalized(node.label)))
            let enabled = inheritedEnabled && node.enabled
            let ownMarker = ["AXLink", "AXButton", "AXRow"].contains(node.role) && node.children.contains { marker($0) }
            if ownMarker { recognized = true }
            let localPin = pinned || section || rowMarker || ownMarker
            let label = cleanTitle(node.label)
            let url = node.url.flatMap { provider.conversationURL($0) }
            let acceptableRole = ["AXLink", "AXButton", "AXRow"].contains(node.role)
            let nativeTitleTarget = native && node.url == nil && ["AXButton", "AXRow"].contains(node.role) &&
                (sectionChatOnly || node.identifier.lowercased().contains("chat") || node.identifier.lowercased().contains("conversation")) &&
                !node.identifier.lowercased().contains("project")
            if localPin, !section, acceptableRole, node.pressable, let title = label,
               !rejectedControls.contains(normalized(title)), (url != nil || nativeTitleTarget) {
                let identity = url ?? "native:\(node.identifier.isEmpty ? title : node.identifier)"
                result.append(PinnedChat(token: node.token, identity: identity, title: title, url: url,
                    selected: node.selected, enabled: enabled, evidence: (rowMarker || ownMarker) ? "row-marker" : "pinned-section"))
                return // Never turn its overflow, unpin or delete buttons into navigation.
            }
            // A marker applies only to its own row, not siblings in a whole list.
            let row = ["AXRow", "AXGroup"].contains(node.role) && node.children.filter {
                ["AXLink", "AXButton", "AXRow"].contains($0.role) &&
                    !rejectedControls.contains(normalized($0.label)) && !isSection($0)
            }.count == 1 && node.children.contains { marker($0) }
            if row { recognized = true }
            var sectionActive = pinned || section
            var siblingChatOnly = sectionChatOnly
            for child in node.children {
                if child.hidden { continue }
                if isSection(child) {
                    recognized = true
                    // A named container scopes its own children. Only standalone
                    // headings/disclosures start a following sibling section.
                    let heading = child.children.isEmpty || ["AXHeading", "AXStaticText"].contains(child.role) ||
                        (["AXButton", "AXDisclosureTriangle"].contains(child.role) && child.children.allSatisfy { ["AXStaticText", "AXImage"].contains($0.role) })
                    if heading {
                        sectionActive = true
                        siblingChatOnly = ["pinned chats", "pinned conversations", "starred chats", "starred conversations"].contains(normalized(child.label))
                    }
                }
                else if isBoundary(child) { sectionActive = false; siblingChatOnly = false }
                walk(child, pinned: sectionActive, inheritedEnabled: enabled, depth: depth + 1, rowMarker: row, chatOnly: siblingChatOnly)
            }
        }
        walk(sidebar, pinned: false, inheritedEnabled: true, depth: 0)
        // Multiple same-identity targets fail closed. Never choose the first account,
        // project or duplicated native title as a shortcut to "making it work".
        let groups = Dictionary(grouping: result, by: { $0.identity })
        let ambiguous = result.filter { (groups[$0.identity]?.count ?? 0) > 1 }.count
        result = result.map { chat in
            var chat = chat
            if (groups[chat.identity]?.count ?? 0) > 1 { chat.enabled = false }
            return chat
        }
        if result.count > maximumChats { limited = true; result = Array(result.prefix(maximumChats)) }
        return PinInventory(chats: result, recognizedSection: recognized, limited: limited, ambiguous: ambiguous)
    }
}

/// Shared dispatch/replay gate; target elements also undergo native CFEqual and
/// live AXPress checks. An old button cannot silently become a new chat.
public struct PinSession: Equatable {
    public var pid: Int32
    public var bundle: String
    public var window: String
    public var document: String
    public var provider: PinProvider
    public init(pid: Int32, bundle: String, window: String, document: String, provider: PinProvider) {
        self.pid = pid; self.bundle = bundle; self.window = window; self.document = document; self.provider = provider
    }
}
public struct PinTicket: Equatable {
    public var nonce: UUID
    public var generation: UUID
    public var session: PinSession
    public var chat: PinnedChat
    public var issuedAt: Double
}
public struct PinNavigationGate {
    public private(set) var generation = UUID()
    public private(set) var session: PinSession?
    public private(set) var chats: [PinnedChat] = []
    public private(set) var sampledAt: Double = 0
    private var used = Set<UUID>()
    public init() {}
    public mutating func clear() { generation = UUID(); session = nil; chats = []; sampledAt = 0; used = [] }
    public mutating func update(session: PinSession, chats: [PinnedChat], now: Double) {
        if self.session != session || self.chats != chats { generation = UUID(); used = [] }
        self.session = session; self.chats = chats; sampledAt = now
    }
    public func ticket(token: String, now: Double) -> PinTicket? {
        guard now.isFinite, sampledAt.isFinite, now >= sampledAt, now - sampledAt <= PinnedChatPolicy.freshness,
              let session = session, let chat = chats.first(where: { $0.token == token }), chat.enabled else { return nil }
        return PinTicket(nonce: UUID(), generation: generation, session: session, chat: chat, issuedAt: now)
    }
    public mutating func consume(_ ticket: PinTicket, liveSession: PinSession, liveChats: [PinnedChat], now: Double) -> Bool {
        guard now.isFinite, ticket.issuedAt.isFinite, now >= ticket.issuedAt, now - ticket.issuedAt <= 2,
              now >= sampledAt, now - sampledAt <= PinnedChatPolicy.freshness,
              ticket.generation == generation, ticket.session == session, liveSession == session,
              liveChats == chats, chats.contains(ticket.chat), ticket.chat.enabled,
              used.insert(ticket.nonce).inserted else { return false }
        return true
    }
}

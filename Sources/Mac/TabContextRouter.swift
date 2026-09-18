import Cocoa

public enum TabContextKind: String, Equatable, CaseIterable {
    case youtube
    case sheets
    case docs
    case github
    case general
}

public struct TabContextAction: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let help: String
    public let icon: String?
    public let width: CGFloat?
    
    public init(id: String, title: String, help: String, icon: String? = nil, width: CGFloat? = nil) {
        self.id = id
        self.title = title
        self.help = help
        self.icon = icon
        self.width = width
    }
}

public enum TabContextRouter {
    public static func detectContext(url: String, title: String) -> TabContextKind {
        let lowerURL = url.lowercased()
        
        if lowerURL.contains("youtube.com/watch") || lowerURL.contains("youtu.be/") {
            return .youtube
        }
        if lowerURL.contains("docs.google.com/spreadsheets") || lowerURL.contains("script.google.com") {
            return .sheets
        }
        if lowerURL.contains("docs.google.com/document") {
            return .docs
        }
        if lowerURL.contains("github.com") {
            return .github
        }
        return .general
    }
    
    public static func actions(for kind: TabContextKind) -> [TabContextAction] {
        switch kind {
        case .youtube:
            return [
                TabContextAction(id: "yt.rewind", title: "↶10", help: "Rewind 10s", width: 46),
                TabContextAction(id: "yt.timeline", title: "Chapters ▸", help: "Video chapters and semantic timeline", width: 120),
                TabContextAction(id: "yt.moment", title: "★ MOMENT", help: "Capture timestamped moment", width: 82),
                TabContextAction(id: "yt.transcribe", title: "TRANSCRIBE", help: "Synchronized transcript", width: 96),
                TabContextAction(id: "yt.ask", title: "ASK", help: "Ask AI about this video", width: 46)
            ]
        case .sheets:
            return [
                TabContextAction(id: "sheets.menu", title: "📊 Sheets ›", help: "Spreadsheet tools & formulas", width: 85),
                TabContextAction(id: "sheets.currency", title: "$ Currency", help: "Format as currency", width: 65),
                TabContextAction(id: "sheets.filter", title: "⚡ Filter", help: "Toggle filter", width: 65),
                TabContextAction(id: "sheets.freeze", title: "❄ Freeze", help: "Freeze top row", width: 65)
            ]
        case .github:
            return [
                TabContextAction(id: "github.prs", title: "🐙 PRs", help: "Open Pull Requests", width: 65),
                TabContextAction(id: "github.issues", title: "📋 Issues", help: "Open Issues", width: 65),
                TabContextAction(id: "github.actions", title: "⚙ Actions", help: "Open GitHub Actions", width: 65)
            ]
        case .docs:
            return [
                TabContextAction(id: "docs.menu", title: "📝 Docs", help: "Google Docs tools", width: 65),
                TabContextAction(id: "docs.bold", title: "B Bold", help: "Toggle bold formatting", width: 55),
                TabContextAction(id: "docs.note", title: "💬 Note", help: "Add comment", width: 55)
            ]
        case .general:
            return []
        }
    }
    
    public static func execute(actionID: String, activeURL: String) {
        switch actionID {
        case "github.prs":
            openURL("https://github.com/pulls")
        case "github.issues":
            openURL("https://github.com/issues")
        case "github.actions":
            if let repoURL = extractRepoURL(from: activeURL) {
                openURL("\(repoURL)/actions")
            } else {
                openURL("https://github.com/features/actions")
            }
            
        case "sheets.currency":
            // Cmd+Shift+4 for currency format in sheets
            simulateKey(keyCode: 21, flags: [.maskCommand, .maskShift])
        case "sheets.filter":
            // Simulating filter action
            simulateKey(keyCode: 3, flags: [.maskCommand, .maskShift])
        case "sheets.freeze":
            // No direct shortcut, log for future implementation
            print("Freeze top row executed.")
            
        case "docs.bold":
            // Cmd+B
            simulateKey(keyCode: 11, flags: [.maskCommand])
        case "docs.note":
            // Cmd+Option+M for comment
            simulateKey(keyCode: 46, flags: [.maskCommand, .maskAlternate])
            
        case "general.clip":
            // Cmd+C
            simulateKey(keyCode: 8, flags: [.maskCommand])
        case "general.shot":
            // Cmd+Shift+4
            simulateKey(keyCode: 21, flags: [.maskCommand, .maskShift])
            
        default:
            break
        }
    }
    
    private static func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private static func extractRepoURL(from urlString: String) -> String? {
        guard urlString.contains("github.com") else { return nil }
        let components = urlString.components(separatedBy: "/")
        if components.count >= 5 {
            let repoBase = components[0...4].joined(separator: "/")
            return repoBase
        }
        return nil
    }
    
    private static func simulateKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        if let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        if let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}

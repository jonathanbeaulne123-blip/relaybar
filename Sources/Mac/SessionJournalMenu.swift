import Cocoa
#if canImport(RelayCore)
import RelayCore
#endif

@MainActor
public enum SessionJournalMenu {
    
    public static func menuItems(
        journal: SessionJournal,
        projectName: String,
        gitSnapshot: GitSnapshot,
        target: Any,
        showAction: Selector,
        exportMarkdownAction: Selector,
        exportHandoffAction: Selector,
        toggleRecordingAction: Selector
    ) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        
        let header = NSMenuItem(title: "📓 Session Journal", action: nil, keyEquivalent: "")
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 13)]
        header.attributedTitle = NSAttributedString(string: "📓 Session Journal", attributes: attrs)
        header.isEnabled = false
        items.append(header)
        
        if journal.isRecording, let start = journal.sessionStartedAt {
            let duration = Date().timeIntervalSince(start)
            let h = Int(duration) / 3600
            let m = (Int(duration) % 3600) / 60
            let s = Int(duration) % 60
            let timeStr = String(format: "%02d:%02d:%02d", h, m, s)
            
            let recordingItem = NSMenuItem(title: "  ⏱ Recording: \(timeStr)", action: nil, keyEquivalent: "")
            recordingItem.isEnabled = false
            items.append(recordingItem)
        } else {
            let notRecordingItem = NSMenuItem(title: "  ⏸ Not Recording", action: nil, keyEquivalent: "")
            notRecordingItem.isEnabled = false
            items.append(notRecordingItem)
        }
        
        let entriesItem = NSMenuItem(title: "  📊 \(journal.entries.count) entries", action: nil, keyEquivalent: "")
        entriesItem.isEnabled = false
        items.append(entriesItem)
        
        items.append(.separator())
        
        let toggleItem = NSMenuItem(
            title: journal.isRecording ? "  ⏹ Stop Recording" : "  ▶ Start Recording",
            action: toggleRecordingAction,
            keyEquivalent: ""
        )
        toggleItem.target = target as AnyObject
        items.append(toggleItem)
        
        let showItem = NSMenuItem(title: "  📋 Show Timeline", action: showAction, keyEquivalent: "")
        showItem.target = target as AnyObject
        items.append(showItem)
        
        let exportMdItem = NSMenuItem(title: "  📄 Copy as Markdown", action: exportMarkdownAction, keyEquivalent: "")
        exportMdItem.target = target as AnyObject
        items.append(exportMdItem)
        
        let handoffItem = NSMenuItem(title: "  🤝 Copy Handoff Packet", action: exportHandoffAction, keyEquivalent: "")
        handoffItem.target = target as AnyObject
        items.append(handoffItem)
        
        return items
    }
}

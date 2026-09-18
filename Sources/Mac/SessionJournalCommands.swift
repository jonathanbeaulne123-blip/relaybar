#if canImport(RelayCore)
import RelayCore
#endif

public enum SessionJournalCommands {
    
    public static func commandEntries() -> [CommandEntry] {
        return [
            CommandEntry(
                id: "journal-show",
                kind: .relayCommand,
                title: "Show Session Journal",
                subtitle: "View session timeline and events",
                icon: "📓",
                action: "journal.show"
            ),
            CommandEntry(
                id: "journal-export-markdown",
                kind: .relayCommand,
                title: "Export Journal as Markdown",
                subtitle: "Copy journal to clipboard as Markdown",
                icon: "📄",
                action: "journal.exportMarkdown"
            ),
            CommandEntry(
                id: "journal-export-handoff",
                kind: .relayCommand,
                title: "Export Journal Handoff Packet",
                subtitle: "Copy session handoff packet to clipboard",
                icon: "🤝",
                action: "journal.exportHandoff"
            ),
            CommandEntry(
                id: "journal-toggle-recording",
                kind: .relayCommand,
                title: "Toggle Journal Recording",
                subtitle: "Start or stop session recording",
                icon: "🔴",
                action: "journal.toggleRecording"
            ),
            CommandEntry(
                id: "journal-add-note",
                kind: .relayCommand,
                title: "Add Journal Note",
                subtitle: "Type a note in the session journal",
                icon: "📝",
                action: "journal.addNote"
            ),
            CommandEntry(
                id: "journal-clear",
                kind: .relayCommand,
                title: "Clear Session Journal",
                subtitle: "Clear all events in the timeline",
                icon: "🧹",
                action: "journal.clear"
            )
        ]
    }
}

import Foundation

public enum CommandEntryKind: String, Codable {
    case quickAction
    case workflow
    case gitCommand
    case relayCommand
    case plugin
    case setting
    case verify
}

public struct CommandEntry: Identifiable, Equatable {
    public let id: String
    public let kind: CommandEntryKind
    public let title: String
    public let subtitle: String
    public let icon: String
    public var usageCount: Int
    public let action: String  // serializable action identifier
    
    public init(id: String, kind: CommandEntryKind, title: String, subtitle: String = "", icon: String = "", usageCount: Int = 0, action: String = "") {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.usageCount = usageCount
        self.action = action
    }
}

public final class CommandIndex {
    public private(set) var entries: [CommandEntry] = []
    private var usageCounts: [String: Int] = [:]
    
    public init() {}
    
    /// Declared verify commands are searchable like any other command, but they
    /// are only ever run through the claim ledger's planning rules.
    public func registerVerifyCommands(_ commands: [VerifyCommand]) {
        unregister(kind: .verify)
        register(commands.map { command in
            CommandEntry(id: "verify-\(command.id.uuidString)", kind: .verify, title: command.name,
                         subtitle: "\(command.kind.title) · \(command.command)", icon: "🔎",
                         action: "verify-\(command.id.uuidString)")
        })
    }

    // Register entries from various sources
    public func register(_ newEntries: [CommandEntry]) {
        entries.removeAll { entry in newEntries.contains(where: { $0.id == entry.id }) }
        entries.append(contentsOf: newEntries)
    }
    
    // Unregister entries by kind
    public func unregister(kind: CommandEntryKind) {
        entries.removeAll { $0.kind == kind }
    }
    
    // Fuzzy search across all entries
    // Returns entries sorted by score (higher = better match), then by usage count
    public func search(_ query: String) -> [CommandEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            // Return most-used entries when query is empty
            return entries.sorted { ($0.usageCount, $0.title) > ($1.usageCount, $1.title) }.prefix(12).map { $0 }
        }
        
        // Score each entry using fuzzy matching
        return entries.compactMap { entry -> (entry: CommandEntry, score: Int)? in
            let score = fuzzyScore(query: trimmed, target: entry.title.lowercased())
            let subtitleScore = fuzzyScore(query: trimmed, target: entry.subtitle.lowercased())
            let bestScore = max(score, subtitleScore)
            guard bestScore > 0 else { return nil }
            return (entry, bestScore + entry.usageCount)
        }
        .sorted { $0.score > $1.score }
        .prefix(20)
        .map { $0.entry }
    }
    
    // Record that a command was used (for smart ranking)
    public func recordUsage(_ id: String) {
        usageCounts[id, default: 0] += 1
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].usageCount = usageCounts[id] ?? 0
        }
    }
    
    // Simple fuzzy matching: all characters must appear in order
    // Score bonus for consecutive matches, word-boundary matches, and prefix matches
    private func fuzzyScore(query: String, target: String) -> Int {
        guard !query.isEmpty, !target.isEmpty else { return 0 }
        
        let qChars = Array(query)
        let tChars = Array(target)
        
        var qIdx = 0
        var tIdx = 0
        var score = 0
        var consecutive = false
        
        while qIdx < qChars.count && tIdx < tChars.count {
            if qChars[qIdx] == tChars[tIdx] {
                // Match found
                if tIdx == 0 {
                    score += 10 // exact match at start
                } else {
                    let prevChar = tChars[tIdx - 1]
                    if prevChar == " " || prevChar == "-" || prevChar == "_" {
                        score += 3 // word boundary
                    } else {
                        score += 1 // regular match
                    }
                }
                
                if consecutive {
                    score += 5 // consecutive
                }
                
                consecutive = true
                qIdx += 1
            } else {
                consecutive = false
            }
            tIdx += 1
        }
        
        if qIdx == qChars.count {
            return score
        } else {
            return 0
        }
    }
    
    // Build default entries from RelayBar's built-in commands
    public func registerBuiltinCommands() {
        // Git shortcuts
        var builtins: [CommandEntry] = [
            .init(id: "git-status", kind: .gitCommand, title: "Git Status", subtitle: "Show working tree status", icon: "📊"),
            .init(id: "git-pull", kind: .gitCommand, title: "Git Pull", subtitle: "Fetch and merge upstream", icon: "⬇"),
            .init(id: "git-push", kind: .gitCommand, title: "Git Push", subtitle: "Push commits to remote", icon: "⬆"),
            .init(id: "git-log", kind: .gitCommand, title: "Git Log", subtitle: "Show recent commits", icon: "📜"),
            .init(id: "git-diff", kind: .gitCommand, title: "Git Diff", subtitle: "Show unstaged changes", icon: "📝"),
            .init(id: "git-stash", kind: .gitCommand, title: "Git Stash", subtitle: "Stash working changes", icon: "📦"),
            .init(id: "git-stash-pop", kind: .gitCommand, title: "Git Stash Pop", subtitle: "Restore stashed changes", icon: "📤"),
        ]
        
        // Settings
        builtins.append(contentsOf: [
            .init(id: "setting-app-aware", kind: .setting, title: "Toggle App-Aware", subtitle: "Settings", icon: "⚙"),
            .init(id: "setting-shell", kind: .setting, title: "Toggle Persistent Shell", subtitle: "Settings", icon: "⚙"),
            .init(id: "setting-native", kind: .setting, title: "Toggle Native Controls", subtitle: "Settings", icon: "⚙"),
        ])
        
        register(builtins)
    }
}

import Foundation

public enum SessionJournalPolicy {
    public static let maxEntries = 500
    public static let maxNoteLength = 1000
    public static let deduplicationWindow: TimeInterval = 2.0
    public static let maxExportEntries = 200
    
    public static func icon(for kind: JournalEntryKind) -> String {
        switch kind {
        case .projectSwitch: return "📁"
        case .branchChange: return "🌿"
        case .commandRun(_, _, let exitCode, _):
            return exitCode == 0 ? "⚡" : "⚠️"
        case .contextClipAdded: return "📎"
        case .screenshotTaken: return "📸"
        case .workflowCompleted(_, let stepCount, let successCount):
            return stepCount == successCount ? "✅" : "⚠️"
        case .note: return "📝"
        case .sessionStart: return "▶️"
        case .sessionEnd: return "⏹️"
        case .claimLedgerCreated(_, _, _, _): return "🔎"
        case .claimVerified(_, let verdict, _):
            switch verdict {
            case ClaimVerdict.verified.rawValue: return "✅"
            case ClaimVerdict.refuted.rawValue: return "❌"
            case ClaimVerdict.notCheckable.rawValue: return "⏭"
            default: return "⚠️"
            }
        case .rehearsalRan(_, let exitCode, _): return exitCode == 0 ? "🧪" : "⚠️"
        case .claimRepeated: return "❗"
        }
    }
}

public enum JournalEntryKind: Codable, Equatable {
    case projectSwitch(name: String, type: String)
    case branchChange(from: String, to: String)
    case commandRun(name: String, command: String, exitCode: Int32, durationSeconds: Double)
    case contextClipAdded(preview: String)
    case screenshotTaken(index: Int)
    case workflowCompleted(name: String, stepCount: Int, successCount: Int)
    case note(text: String)
    case sessionStart
    case sessionEnd
    case claimLedgerCreated(claimCount: Int, verified: Int, refuted: Int, unverified: Int)
    case claimVerified(text: String, verdict: String, method: String)
    case rehearsalRan(command: String, exitCode: Int32, worktree: String)
    case claimRepeated(text: String)
}

public struct JournalEntry: Codable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let kind: JournalEntryKind
    public let appContext: String
    
    public init(id: UUID = UUID(), timestamp: Date = Date(), kind: JournalEntryKind, appContext: String) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.appContext = appContext
    }
    
    public var summary: String {
        switch kind {
        case .projectSwitch(let name, let type):
            return "Switched to project '\(name)' (\(type))"
        case .branchChange(let from, let to):
            return "Changed branch from '\(from)' to '\(to)'"
        case .commandRun(let name, let command, let exitCode, let durationSeconds):
            let status = exitCode == 0 ? "succeeded" : "failed (code \(exitCode))"
            let duration = String(format: "%.1fs", durationSeconds)
            return "Ran '\(name)' (\(command)) — \(status) in \(duration)"
        case .contextClipAdded(let preview):
            return "Added context clip: \"\(preview)\""
        case .screenshotTaken(let index):
            return "Captured screenshot #\(index)"
        case .workflowCompleted(let name, let stepCount, let successCount):
            return "Completed workflow '\(name)' (\(successCount)/\(stepCount) steps successful)"
        case .note(let text):
            return text
        case .sessionStart:
            return "Session started"
        case .sessionEnd:
            return "Session ended"
        case .claimLedgerCreated(let claimCount, let verified, let refuted, let unverified):
            return "Reviewed \(claimCount) claim(s): \(verified) verified, \(refuted) refuted, \(unverified) unverified"
        case .claimVerified(let text, let verdict, let method):
            return "\(verdict) · \"\(text)\" — \(method)"
        case .rehearsalRan(let command, let exitCode, let worktree):
            return "Rehearsed '\(command)' in a throwaway worktree (exit \(exitCode)): \(worktree)"
        case .claimRepeated(let text):
            return "Reply restated something the receipt did not support: \"\(text)\""
        }
    }
}

public final class SessionJournal {
    public private(set) var entries: [JournalEntry] = []
    public private(set) var isRecording: Bool = false
    public private(set) var sessionStartedAt: Date?
    
    public var onChange: (() -> Void)?
    
    public init() {}
    
    public func startSession() {
        guard !isRecording else { return }
        isRecording = true
        sessionStartedAt = Date()
        record(.sessionStart, app: "System")
    }
    
    public func endSession() {
        guard isRecording else { return }
        record(.sessionEnd, app: "System")
        isRecording = false
        sessionStartedAt = nil
    }
    
    public func record(_ kind: JournalEntryKind, app: String) {
        guard isRecording else { return }
        
        let now = Date()
        
        if let last = entries.last, last.kind == kind {
            if now.timeIntervalSince(last.timestamp) < SessionJournalPolicy.deduplicationWindow {
                return
            }
        }
        
        let entry = JournalEntry(timestamp: now, kind: kind, appContext: app)
        entries.append(entry)
        
        if entries.count > SessionJournalPolicy.maxEntries {
            entries.removeFirst(entries.count - SessionJournalPolicy.maxEntries)
        }
        
        onChange?()
    }
    
    public func addNote(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RelayError.invalid("Note cannot be empty.")
        }
        guard trimmed.count <= SessionJournalPolicy.maxNoteLength else {
            throw RelayError.invalid("Note must be \(SessionJournalPolicy.maxNoteLength) characters or fewer.")
        }
        record(.note(text: trimmed), app: "User")
    }
    
    public func clear() {
        entries.removeAll()
        isRecording = false
        sessionStartedAt = nil
        onChange?()
    }
}

public enum SessionJournalExporter {
    
    public static func exportMarkdown(journal: SessionJournal, projectName: String) -> String {
        var markdown = "# Session Journal: \(projectName)\n\n"
        
        if let start = journal.sessionStartedAt {
            let duration = Date().timeIntervalSince(start)
            let mins = max(1, Int(duration) / 60)
            markdown += "**Session Duration:** \(mins) min\n\n"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        var currentHour = ""
        let exportEntries = Array(journal.entries.suffix(SessionJournalPolicy.maxExportEntries))
        
        for entry in exportEntries {
            let hourFormatter = DateFormatter()
            hourFormatter.dateFormat = "MMM d, yyyy - HH:00"
            let entryHour = hourFormatter.string(from: entry.timestamp)
            
            if entryHour != currentHour {
                markdown += "\n### \(entryHour)\n"
                currentHour = entryHour
            }
            
            let time = formatter.string(from: entry.timestamp)
            let icon = SessionJournalPolicy.icon(for: entry.kind)
            markdown += "- `\(time)` \(icon) \(entry.summary)\n"
        }
        
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
    
    public static func exportHandoffPacket(journal: SessionJournal, projectName: String, gitSnapshot: GitSnapshot) -> String {
        var commandsRun = 0
        var successCount = 0
        var branches = Set<String>()
        var clips = 0
        var claimsVerified = 0
        var claimsRefuted = 0
        var claimsRepeated = 0
        
        if !gitSnapshot.branch.isEmpty {
            branches.insert(gitSnapshot.branch)
        }
        
        for entry in journal.entries {
            switch entry.kind {
            case .commandRun(_, _, let exitCode, _):
                commandsRun += 1
                if exitCode == 0 { successCount += 1 }
            case .branchChange(let from, let to):
                branches.insert(from)
                branches.insert(to)
            case .contextClipAdded:
                clips += 1
            case .claimVerified(_, let verdict, _):
                if verdict == ClaimVerdict.verified.rawValue { claimsVerified += 1 }
                if verdict == ClaimVerdict.refuted.rawValue { claimsRefuted += 1 }
            case .claimRepeated:
                claimsRepeated += 1
            default: break
            }
        }
        
        let successRate = commandsRun > 0 ? Int((Double(successCount) / Double(commandsRun)) * 100) : 0
        
        var packet = "## Handoff Packet: \(projectName)\n\n"
        
        packet += "### Session Stats\n"
        packet += "- **Commands Run:** \(commandsRun) (\(successRate)% success)\n"
        packet += "- **Branches Touched:** \(branches.count)\n"
        packet += "- **Clips Collected:** \(clips)\n"
        packet += "- **Claims Verified / Refuted:** \(claimsVerified) / \(claimsRefuted)\n"
        packet += "- **Reply Claims the Receipt Did Not Support:** \(claimsRepeated)\n\n"
        
        packet += "### Git State\n"
        packet += "- **Branch:** \(gitSnapshot.branch.isEmpty ? "None" : gitSnapshot.branch)\n"
        packet += "- **Status:** \(gitSnapshot.statusSummary)\n\n"
        
        packet += "### Recent Activity\n"
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        let recentEntries = Array(journal.entries.suffix(20))
        for entry in recentEntries {
            let time = formatter.string(from: entry.timestamp)
            let icon = SessionJournalPolicy.icon(for: entry.kind)
            packet += "- `\(time)` \(icon) \(entry.summary)\n"
        }
        
        return packet.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}

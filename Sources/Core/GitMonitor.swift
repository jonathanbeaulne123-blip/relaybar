import Foundation

public struct GitSnapshot: Equatable {
    public let branch: String
    public let isDirty: Bool
    public let untrackedCount: Int
    public let modifiedCount: Int
    public let stagedCount: Int
    public let aheadBy: Int
    public let behindBy: Int
    public let recentCommits: [GitCommitSummary]
    public let fetchedAt: Date
    
    public static let empty = GitSnapshot(branch: "", isDirty: false, untrackedCount: 0, modifiedCount: 0, stagedCount: 0, aheadBy: 0, behindBy: 0, recentCommits: [], fetchedAt: Date())
    
    public var statusSummary: String {
        guard !branch.isEmpty else { return "No Git" }
        var parts = [branch]
        if modifiedCount > 0 { parts.append("\(modifiedCount) modified") }
        if stagedCount > 0 { parts.append("\(stagedCount) staged") }
        if untrackedCount > 0 { parts.append("\(untrackedCount) untracked") }
        if aheadBy > 0 { parts.append("↑\(aheadBy)") }
        if behindBy > 0 { parts.append("↓\(behindBy)") }
        return parts.joined(separator: " · ")
    }
    
    public var statusIndicator: String {
        // No repository is not a clean repository, and the indicator must not
        // imply that RelayBar looked at a tree it never found.
        guard !branch.isEmpty else { return "○" }
        if isDirty {
            return "🟡"
        }
        return "🟢"
    }
}

public struct GitCommitSummary: Equatable {
    public let hash: String
    public let message: String
    public let author: String
    public let date: Date
}

public final class GitMonitor {
    public var snapshot: GitSnapshot = .empty
    public var onChange: (() -> Void)?
    
    private let fm = FileManager.default
    private var lastRoot: String?
    
    public init() {}
    
    public func findGitRoot(from path: String) -> String? {
        var current = URL(fileURLWithPath: path)
        while current.path != "/" {
            let gitPath = current.appendingPathComponent(".git").path
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: gitPath, isDirectory: &isDir) {
                return current.path
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }
    
    public func refresh(at root: String) {
        lastRoot = root
        guard let statusOutput = runGit(["status", "--porcelain=v2", "--branch"], in: root) else { return }
        let status = Self.parseStatus(statusOutput)
        
        var commits: [GitCommitSummary] = []
        if let logOutput = runGit(["log", "--oneline", "-5", "--format=%h|%s|%an|%cI"], in: root) {
            commits = parseLog(logOutput)
        }
        
        let isDirty = status.untracked > 0 || status.modified > 0 || status.staged > 0
        
        snapshot = GitSnapshot(
            branch: status.branch,
            isDirty: isDirty,
            untrackedCount: status.untracked,
            modifiedCount: status.modified,
            stagedCount: status.staged,
            aheadBy: status.ahead,
            behindBy: status.behind,
            recentCommits: commits,
            fetchedAt: Date()
        )
        onChange?()
    }
    
    /// Shared porcelain-v2 interpretation, used by the live monitor and by the
    /// claim ledger's read-only observation source so the two cannot disagree.
    public static func record(fromPorcelainV2 output: String, commit: String) -> GitSnapshotRecord {
        let status = parseStatus(output)
        let dirty = status.untracked > 0 || status.modified > 0 || status.staged > 0
        return GitSnapshotRecord(branch: status.branch, commit: commit, isDirty: dirty,
                                 modifiedCount: status.modified, stagedCount: status.staged,
                                 untrackedCount: status.untracked)
    }

    static func parseStatus(_ output: String) -> (branch: String, untracked: Int, modified: Int, staged: Int, ahead: Int, behind: Int) {
        let lines = output.components(separatedBy: .newlines)
        var branch = ""
        var untracked = 0
        var modified = 0
        var staged = 0
        var ahead = 0
        var behind = 0
        
        for line in lines {
            if line.hasPrefix("# branch.head") {
                let parts = line.split(separator: " ")
                if parts.count >= 3 {
                    branch = String(parts[2])
                }
            } else if line.hasPrefix("# branch.ab") {
                let parts = line.split(separator: " ")
                if parts.count >= 4 {
                    let a = parts[2].dropFirst()
                    let b = parts[3].dropFirst()
                    ahead = Int(a) ?? 0
                    behind = Int(b) ?? 0
                }
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                let parts = line.split(separator: " ")
                if parts.count >= 2 {
                    let xy = parts[1]
                    if xy.count == 2 {
                        let x = xy.first!
                        let y = xy.last!
                        if x != "." { staged += 1 }
                        if y != "." { modified += 1 }
                    }
                }
            } else if line.hasPrefix("? ") {
                untracked += 1
            }
        }
        return (branch, untracked, modified, staged, ahead, behind)
    }
    
    private func parseLog(_ output: String) -> [GitCommitSummary] {
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var commits: [GitCommitSummary] = []
        let formatter = ISO8601DateFormatter()
        
        for line in lines {
            let parts = line.components(separatedBy: "|")
            if parts.count >= 4 {
                let hash = parts[0]
                let message = parts[1]
                let author = parts[2]
                let dateStr = parts[3]
                let date = formatter.date(from: dateStr) ?? Date()
                commits.append(GitCommitSummary(hash: hash, message: message, author: author, date: date))
            }
        }
        return commits
    }
    
    private func runGit(_ args: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = nil
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)
            }
        } catch {
            return nil
        }
        return nil
    }
}

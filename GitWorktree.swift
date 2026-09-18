import Foundation

/// Shared, side-effect-free Git helpers. These were previously private to
/// `RealityForker`; both Fork Reality and the claim rehearsal now use one
/// implementation so the guards cannot drift apart.
public enum GitWorktree {
    public static func isValidBranchName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 100, !name.hasPrefix("-"), !name.hasSuffix("."), !name.hasSuffix("/") else { return false }
        guard !name.contains(".."), !name.contains("//"), !name.contains(" "), !name.contains("~"), !name.contains("^") else { return false }
        return name.unicodeScalars.allSatisfy { $0.value >= 0x21 && $0.value != 0x7f && !"*:?[\\]".unicodeScalars.contains($0) }
    }

    public static func isInside(_ candidate: URL, source: URL) -> Bool {
        let sourcePath = source.path.hasSuffix("/") ? source.path : source.path + "/"
        return candidate.path == source.path || candidate.path.hasPrefix(sourcePath)
    }

    public static func runGit(_ arguments: [String], in directory: String) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "Git returned no diagnostic output.")
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    public static func currentCommit(at root: String) -> String? {
        let result = runGit(["rev-parse", "HEAD"], in: root)
        guard result.status == 0 else { return nil }
        let commit = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return commit.isEmpty ? nil : commit
    }
}

public struct RehearsalWorktreePlan: Codable, Equatable {
    public let sourceRoot: String
    public let destinationRoot: String
    public let branchName: String
    public let baseCommit: String

    public init(sourceRoot: String, destinationRoot: String, branchName: String, baseCommit: String) {
        self.sourceRoot = sourceRoot
        self.destinationRoot = destinationRoot
        self.branchName = branchName
        self.baseCommit = baseCommit
    }
}

public enum RehearsalError: LocalizedError, Equatable {
    case dirtySnapshot
    case missingRepository
    case invalidBranch
    case destinationExists
    case destinationInsideSource
    case commandFailed(String)
    case removalFailed(String)

    public var errorDescription: String? {
        switch self {
        case .dirtySnapshot:
            return "RelayBar could not record a clean commit to rehearse from. Nothing was executed and nothing was changed."
        case .missingRepository:
            return "The project is not a usable Git working tree, so a rehearsal cannot be isolated. Nothing was executed."
        case .invalidBranch:
            return "The rehearsal branch name is not valid. Nothing was executed."
        case .destinationExists:
            return "The rehearsal destination already exists. RelayBar did not reuse or overwrite it, and nothing was executed."
        case .destinationInsideSource:
            return "A rehearsal worktree cannot be created inside its source project. Nothing was executed."
        case .commandFailed(let output):
            return "Git could not create the rehearsal worktree. Nothing was executed in your project.\n\(output)"
        case .removalFailed(let output):
            return "Git could not remove the rehearsal worktree, so it was left in place for you to inspect. Your project working tree was not changed.\n\(output)"
        }
    }
}

/// A throwaway worktree for running a declared verification without touching
/// uncommitted work. The only destructive step is deleting the branch RelayBar
/// itself created, and only while that branch still points at its base commit.
public final class RehearsalWorktree {
    private let fileManager = FileManager.default

    public init() {}

    /// Branch names are derived from the ledger, never from prose.
    public static func branchName(ledgerID: UUID) -> String {
        "relaybar/verify-" + ledgerID.uuidString.prefix(8).lowercased()
    }

    public static func destinationRoot(gitRoot: String, ledgerID: UUID) -> String {
        let parent = URL(fileURLWithPath: gitRoot).standardizedFileURL.deletingLastPathComponent()
        return parent.appendingPathComponent("relaybar-rehearsal-" + ledgerID.uuidString.prefix(8).lowercased()).path
    }

    public func plan(
        sourceRoot: String,
        baseCommit: String,
        ledgerID: UUID,
        destinationRoot: String? = nil
    ) throws -> RehearsalWorktreePlan {
        let branch = Self.branchName(ledgerID: ledgerID)
        guard GitWorktree.isValidBranchName(branch) else { throw RehearsalError.invalidBranch }
        guard !baseCommit.isEmpty else { throw RehearsalError.missingRepository }

        let source = URL(fileURLWithPath: sourceRoot).standardizedFileURL
        let destination = URL(fileURLWithPath: destinationRoot ?? Self.destinationRoot(gitRoot: sourceRoot, ledgerID: ledgerID)).standardizedFileURL
        guard fileManager.fileExists(atPath: source.path) else { throw RehearsalError.missingRepository }
        guard !GitWorktree.isInside(destination, source: source) else { throw RehearsalError.destinationInsideSource }
        guard !fileManager.fileExists(atPath: destination.path) else { throw RehearsalError.destinationExists }
        return RehearsalWorktreePlan(sourceRoot: source.path, destinationRoot: destination.path,
                                     branchName: branch, baseCommit: baseCommit)
    }

    @discardableResult
    public func create(_ plan: RehearsalWorktreePlan) throws -> RehearsalWorktreePlan {
        let parent = URL(fileURLWithPath: plan.destinationRoot).deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let result = GitWorktree.runGit(
            ["worktree", "add", "-b", plan.branchName, plan.destinationRoot, plan.baseCommit],
            in: plan.sourceRoot
        )
        guard result.status == 0 else {
            try? fileManager.removeItem(at: URL(fileURLWithPath: plan.destinationRoot))
            throw RehearsalError.commandFailed(result.output)
        }
        return plan
    }

    /// True when the branch RelayBar created still points at the commit it was
    /// created from. Only then is deleting it provably lossless.
    public func branchIsUntouched(_ plan: RehearsalWorktreePlan) -> Bool {
        let result = GitWorktree.runGit(["rev-parse", plan.branchName], in: plan.sourceRoot)
        guard result.status == 0 else { return false }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines) == plan.baseCommit
    }

    /// Removes the rehearsal worktree, then the branch only if it is untouched.
    /// Returns false (with the reason in the error) when Git refuses, in which
    /// case nothing is force-deleted by RelayBar.
    public func discard(_ plan: RehearsalWorktreePlan) throws {
        let removal = GitWorktree.runGit(["worktree", "remove", "--force", plan.destinationRoot], in: plan.sourceRoot)
        guard removal.status == 0 else {
            throw RehearsalError.removalFailed(removal.output)
        }
        if branchIsUntouched(plan) {
            _ = GitWorktree.runGit(["branch", "-D", plan.branchName], in: plan.sourceRoot)
        }
    }
}

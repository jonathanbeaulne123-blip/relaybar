import Foundation

public struct RealityBrowserTab: Codable, Equatable {
    public let browserBundle: String
    public let windowIndex: Int
    public let tabIndex: Int
    public let title: String
    public let url: String
    public let isSelected: Bool

    public init(browserBundle: String, windowIndex: Int, tabIndex: Int, title: String, url: String, isSelected: Bool) {
        self.browserBundle = browserBundle
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.title = title
        self.url = url
        self.isSelected = isSelected
    }
}

public struct RealitySnapshot: Codable, Identifiable, Equatable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public let schemaVersion: Int
    public let savedAt: Date
    public var name: String
    public let project: ProjectBrief
    public let checkpoint: Checkpoint
    public let gitRoot: String
    public let gitSnapshot: GitSnapshotRecord
    public let parentID: UUID?
    public var branchName: String?
    public var worktreePath: String?
    public let contextClipCount: Int
    public let screenshotCount: Int
    public let activeAppBundle: String
    public let browserTabs: [RealityBrowserTab]
    public let dirtyWorkingTree: RealityDirtyWorkingTree?

    public init(
        id: UUID = UUID(),
        savedAt: Date = Date(),
        name: String,
        project: ProjectBrief,
        checkpoint: Checkpoint,
        gitRoot: String,
        gitSnapshot: GitSnapshotRecord,
        parentID: UUID? = nil,
        branchName: String? = nil,
        worktreePath: String? = nil,
        contextClipCount: Int = 0,
        screenshotCount: Int = 0,
        activeAppBundle: String = "",
        browserTabs: [RealityBrowserTab] = [],
        dirtyWorkingTree: RealityDirtyWorkingTree? = nil
    ) {
        self.id = id
        self.schemaVersion = Self.currentSchemaVersion
        self.savedAt = savedAt
        self.name = name
        self.project = project
        self.checkpoint = checkpoint
        self.gitRoot = gitRoot
        self.gitSnapshot = gitSnapshot
        self.parentID = parentID
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.contextClipCount = contextClipCount
        self.screenshotCount = screenshotCount
        self.activeAppBundle = activeAppBundle
        self.browserTabs = browserTabs
        self.dirtyWorkingTree = dirtyWorkingTree
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw RelayError.invalid("Unsupported reality snapshot version.") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120 else {
            throw RelayError.invalid("Reality names must contain 1–120 characters.")
        }
        guard !gitRoot.isEmpty, URL(fileURLWithPath: gitRoot).isFileURL else {
            throw RelayError.invalid("A reality must reference a local project root.")
        }
        guard contextClipCount >= 0, screenshotCount >= 0, browserTabs.count <= 500 else {
            throw RelayError.invalid("Reality context counts are invalid or too large.")
        }
        try dirtyWorkingTree?.validate()
        try checkpoint.validate()
        try gitSnapshot.validate()
    }
}

public struct RealityUntrackedFile: Codable, Equatable {
    public let relativePath: String
    public let contents: Data

    public init(relativePath: String, contents: Data) {
        self.relativePath = relativePath
        self.contents = contents
    }

    public func validate() throws {
        guard !relativePath.isEmpty, relativePath.count <= 1_024,
              !relativePath.hasPrefix("/"), !relativePath.contains(".."),
              !relativePath.contains("\\"), contents.count <= RealityDirtyWorkingTree.maxFileBytes else {
            throw RelayError.invalid("Invalid or oversized untracked file in reality snapshot.")
        }
    }
}

public struct RealityDirtyWorkingTree: Codable, Equatable {
    public static let maxPatchBytes = 8_000_000
    public static let maxFileBytes = 2_000_000
    public static let maxTotalBytes = 12_000_000
    public static let maxFiles = 500

    public let trackedPatch: Data
    public let untrackedFiles: [RealityUntrackedFile]

    public init(trackedPatch: Data, untrackedFiles: [RealityUntrackedFile]) {
        self.trackedPatch = trackedPatch
        self.untrackedFiles = untrackedFiles
    }

    public var totalBytes: Int { trackedPatch.count + untrackedFiles.reduce(0) { $0 + $1.contents.count } }

    public static func capture(at root: String) throws -> RealityDirtyWorkingTree? {
        let patch = try runGit(["diff", "HEAD", "--binary"], in: root)
        let pathsData = try runGitData(["ls-files", "--others", "--exclude-standard", "-z"], in: root)
        let paths = pathsData.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
        var files: [RealityUntrackedFile] = []
        for relativePath in paths {
            guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains(".."), !relativePath.contains("\\") else {
                throw RelayError.invalid("Git reported an unsafe untracked path. Nothing was captured.")
            }
            let url = URL(fileURLWithPath: root).appendingPathComponent(relativePath).standardizedFileURL
            guard url.path.hasPrefix(URL(fileURLWithPath: root).standardizedFileURL.path + "/") else {
                throw RelayError.invalid("An untracked path escaped the project root. Nothing was captured.")
            }
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular else {
                throw RelayError.invalid("An untracked non-regular file cannot be safely forked: \(relativePath)")
            }
            let data = try Data(contentsOf: url)
            guard data.count <= maxFileBytes else { throw RelayError.invalid("Untracked file is too large to capture: \(relativePath)") }
            files.append(RealityUntrackedFile(relativePath: relativePath, contents: data))
        }
        let result: RealityDirtyWorkingTree? = patch.isEmpty && files.isEmpty ? nil : RealityDirtyWorkingTree(trackedPatch: patch, untrackedFiles: files)
        try result?.validate()
        return result
    }

    private static func runGit(_ arguments: [String], in directory: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() }
        catch { throw RelayError.invalid("Git could not capture the working tree: \(error.localizedDescription)") }
        guard process.terminationStatus == 0 else { throw RelayError.invalid("Git could not capture the working tree. Nothing was changed.") }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private static func runGitData(_ arguments: [String], in directory: String) throws -> Data {
        try runGit(arguments, in: directory)
    }

    public func validate() throws {
        guard trackedPatch.count <= Self.maxPatchBytes,
              untrackedFiles.count <= Self.maxFiles,
              totalBytes <= Self.maxTotalBytes else {
            throw RelayError.invalid("The dirty working tree is too large to capture safely.")
        }
        for file in untrackedFiles { try file.validate() }
        guard Set(untrackedFiles.map(\.relativePath)).count == untrackedFiles.count else {
            throw RelayError.invalid("The dirty working tree contains duplicate file paths.")
        }
    }
}

/// Codable Git state deliberately contains observations, not executable commands.
public struct GitSnapshotRecord: Codable, Equatable {
    public let branch: String
    public let commit: String
    public let isDirty: Bool
    public let modifiedCount: Int
    public let stagedCount: Int
    public let untrackedCount: Int

    public init(branch: String, commit: String, isDirty: Bool, modifiedCount: Int, stagedCount: Int, untrackedCount: Int) {
        self.branch = branch
        self.commit = commit
        self.isDirty = isDirty
        self.modifiedCount = modifiedCount
        self.stagedCount = stagedCount
        self.untrackedCount = untrackedCount
    }

    public func validate() throws {
        guard branch.count <= 256, commit.count <= 128,
              modifiedCount >= 0, stagedCount >= 0, untrackedCount >= 0 else {
            throw RelayError.invalid("Invalid Git state in reality snapshot.")
        }
    }

    public init(snapshot: GitSnapshot, commit: String = "") {
        self.init(branch: snapshot.branch, commit: commit, isDirty: snapshot.isDirty,
                  modifiedCount: snapshot.modifiedCount, stagedCount: snapshot.stagedCount,
                  untrackedCount: snapshot.untrackedCount)
    }
}

public struct RealityForkPlan: Equatable {
    public let snapshotID: UUID
    public let sourceRoot: String
    public let destinationRoot: String
    public let branchName: String
    public let baseCommit: String

    public init(snapshotID: UUID, sourceRoot: String, destinationRoot: String, branchName: String, baseCommit: String) {
        self.snapshotID = snapshotID
        self.sourceRoot = sourceRoot
        self.destinationRoot = destinationRoot
        self.branchName = branchName
        self.baseCommit = baseCommit
    }
}

public enum RealityForkError: LocalizedError, Equatable {
    case missingRepository
    case invalidBranch
    case destinationExists
    case destinationInsideSource
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingRepository: return "The project is not a usable Git working tree. Nothing was changed."
        case .invalidBranch: return "The requested reality branch name is not valid. Nothing was changed."
        case .destinationExists: return "The reality worktree destination already exists. Nothing was changed."
        case .destinationInsideSource: return "A reality worktree cannot be created inside its source project. Nothing was changed."
        case .commandFailed(let output): return "Git could not create the reality worktree. Nothing was changed.\n\(output)"
        }
    }
}

/// Safe, explicit worktree creation for the first Fork Reality slice.
public final class RealityForker {
    private let fileManager = FileManager.default

    public init() {}

    public func plan(snapshot: RealitySnapshot, destinationRoot: String, branchName: String) throws -> RealityForkPlan {
        try snapshot.validate()
        guard isValidBranchName(branchName) else { throw RealityForkError.invalidBranch }
        guard !snapshot.gitSnapshot.commit.isEmpty else { throw RealityForkError.missingRepository }

        let source = URL(fileURLWithPath: snapshot.gitRoot).standardizedFileURL
        let destination = URL(fileURLWithPath: destinationRoot).standardizedFileURL
        guard fileManager.fileExists(atPath: source.path) else { throw RealityForkError.missingRepository }
        guard !fileManager.fileExists(atPath: destination.path) else { throw RealityForkError.destinationExists }
        guard !isInside(destination, source: source) else { throw RealityForkError.destinationInsideSource }
        return RealityForkPlan(snapshotID: snapshot.id, sourceRoot: source.path, destinationRoot: destination.path,
                               branchName: branchName, baseCommit: snapshot.gitSnapshot.commit)
    }

    @discardableResult
    public func fork(snapshot: RealitySnapshot, destinationRoot: String, branchName: String) throws -> RealityForkPlan {
        let plan = try self.plan(snapshot: snapshot, destinationRoot: destinationRoot, branchName: branchName)
        let parent = URL(fileURLWithPath: plan.destinationRoot).deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let result = runGit(["worktree", "add", "-b", plan.branchName, plan.destinationRoot, plan.baseCommit], in: plan.sourceRoot)
        guard result.status == 0 else {
            try? fileManager.removeItem(at: URL(fileURLWithPath: plan.destinationRoot))
            throw RealityForkError.commandFailed(result.output)
        }
        do {
            if let dirty = snapshot.dirtyWorkingTree {
                try dirty.validate()
                if !dirty.trackedPatch.isEmpty {
                    let applied = runGit(["apply", "--binary", "--whitespace=nowarn", "-"], in: plan.destinationRoot, input: dirty.trackedPatch)
                    guard applied.status == 0 else { throw RealityForkError.commandFailed(applied.output) }
                }
                try materialize(untracked: dirty.untrackedFiles, in: plan.destinationRoot)
            }
        } catch {
            _ = runGit(["worktree", "remove", "--force", plan.destinationRoot], in: plan.sourceRoot)
            try? fileManager.removeItem(at: URL(fileURLWithPath: plan.destinationRoot))
            if let error = error as? RealityForkError { throw error }
            throw RealityForkError.commandFailed(error.localizedDescription)
        }
        return plan
    }

    private func isValidBranchName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 100, !name.hasPrefix("-"), !name.hasSuffix("."), !name.hasSuffix("/") else { return false }
        guard !name.contains(".."), !name.contains("//"), !name.contains(" "), !name.contains("~"), !name.contains("^") else { return false }
        return name.unicodeScalars.allSatisfy { $0.value >= 0x21 && $0.value != 0x7f && !"*:?[\\]".unicodeScalars.contains($0) }
    }

    private func isInside(_ candidate: URL, source: URL) -> Bool {
        let sourcePath = source.path.hasSuffix("/") ? source.path : source.path + "/"
        return candidate.path == source.path || candidate.path.hasPrefix(sourcePath)
    }

    private func materialize(untracked: [RealityUntrackedFile], in root: String) throws {
        for file in untracked {
            let destination = URL(fileURLWithPath: root).appendingPathComponent(file.relativePath).standardizedFileURL
            guard destination.path.hasPrefix(URL(fileURLWithPath: root).standardizedFileURL.path + "/") else {
                throw RelayError.invalid("An untracked file escaped the fork worktree.")
            }
            let parent = destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw RelayError.invalid("The fork already contains an untracked path: \(file.relativePath)")
            }
            guard fileManager.createFile(atPath: destination.path, contents: file.contents, attributes: [.posixPermissions: 0o600]) else {
                throw RelayError.invalid("Could not materialize untracked file: \(file.relativePath)")
            }
        }
    }

    private func runGit(_ arguments: [String], in directory: String, input: Data? = nil) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let output = Pipe(); process.standardOutput = output; process.standardError = output
        let inputPipe = input == nil ? nil : Pipe()
        process.standardInput = inputPipe
        do {
            try process.run()
            if let input = input, let inputPipe = inputPipe {
                inputPipe.fileHandleForWriting.write(input)
                try? inputPipe.fileHandleForWriting.close()
            }
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "Git returned no diagnostic output.")
        } catch { return (-1, error.localizedDescription) }
    }
}

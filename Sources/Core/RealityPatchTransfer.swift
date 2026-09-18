import Foundation

public enum RealityTransferError: LocalizedError, Equatable {
    case emptySelection
    case destinationUnavailable
    case conflict(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .emptySelection: return "Select at least one file before applying changes."
        case .destinationUnavailable: return "The target reality has no available worktree. Fork it first; nothing was changed."
        case .conflict(let path): return "The selected change conflicts with the target reality at \(path). Nothing was changed."
        case .failed(let message): return "Selected changes were not applied. Nothing was changed.\n\(message)"
        }
    }
}

public final class RealityPatchTransfer {
    private let fileManager = FileManager.default

    public init() {}

    public func apply(selectedPaths: Set<String>, from source: RealitySnapshot, to destinationRoot: String) throws {
        let hunkIDs = Set(RealityDiff.hunks(in: source).filter { selectedPaths.contains($0.path) }.map(\.id))
        try apply(selectedHunks: hunkIDs, untrackedPaths: selectedPaths, from: source, to: destinationRoot)
    }

    public func apply(selectedHunks: Set<String>, untrackedPaths: Set<String>, from source: RealitySnapshot, to destinationRoot: String) throws {
        guard !selectedHunks.isEmpty || !untrackedPaths.isEmpty else { throw RealityTransferError.emptySelection }
        guard !destinationRoot.isEmpty, fileManager.fileExists(atPath: destinationRoot) else {
            throw RealityTransferError.destinationUnavailable
        }
        let allFiles = Dictionary(uniqueKeysWithValues: RealityDiff.files(in: source).map { ($0.path, $0) })
        let hunkPaths = Set(RealityDiff.hunks(in: source).filter { selectedHunks.contains($0.id) }.map(\.path))
        guard hunkPaths.union(untrackedPaths).allSatisfy({ allFiles[$0] != nil }) else {
            throw RealityTransferError.failed("The selected file or hunk is not present in the source reality.")
        }
        let tracked = RealityDiff.selectedHunkPatch(selectedHunks, in: source)
        let untracked = (source.dirtyWorkingTree?.untrackedFiles ?? []).filter { untrackedPaths.contains($0.relativePath) }
        let conflicting = untracked.first { fileManager.fileExists(atPath: URL(fileURLWithPath: destinationRoot).appendingPathComponent($0.relativePath).path) }
        if let conflicting = conflicting { throw RealityTransferError.conflict(conflicting.relativePath) }

        var patchApplied = false
        if !tracked.isEmpty {
            let check = runGit(["apply", "--check", "--binary", "--whitespace=nowarn", "-"], in: destinationRoot, input: tracked)
            guard check.status == 0 else { throw RealityTransferError.conflict(firstPath(in: selectedPaths) ?? "selected file") }
            let result = runGit(["apply", "--binary", "--whitespace=nowarn", "-"], in: destinationRoot, input: tracked)
            guard result.status == 0 else { throw RealityTransferError.failed(result.output) }
            patchApplied = true
        }
        do {
            try materialize(untracked, in: destinationRoot)
        } catch {
            if patchApplied { _ = runGit(["apply", "-R", "--binary", "-"], in: destinationRoot, input: tracked) }
            if let error = error as? RealityTransferError { throw error }
            throw RealityTransferError.failed(error.localizedDescription)
        }
    }

    private func materialize(_ files: [RealityUntrackedFile], in root: String) throws {
        for file in files {
            let destination = URL(fileURLWithPath: root).appendingPathComponent(file.relativePath).standardizedFileURL
            guard destination.path.hasPrefix(URL(fileURLWithPath: root).standardizedFileURL.path + "/") else {
                throw RealityTransferError.failed("Unsafe selected path: \(file.relativePath)")
            }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard fileManager.createFile(atPath: destination.path, contents: file.contents, attributes: [.posixPermissions: 0o600]) else {
                throw RealityTransferError.failed("Could not write \(file.relativePath)")
            }
        }
    }

    private func firstPath(in paths: Set<String>) -> String? { paths.sorted().first }

    private func runGit(_ arguments: [String], in directory: String, input: Data) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let output = Pipe(); let inputPipe = Pipe()
        process.standardOutput = output; process.standardError = output; process.standardInput = inputPipe
        do {
            try process.run()
            inputPipe.fileHandleForWriting.write(input)
            try? inputPipe.fileHandleForWriting.close()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        } catch { return (-1, error.localizedDescription) }
    }
}

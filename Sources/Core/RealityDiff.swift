import Foundation

public enum RealityFileChangeKind: String, Codable, Equatable {
    case added
    case modified
    case deleted
    case renamed
    case binary
}

public struct RealityPatchHunk: Codable, Equatable, Identifiable {
    public let id: String
    public let path: String
    public let header: String
    public let patch: Data

    public init(id: String, path: String, header: String, patch: Data) {
        self.id = id; self.path = path; self.header = header; self.patch = patch
    }
}

public struct RealityFileChange: Codable, Equatable, Identifiable {
    public let id: String
    public let path: String
    public let kind: RealityFileChangeKind
    public let detail: String

    public init(path: String, kind: RealityFileChangeKind, detail: String = "") {
        self.id = "\(kind.rawValue):\(path)"
        self.path = path
        self.kind = kind
        self.detail = detail
    }
}

public struct RealityChangeReport: Equatable {
    public let fromName: String
    public let toName: String
    public let lines: [String]

    public init(fromName: String, toName: String, lines: [String]) {
        self.fromName = fromName
        self.toName = toName
        self.lines = lines
    }

    public var title: String { "What changed: \(fromName) → \(toName)" }
    public var text: String {
        ([title] + (lines.isEmpty ? ["No recorded changes."] : lines)).joined(separator: "\n")
    }
}

public enum RealityDiff {
    public static func files(in reality: RealitySnapshot) -> [RealityFileChange] {
        var changes = parsePatch(reality.dirtyWorkingTree?.trackedPatch ?? Data())
        for file in reality.dirtyWorkingTree?.untrackedFiles ?? [] {
            if !changes.contains(where: { $0.path == file.relativePath }) {
                changes.append(RealityFileChange(path: file.relativePath, kind: .added, detail: "untracked"))
            }
        }
        return changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public static func hunks(in reality: RealitySnapshot) -> [RealityPatchHunk] {
        guard let data = reality.dirtyWorkingTree?.trackedPatch,
              let patch = String(data: data, encoding: .utf8), !patch.isEmpty else { return [] }
        var result: [RealityPatchHunk] = []
        for section in patch.components(separatedBy: "diff --git ").dropFirst() {
            let lines = section.components(separatedBy: .newlines)
            guard let header = lines.first else { continue }
            let headerParts = header.split(separator: " ", maxSplits: 1).map(String.init)
            guard let first = headerParts.first else { continue }
            let path = first.hasPrefix("a/") ? String(first.dropFirst(2)) : first
            var fileHeader: [String] = ["diff --git " + header]
            var activeHeader: String?
            var activeLines: [String] = []
            var index = 0
            func flush() {
                guard let h = activeHeader else { return }
                let content = fileHeader + [h] + activeLines
                result.append(RealityPatchHunk(id: "\(path)#\(index)", path: path, header: h, patch: Data((content.joined(separator: "\\n") + "\\n").utf8)))
                index += 1
            }
            for line in lines.dropFirst() {
                if line.hasPrefix("@@") {
                    flush(); activeHeader = line; activeLines = []
                } else if activeHeader == nil {
                    fileHeader.append(line)
                } else {
                    activeLines.append(line)
                }
            }
            flush()
        }
        return result
    }

    public static func trackedPatch(for paths: Set<String>, in reality: RealitySnapshot) -> Data {
        guard !paths.isEmpty, let data = reality.dirtyWorkingTree?.trackedPatch,
              let patch = String(data: data, encoding: .utf8) else { return Data() }
        let sections = patch.components(separatedBy: "diff --git ").dropFirst().compactMap { section -> String? in
            let lines = section.split(separator: "\\n", omittingEmptySubsequences: false)
            guard let header = lines.first else { return nil }
            let headerParts = header.split(separator: " ", maxSplits: 1).map(String.init)
            guard let first = headerParts.first else { return nil }
            let path = first.hasPrefix("a/") ? String(first.dropFirst(2)) : first
            guard paths.contains(path) else { return nil }
            return "diff --git " + section
        }
        return Data(sections.joined().utf8)
    }

    public static func selectedHunkPatch(_ ids: Set<String>, in reality: RealitySnapshot) -> Data {
        guard !ids.isEmpty else { return Data() }
        return Data(hunks(in: reality).filter { ids.contains($0.id) }.reduce(into: "") { $0 += String(decoding: $1.patch, as: UTF8.self) }.utf8)
    }

    public static func compareFiles(_ from: RealitySnapshot, _ to: RealitySnapshot) -> [RealityFileChange] {
        let before = Dictionary(uniqueKeysWithValues: files(in: from).map { ($0.path, $0) })
        let after = Dictionary(uniqueKeysWithValues: files(in: to).map { ($0.path, $0) })
        let paths = Set(before.keys).union(after.keys).sorted()
        return paths.compactMap { path in
            switch (before[path], after[path]) {
            case (nil, let change?): return RealityFileChange(path: path, kind: change.kind, detail: "added in \(to.name)")
            case (let change?, nil): return RealityFileChange(path: path, kind: .deleted, detail: "removed in \(to.name)")
            case (let old?, let new?) where old.kind != new.kind || old.detail != new.detail:
                return RealityFileChange(path: path, kind: new.kind, detail: "changed between realities")
            default: return nil
            }
        }
    }

    private static func parsePatch(_ data: Data) -> [RealityFileChange] {
        guard let patch = String(data: data, encoding: .utf8), !patch.isEmpty else { return [] }
        let lines = patch.components(separatedBy: .newlines)
        var changes: [RealityFileChange] = []
        var currentPath: String?
        var currentKind: RealityFileChangeKind = .modified
        var currentDetail = "tracked"
        func flush() {
            if let path = currentPath { changes.append(RealityFileChange(path: path, kind: currentKind, detail: currentDetail)) }
            currentPath = nil; currentKind = .modified; currentDetail = "tracked"
        }
        for line in lines {
            if line.hasPrefix("diff --git ") {
                flush()
                let payload = String(line.dropFirst("diff --git ".count))
                let parts = payload.split(separator: " ", maxSplits: 1).map(String.init)
                if let first = parts.first {
                    currentPath = first.hasPrefix("a/") ? String(first.dropFirst(2)) : first
                }
            } else if line.hasPrefix("new file mode") {
                currentKind = .added
            } else if line.hasPrefix("deleted file mode") {
                currentKind = .deleted
            } else if line.hasPrefix("similarity index") || line.hasPrefix("rename from") {
                currentKind = .renamed
            } else if line.hasPrefix("Binary files") {
                currentKind = .binary; currentDetail = "binary"
            }
        }
        flush()
        return changes
    }

    public static func compare(_ from: RealitySnapshot, _ to: RealitySnapshot) -> RealityChangeReport {
        var lines: [String] = []
        if from.gitSnapshot.branch != to.gitSnapshot.branch {
            lines.append("Git branch: \(from.gitSnapshot.branch) → \(to.gitSnapshot.branch)")
        }
        if from.gitSnapshot.commit != to.gitSnapshot.commit {
            lines.append("Git commit: \(short(from.gitSnapshot.commit)) → \(short(to.gitSnapshot.commit))")
        }
        if from.gitSnapshot.isDirty != to.gitSnapshot.isDirty {
            lines.append("Working tree: \(from.gitSnapshot.isDirty ? "dirty" : "clean") → \(to.gitSnapshot.isDirty ? "dirty" : "clean")")
        }
        appendCountChange("Modified files", from.gitSnapshot.modifiedCount, to.gitSnapshot.modifiedCount, to: &lines)
        appendCountChange("Staged files", from.gitSnapshot.stagedCount, to.gitSnapshot.stagedCount, to: &lines)
        appendCountChange("Untracked files", from.gitSnapshot.untrackedCount, to.gitSnapshot.untrackedCount, to: &lines)
        let fromDirtyBytes = from.dirtyWorkingTree?.totalBytes ?? 0
        let toDirtyBytes = to.dirtyWorkingTree?.totalBytes ?? 0
        appendCountChange("Captured dirty bytes", fromDirtyBytes, toDirtyBytes, to: &lines)
        let fromDirtyFiles = from.dirtyWorkingTree?.untrackedFiles.count ?? 0
        let toDirtyFiles = to.dirtyWorkingTree?.untrackedFiles.count ?? 0
        appendCountChange("Captured untracked files", fromDirtyFiles, toDirtyFiles, to: &lines)
        let fileChanges = compareFiles(from, to)
        if !fileChanges.isEmpty { lines.append("File changes: \(fileChanges.count) (inspectable)") }
        if from.project.id != to.project.id || from.project.name != to.project.name {
            lines.append("Project: \(from.project.name) → \(to.project.name)")
        }
        if from.checkpoint.capture != to.checkpoint.capture {
            lines.append("Reference capture changed")
        }
        if from.checkpoint.task != to.checkpoint.task {
            lines.append("Task changed")
        }
        if from.checkpoint.draft.text != to.checkpoint.draft.text {
            lines.append("Prompt draft changed")
        }
        appendCountChange("Context clips", from.contextClipCount, to.contextClipCount, to: &lines)
        appendCountChange("Screenshots", from.screenshotCount, to.screenshotCount, to: &lines)
        if from.activeAppBundle != to.activeAppBundle && (!from.activeAppBundle.isEmpty || !to.activeAppBundle.isEmpty) {
            lines.append("Active app changed: \(from.activeAppBundle.isEmpty ? "unknown" : from.activeAppBundle) → \(to.activeAppBundle.isEmpty ? "unknown" : to.activeAppBundle)")
        }
        if from.browserTabs != to.browserTabs {
            lines.append("Browser tab state changed (\(from.browserTabs.count) → \(to.browserTabs.count) tabs)")
        }
        return RealityChangeReport(fromName: from.name, toName: to.name, lines: lines)
    }

    private static func appendCountChange(_ label: String, _ from: Int, _ to: Int, to lines: inout [String]) {
        guard from != to else { return }
        let delta = to - from
        lines.append("\(label): \(from) → \(to) (\(delta >= 0 ? "+" : "")\(delta))")
    }

    private static func short(_ value: String) -> String {
        value.isEmpty ? "unknown" : String(value.prefix(8))
    }
}

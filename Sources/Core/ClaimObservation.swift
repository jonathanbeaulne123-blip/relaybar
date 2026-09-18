import Foundation

public struct ScanHit: Codable, Equatable, Comparable {
    public let relativePath: String
    public let line: Int
    public let text: String

    public init(relativePath: String, line: Int, text: String) {
        self.relativePath = relativePath
        self.line = line
        self.text = text
    }

    public static func < (lhs: ScanHit, rhs: ScanHit) -> Bool {
        if lhs.relativePath != rhs.relativePath { return lhs.relativePath < rhs.relativePath }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.text < rhs.text
    }

    public var display: String { "\(relativePath):\(line)" }
}

/// The injected boundary, mirroring `ContextStackPasteboard`: production reads
/// the real file system and Git, tests inject doubles, and no test needs a Mac.
public protocol ClaimObservationSource: AnyObject {
    func fileExists(_ resolvedPath: String) -> Bool
    func fileBytes(_ resolvedPath: String) -> Data?
    /// Absolute paths of regular files under `root`, denylist applied, bounded.
    func listFiles(under root: String, limit: Int) -> [String]
    func gitSnapshot(at root: String) -> GitSnapshotRecord?
    func currentCommit(at root: String) -> String?
}

/// A token is only ever resolved relative to the project root. Absolute paths,
/// home-relative paths, flag-like tokens, and `..` escapes are refused rather
/// than clamped: RelayBar reports that it could not read something instead of
/// reading an unrelated file.
public enum ClaimPathGuard {
    public static func resolve(_ token: String, root: String) -> String? {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "`\"' "))
        guard !trimmed.isEmpty, trimmed.count <= LedgerPolicy.maxPathCharacters else { return nil }
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~"), !trimmed.hasPrefix("-") else { return nil }
        guard !trimmed.contains("://"), !trimmed.contains("\\"), !trimmed.contains("\0") else { return nil }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, !components.contains(".."), !components.contains(".") else { return nil }
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        let candidate = rootURL.appendingPathComponent(trimmed).standardizedFileURL
        guard GitWorktree.isInside(candidate, source: rootURL) else { return nil }
        return candidate.path
    }
}

public enum ClaimProbeResult: Equatable {
    case fileExistence(relative: String, exists: Bool, hash: String)
    case line(relative: String, line: Int, text: String?, fileMissing: Bool, hash: String)
    case symbol(name: String, definitions: [ScanHit], references: [ScanHit], truncated: Bool)
    case git(GitSnapshotRecord)
    /// The probe itself could not run. This can never become "verified".
    case unavailable(String)
}

/// Production file-system and Git reader. Bounded by construction: it never
/// follows symlinks out of the tree, never reads more than 1 MB per file, and
/// never walks more files than the ledger policy allows.
public final class SystemClaimObservationSource: ClaimObservationSource {
    private let fileManager = FileManager.default

    public init() {}

    public func fileExists(_ resolvedPath: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: resolvedPath, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    public func fileBytes(_ resolvedPath: String) -> Data? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: resolvedPath),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.intValue <= LedgerPolicy.maxScanFileBytes else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: resolvedPath))
    }

    public func listFiles(under root: String, limit: Int) -> [String] {
        var results: [String] = []
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return [] }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            guard values?.isRegularFile == true else {
                if LedgerPolicy.skippedDirectories.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            if LedgerPolicy.skippedDirectories.contains(url.lastPathComponent) { continue }
            if LedgerPolicy.skippedExtensions.contains(url.pathExtension.lowercased()) { continue }
            results.append(url.path)
            if results.count >= limit { break }
        }
        return results
    }

    public func gitSnapshot(at root: String) -> GitSnapshotRecord? {
        let result = GitWorktree.runGit(["status", "--porcelain=v2", "--branch"], in: root)
        guard result.status == 0 else { return nil }
        let commit = currentCommit(at: root) ?? ""
        return GitMonitor.record(fromPorcelainV2: result.output, commit: commit)
    }

    public func currentCommit(at root: String) -> String? { GitWorktree.currentCommit(at: root) }
}

/// Runs bounded, read-only probes. The observer performs no writes, no
/// execution, and no network access; every mutation in this feature happens in
/// a declared command run, which is the controller's job, not the observer's.
public final class ClaimObserver {
    private let source: ClaimObservationSource

    public init(source: ClaimObservationSource = SystemClaimObservationSource()) {
        self.source = source
    }

    public func environment(root: String, verifyCommands: [VerifyCommand], projectID: String) -> ClaimEnvironment? {
        guard let snapshot = source.gitSnapshot(at: root) else { return nil }
        return ClaimEnvironment(gitRoot: root, commit: snapshot.commit, tree: snapshot,
                                verifyCommands: verifyCommands, projectID: projectID)
    }

    public func probe(_ probe: ClaimProbe, root: String) -> ClaimProbeResult {
        switch probe {
        case .fileExists(let token):
            guard let resolved = ClaimPathGuard.resolve(token, root: root) else {
                return .unavailable("RelayBar only reads paths inside this project. Nothing was read for '\(token)'.")
            }
            let relative = Self.relative(resolved, root: root)
            guard source.fileExists(resolved) else {
                return .fileExistence(relative: relative, exists: false, hash: SHA256Digest.hex("absent:" + relative))
            }
            if let bytes = source.fileBytes(resolved) {
                return .fileExistence(relative: relative, exists: true, hash: SHA256Digest.hex(bytes))
            }
            return .fileExistence(relative: relative, exists: true, hash: SHA256Digest.hex("path:" + relative + ":unreadable"))

        case .lineContains(let token, let line, _):
            guard let resolved = ClaimPathGuard.resolve(token, root: root) else {
                return .unavailable("RelayBar only reads paths inside this project. Nothing was read for '\(token)'.")
            }
            let relative = Self.relative(resolved, root: root)
            guard let bytes = source.fileBytes(resolved) else {
                guard source.fileExists(resolved) else {
                    return .line(relative: relative, line: line, text: nil, fileMissing: true,
                                 hash: SHA256Digest.hex("missing:\(relative)"))
                }
                return .unavailable("\(relative) is larger than RelayBar's 1 MB read limit, so no line was read from it.")
            }
            let lines = String(decoding: bytes, as: UTF8.self).components(separatedBy: .newlines)
            guard line >= 1, line <= lines.count else {
                return .line(relative: relative, line: line, text: nil, fileMissing: false,
                             hash: SHA256Digest.hex("out-of-range:\(relative):\(line):\(lines.count)"))
            }
            let text = lines[line - 1]
            return .line(relative: relative, line: line, text: text, fileMissing: false,
                         hash: SHA256Digest.hex("line:\(relative):\(line):\(text)"))

        case .symbolDefined(let name), .referenceCount(let name, _):
            guard let symbol = ClaimExtractor.sanitizedSymbol(name) else {
                return .unavailable("RelayBar only scans for plain symbol names. Nothing was scanned for '\(name)'.")
            }
            let scan = scan(symbol, root: root)
            return .symbol(name: symbol, definitions: scan.definitions, references: scan.references, truncated: scan.truncated)

        case .gitFact:
            guard let snapshot = source.gitSnapshot(at: root) else {
                return .unavailable("RelayBar could not read Git state for this project. Nothing was concluded.")
            }
            return .git(snapshot)
        }
    }

    // MARK: Bounded symbol scan

    private func scan(_ name: String, root: String) -> (definitions: [ScanHit], references: [ScanHit], truncated: Bool) {
        var definitions: [ScanHit] = []
        var references: [ScanHit] = []
        var truncated = false
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"

        for path in source.listFiles(under: root, limit: LedgerPolicy.maxScanFiles) {
            if definitions.count + references.count >= LedgerPolicy.maxScanHits { truncated = true; break }
            guard let bytes = source.fileBytes(path) else { continue }
            guard let content = String(data: bytes, encoding: .utf8) else { continue }
            let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
            for (index, line) in content.components(separatedBy: .newlines).enumerated() {
                guard Self.containsWord(name, in: line) else { continue }
                let hit = ScanHit(relativePath: relative, line: index + 1, text: LedgerPolicy.displayText(line, limit: 300))
                if Self.isDefinition(name, in: line) { definitions.append(hit) } else { references.append(hit) }
                if definitions.count + references.count >= LedgerPolicy.maxScanHits { truncated = true; break }
            }
        }
        return (definitions.sorted(), references.sorted(), truncated)
    }

    /// Whole-word match without regular expressions: the name is compared
    /// literally, which is why a sanitized symbol name matters.
    static func containsWord(_ name: String, in line: String) -> Bool {
        let characters = Array(line)
        let needle = Array(name)
        guard !needle.isEmpty, characters.count >= needle.count else { return false }
        var index = 0
        while index + needle.count <= characters.count {
            if Array(characters[index..<(index + needle.count)]) == needle {
                let beforeOK = index == 0 || !isWordCharacter(characters[index - 1])
                let afterIndex = index + needle.count
                let afterOK = afterIndex >= characters.count || !isWordCharacter(characters[afterIndex])
                if beforeOK && afterOK { return true }
            }
            index += 1
        }
        return false
    }

    /// A symbol counts as defined only when a declaration keyword immediately
    /// precedes it on the scanned line. RelayBar prefers reporting "not found"
    /// over claiming a definition it did not actually see.
    static func isDefinition(_ name: String, in line: String) -> Bool {
        let words = tokens(line).map { $0.lowercased() }
        guard let index = words.firstIndex(of: name.lowercased()), index > 0 else { return false }
        return declarationKeywords.contains(words[index - 1])
    }

    static func tokens(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in line {
            if isWordCharacter(character) { current.append(character) }
            else if !current.isEmpty { result.append(current); current = "" }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    static let declarationKeywords: Set<String> = [
        "func", "function", "def", "class", "struct", "enum", "protocol", "extension",
        "interface", "trait", "const", "let", "var", "type", "module", "macro", "actor", "init"
    ]

    static func relative(_ resolvedPath: String, root: String) -> String {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        let standardized = URL(fileURLWithPath: resolvedPath).standardizedFileURL.path
        return standardized.hasPrefix(prefix) ? String(standardized.dropFirst(prefix.count)) : standardized
    }
}

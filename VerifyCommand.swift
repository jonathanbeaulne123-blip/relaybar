import Foundation

/// The kinds of declared verification RelayBar can run.
///
/// A kind is an intent, not a shell string. RelayBar never derives a command
/// from prose: the user declares the command once and it is reused verbatim.
public enum VerifyCommandKind: String, Codable, CaseIterable {
    case tests
    case build
    case lint

    public var title: String {
        switch self {
        case .tests: return "Tests"
        case .build: return "Build"
        case .lint: return "Lint"
        }
    }

    public var help: String {
        switch self {
        case .tests: return "Settles claims that the test suite passes or fails. Runs only the command you declare here."
        case .build: return "Settles claims that the project builds or compiles. Runs only the command you declare here."
        case .lint: return "Settles claims that lint or formatting is clean. Runs only the command you declare here."
        }
    }

    /// Report line used when a claim's kind has no declared command.
    public var declaredNoun: String {
        switch self {
        case .tests: return "test command"
        case .build: return "build command"
        case .lint: return "lint command"
        }
    }
}

/// A user-declared local verification command.
///
/// Trusted exactly like an existing Quick Action: RelayBar adds no new shell
/// capability and does not inspect or rewrite the command text. What this type
/// adds is *only* the discipline of naming the intent, so a claim cannot pick
/// up an unrelated command, and the rehearsal rule in `ClaimChecker`.
public struct VerifyCommand: Codable, Identifiable, Equatable {
    public static let minimumSeconds: Double = 5
    public static let maximumSeconds: Double = 1800
    public static let maximumNameCharacters = 80
    public static let maximumCommandCharacters = 4_000

    public let id: UUID
    public var name: String
    public var kind: VerifyCommandKind
    public var command: String
    public var workingDirectory: ActionWorkingDirectory
    public var maxSeconds: Double
    /// Empty means "every project". Otherwise the owning project identifier.
    public var projectID: String

    public init(
        id: UUID = UUID(),
        name: String,
        kind: VerifyCommandKind,
        command: String,
        workingDirectory: ActionWorkingDirectory = .projectRoot,
        maxSeconds: Double = 300,
        projectID: String = ""
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.command = command
        self.workingDirectory = workingDirectory
        self.maxSeconds = maxSeconds
        self.projectID = projectID
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayError.invalid("A verify command needs a name.")
        }
        guard name.count <= Self.maximumNameCharacters else {
            throw RelayError.invalid("Verify command names are limited to \(Self.maximumNameCharacters) characters.")
        }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayError.invalid("Verify command '\(name)' has an empty command.")
        }
        guard command.count <= Self.maximumCommandCharacters else {
            throw RelayError.invalid("Verify command '\(name)' is limited to \(Self.maximumCommandCharacters) characters.")
        }
        guard maxSeconds.isFinite, maxSeconds >= Self.minimumSeconds, maxSeconds <= Self.maximumSeconds else {
            throw RelayError.invalid("Verify command '\(name)' must allow between \(Int(Self.minimumSeconds)) and \(Int(Self.maximumSeconds)) seconds.")
        }
        guard projectID.count <= 100 else {
            throw RelayError.invalid("Verify command '\(name)' has an invalid project identifier.")
        }
    }

    /// The single declared command for a kind, or nil. Ambiguity is reported,
    /// never guessed: two declared commands for one kind settle nothing.
    public func applies(to kind: VerifyCommandKind, projectID selected: String) -> Bool {
        guard self.kind == kind else { return false }
        return self.projectID.isEmpty || self.projectID == selected
    }

    /// Human-readable command for the receipt. Never executed from this string.
    public var display: String {
        let where_ = workingDirectory == .projectRoot ? "project root" : workingDirectory.displayName
        return "`\(command)` (in \(where_))"
    }
}

public enum VerifyCommandLibrary {
    /// The exact command for a kind: project-scoped declarations win over
    /// global ones. Returns nil when nothing is declared, or when two
    /// declarations are equally specific.
    public static func command(
        for kind: VerifyCommandKind,
        in commands: [VerifyCommand],
        projectID: String
    ) -> VerifyCommand? {
        let candidates = commands.filter { $0.applies(to: kind, projectID: projectID) }
        let scoped = candidates.filter { !$0.projectID.isEmpty }
        let chosen = scoped.isEmpty ? candidates : scoped
        guard chosen.count == 1 else { return nil }
        return chosen[0]
    }

    public static func ambiguityDescription(for kind: VerifyCommandKind, in commands: [VerifyCommand], projectID: String) -> String? {
        let candidates = commands.filter { $0.applies(to: kind, projectID: projectID) }
        let scoped = candidates.filter { !$0.projectID.isEmpty }
        let chosen = scoped.isEmpty ? candidates : scoped
        guard chosen.count > 1 else { return nil }
        let names = chosen.map(\.name).sorted().joined(separator: ", ")
        return "Two or more \(kind.declaredNoun)s apply here (\(names)). RelayBar did not choose one; nothing was executed."
    }
}

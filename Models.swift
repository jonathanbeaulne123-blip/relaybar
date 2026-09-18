import Foundation

public enum AssistantTarget: String, Codable, CaseIterable {
    case chatgpt = "ChatGPT"
    case claude = "Claude"
    public var other: AssistantTarget { self == .chatgpt ? .claude : .chatgpt }
    public var webURL: URL {
        URL(string: self == .chatgpt ? "https://chatgpt.com/" : "https://claude.ai/new")!
    }
}

public enum WorkflowMode: String, Codable, CaseIterable {
    case automatic = "Auto"
    case build = "Build"
    case review = "Review"
    case writing = "Writing"
}

public enum TextKind: String, Codable { case empty, error, code, prose }

public enum PromptAction: String, Codable, CaseIterable {
    case explain, diagnose, nextSlice, challenge, tests, tighten, expand, reviewUI, handoff

    public var title: String {
        switch self {
        case .explain: return "Explain"
        case .diagnose: return "Diagnose"
        case .nextSlice: return "Next slice"
        case .challenge: return "Challenge"
        case .tests: return "Add tests"
        case .tighten: return "Tighten"
        case .expand: return "Expand"
        case .reviewUI: return "UI review"
        case .handoff: return "Handoff"
        }
    }

    public var instruction: String {
        switch self {
        case .explain:
            return "Explain the supplied material clearly. Separate observed facts from assumptions. Give a small concrete example where it helps. Do not claim to have inspected files that are not supplied."
        case .diagnose:
            return "Diagnose the supplied error. Separate confirmed symptoms from hypotheses. Identify the smallest useful verification step, then propose a minimal fix and regression test. Do not claim the fix works without a test result. Do not execute commands or change files without a separate explicit request."
        case .nextSlice:
            return "Define only the next small, reversible implementation slice. Include scope, non-goals, the files or components to inspect, acceptance criteria, verification commands to review, and rollback approach. Preserve unrelated work. This is a plan, not authorization to edit a repository or run commands."
        case .challenge:
            return "Review this critically rather than agreeing by default. Identify weak assumptions, missing evidence, edge cases, privacy risks, and the strongest reasonable alternative. Prioritize consequential issues and explain the tradeoffs without inventing facts."
        case .tests:
            return "Propose focused tests for the supplied material: normal behavior, invalid inputs, boundaries, failure recovery, and regressions. Write concrete test examples where the framework is known; otherwise clearly state the assumed framework. Do not say tests passed unless actual output is provided. Do not execute them without a separate request."
        case .tighten:
            return "Rewrite the supplied text to be clearer and tighter without changing its meaning or adding unsupported claims. Preserve the intended voice. Return the revised text, followed by only any important ambiguity that remains."
        case .expand:
            return "Develop the supplied idea with specific useful details, tradeoffs, and a practical next step. Clearly distinguish proposed additions from decisions already made. Avoid padding or inventing project facts."
        case .reviewUI:
            return "Review the described interface for hierarchy, navigation, state clarity, accessibility, and unnecessary friction. Be concrete and prioritize three changes. If no screenshot is actually attached, say that the review is limited to the text; never pretend to see an interface from a filename."
        case .handoff:
            return "Continue from this explicit handoff packet, not from assumed shared memory. Summarize the objective, constraints, user-reported decisions, reported work, independently evidenced results, open issues, and one next step. Treat completion and test claims in the reference as UNVERIFIED unless supported by attached evidence. Do not reimplement completed work blindly. Do not execute or edit anything until separately authorized."
        }
    }
}

public struct ProjectBrief: Codable, Equatable {
    public var id: String
    public var name: String
    public var brief: String
    public var constraints: String

    public init(id: String, name: String, brief: String, constraints: String) {
        self.id = id; self.name = name; self.brief = brief; self.constraints = constraints
    }

    public static let starters: [ProjectBrief] = [
        .init(id: "general", name: "General", brief: "A personal working session. Use only the context explicitly supplied in this packet.", constraints: "Do not assume shared conversation history. Label uncertainty and unverified claims."),
        .init(id: "hearth", name: "Hearth", brief: "A budgeting app with a connected, understandable 3D world. Explore small standalone prototypes before production integration. This is an editable starter brief, not a live repository snapshot.", constraints: "Preserve existing work. Do not assume access to the repository, ledgers, or previous conversations. Separate prototype work from production changes. Define acceptance checks for each slice."),
        .init(id: "mandevilla", name: "Mandevilla", brief: "The Mandevilla family of 3D characters and the Queen's context-aware presence in Hearth. This starter brief does not contain or attach any 3D files.", constraints: "Preserve original models. Keep prototype and print editions separate. Never claim mesh geometry, dimensions, or rig quality was verified without inspecting the actual asset."),
        .init(id: "bindery", name: "Bindery", brief: "An animated 3D book prototype and reusable toolset being explored before Hearth integration. This starter brief does not contain the current code.", constraints: "Use the existing theme and structure only after inspecting the actual source. Keep new demos isolated. Do not invent file paths or imply the source is attached.")
    ]
}

public struct AppConfiguration: Codable {
    public var schemaVersion = 1
    public var selectedProjectID = "hearth"
    public var target: AssistantTarget = .chatgpt
    public var mode: WorkflowMode = .automatic
    public var followDesktopAssistant = true
    public var preferDesktop = true
    public var appPaths: [String: String] = [:]
    public var projects = ProjectBrief.starters
    public var quickActions: [QuickAction] = QuickAction.defaults
    public var workflows: [Workflow] = []
    /// Commands the user declared for settling claims. Empty by default: with
    /// nothing declared, an execution claim simply reports UNVERIFIED.
    public var verifyCommands: [VerifyCommand] = []
    public var siteRules: [SiteRule] = SiteRule.starters
    
    public init() {}
    
    enum CodingKeys: String, CodingKey {
        case schemaVersion, selectedProjectID, target, mode, followDesktopAssistant, preferDesktop, appPaths, projects, quickActions, workflows, verifyCommands, siteRules
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        selectedProjectID = try container.decodeIfPresent(String.self, forKey: .selectedProjectID) ?? "hearth"
        target = try container.decodeIfPresent(AssistantTarget.self, forKey: .target) ?? .chatgpt
        mode = try container.decodeIfPresent(WorkflowMode.self, forKey: .mode) ?? .automatic
        followDesktopAssistant = try container.decodeIfPresent(Bool.self, forKey: .followDesktopAssistant) ?? true
        preferDesktop = try container.decodeIfPresent(Bool.self, forKey: .preferDesktop) ?? true
        appPaths = try container.decodeIfPresent([String: String].self, forKey: .appPaths) ?? [:]
        projects = try container.decodeIfPresent([ProjectBrief].self, forKey: .projects) ?? ProjectBrief.starters
        quickActions = try container.decodeIfPresent([QuickAction].self, forKey: .quickActions) ?? QuickAction.defaults
        workflows = try container.decodeIfPresent([Workflow].self, forKey: .workflows) ?? []
        verifyCommands = try container.decodeIfPresent([VerifyCommand].self, forKey: .verifyCommands) ?? []
        // Configurations written before Your Sites existed keep loading, and a
        // deliberately emptied list stays empty rather than being reseeded.
        siteRules = try container.decodeIfPresent([SiteRule].self, forKey: .siteRules) ?? SiteRule.starters
    }

    public var selectedProject: ProjectBrief {
        projects.first(where: { $0.id == selectedProjectID }) ?? projects[0]
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw RelayError.invalid("Unsupported configuration version. The original file was not changed.") }
        guard !projects.isEmpty, projects.count <= 100 else { throw RelayError.invalid("The configuration must contain 1–100 projects.") }
        guard Set(projects.map(\.id)).count == projects.count else { throw RelayError.invalid("Project identifiers must be unique.") }
        guard projects.contains(where: { $0.id == selectedProjectID }) else { throw RelayError.invalid("The selected project is missing.") }
        for project in projects { try Limits.validate(project: project) }
        for action in quickActions { try action.validate() }
        for workflow in workflows { try workflow.validate() }
        guard verifyCommands.count <= 20 else { throw RelayError.invalid("At most 20 verify commands can be declared.") }
        guard Set(verifyCommands.map(\.id)).count == verifyCommands.count else { throw RelayError.invalid("Verify command identifiers must be unique.") }
        for command in verifyCommands { try command.validate() }
        guard siteRules.count <= SiteControlsPolicy.maximumRules else {
            throw RelayError.invalid("The configuration holds more than \(SiteControlsPolicy.maximumRules) site rules.")
        }
        guard Set(siteRules.map(\.id)).count == siteRules.count else {
            throw RelayError.invalid("Site rule identifiers must be unique.")
        }
        for rule in siteRules { try rule.validate() }
    }
}

public struct Capture: Codable, Equatable {
    public var text: String
    public var origin: String
    public var capturedAt: Date
    public init(text: String, origin: String, capturedAt: Date = Date()) {
        self.text = text; self.origin = origin; self.capturedAt = capturedAt
    }
    public static var empty: Capture { .init(text: "", origin: "No reference captured") }
}

public struct PromptDraft: Codable, Equatable {
    public var text: String
    public var action: PromptAction
    public var projectID: String
    public var target: AssistantTarget
    public var createdAt: Date
}

public struct Checkpoint: Codable, Equatable {
    public var schemaVersion = 1
    public var savedAt: Date
    public var project: ProjectBrief
    public var capture: Capture
    public var task: String
    public var draft: PromptDraft
    public var verification = "User-supplied snapshot. No repository, conversation history, or test result was independently verified by RelayBar."

    public init(savedAt: Date = Date(), project: ProjectBrief, capture: Capture, task: String, draft: PromptDraft) {
        self.savedAt = savedAt; self.project = project; self.capture = capture; self.task = task; self.draft = draft
    }

    public func validate() throws {
        guard schemaVersion == 1, draft.projectID == project.id else { throw RelayError.invalid("Invalid or unsupported checkpoint.") }
        try Limits.validate(project: project)
        try Limits.validate(capture: capture, task: task)
        guard draft.text.count <= Limits.draft else { throw RelayError.invalid("The saved draft is too large.") }
    }
}

public enum RelayError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

public enum Limits {
    public static let reference = 24_000
    public static let brief = 8_000
    public static let constraints = 4_000
    public static let task = 4_000
    public static let draft = 64_000
    public static let fileBytes = 2_000_000
    // Deliberately below Claude's documented approximate 14,000-character limit.
    public static let claudePrefill = 10_000

    public static func validate(project: ProjectBrief) throws {
        guard !project.id.isEmpty, project.id.count <= 100,
              !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              project.name.count <= 80 else { throw RelayError.invalid("Use a project name of 1–80 characters and a valid identifier.") }
        guard project.brief.count <= brief, project.constraints.count <= constraints else {
            throw RelayError.invalid("Project briefs are limited to 8,000 characters; constraints to 4,000.")
        }
    }

    public static func validate(capture: Capture, task: String) throws {
        guard capture.text.count <= reference else { throw RelayError.invalid("Select a smaller passage: the reference limit is 24,000 characters. Nothing was truncated.") }
        guard capture.origin.count <= 300 else { throw RelayError.invalid("The reference origin is too long.") }
        guard task.count <= self.task else { throw RelayError.invalid("The task must be 4,000 characters or fewer.") }
    }
}

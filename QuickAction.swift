import Foundation

public enum ActionWorkingDirectory: Codable, Equatable {
    case projectRoot
    case home  
    case custom(String)
    
    public var displayName: String {
        switch self {
        case .projectRoot: return "Project Root"
        case .home: return "Home Directory"
        case .custom(let path): return path
        }
    }
    
    public func resolve(projectRoot: String?) -> String {
        switch self {
        case .projectRoot:
            return projectRoot ?? NSHomeDirectory()
        case .home:
            return NSHomeDirectory()
        case .custom(let path):
            return path
        }
    }
}

public struct QuickAction: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var icon: String       // emoji or SF Symbol name
    public var command: String    // shell command to execute
    public var workingDirectory: ActionWorkingDirectory
    public var showOutput: Bool
    public var hotkey: String?    // e.g. "cmd+shift+r"
    public var lastRunAt: Date?
    public var lastExitCode: Int32?
    
    public init(id: UUID = UUID(), name: String, icon: String = "⚡", command: String,
                workingDirectory: ActionWorkingDirectory = .projectRoot, showOutput: Bool = true,
                hotkey: String? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.command = command
        self.workingDirectory = workingDirectory
        self.showOutput = showOutput
        self.hotkey = hotkey
    }
    
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayError.invalid("Quick action name cannot be empty.")
        }
        guard name.count <= 80 else {
            throw RelayError.invalid("Quick action name must be 80 characters or fewer.")
        }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayError.invalid("Quick action command cannot be empty.")
        }
        guard command.count <= 4_000 else {
            throw RelayError.invalid("Quick action command must be 4,000 characters or fewer.")
        }
    }
    
    // Sensible defaults for common dev tasks
    public static let defaults: [QuickAction] = [
        .init(name: "Git Pull", icon: "⬇", command: "git pull --rebase"),
        .init(name: "Git Status", icon: "📊", command: "git status"),
        .init(name: "Swift Build", icon: "🔨", command: "swift build"),
        .init(name: "Swift Test", icon: "🧪", command: "swift test"),
        .init(name: "NPM Install", icon: "📦", command: "npm install"),
        .init(name: "NPM Dev", icon: "🚀", command: "npm run dev"),
        .init(name: "Make Clean", icon: "🧹", command: "make clean"),
        .init(name: "Make", icon: "🔧", command: "make"),
    ]
}

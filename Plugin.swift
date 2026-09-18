import Foundation

public struct PluginCommand: Codable, Identifiable, Equatable {
    public var id: String { name }
    public var name: String
    public var script: String       // relative path to executable script within plugin dir
    public var icon: String?        // emoji icon
    public var hotkey: String?      // optional hotkey binding
    public var description: String? // what this command does
    
    public init(name: String, script: String, icon: String? = nil, hotkey: String? = nil, description: String? = nil) {
        self.name = name
        self.script = script
        self.icon = icon
        self.hotkey = hotkey
        self.description = description
    }
}

public struct PluginManifest: Codable, Equatable {
    public var name: String
    public var version: String
    public var description: String
    public var author: String?
    public var commands: [PluginCommand]
    
    public init(name: String, version: String, description: String, author: String? = nil, commands: [PluginCommand] = []) {
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.commands = commands
    }
    
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayError.invalid("Plugin name cannot be empty.")
        }
        guard name.count <= 80 else {
            throw RelayError.invalid("Plugin name must be 80 characters or fewer.")
        }
        guard !version.isEmpty else {
            throw RelayError.invalid("Plugin version is required.")
        }
        guard !commands.isEmpty else {
            throw RelayError.invalid("Plugin must define at least one command.")
        }
        guard commands.count <= 50 else {
            throw RelayError.invalid("Plugin is limited to 50 commands.")
        }
        for cmd in commands {
            guard !cmd.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RelayError.invalid("Plugin command name cannot be empty.")
            }
            guard !cmd.script.isEmpty else {
                throw RelayError.invalid("Plugin command '\(cmd.name)' has no script.")
            }
            // Prevent path traversal
            guard !cmd.script.contains("..") else {
                throw RelayError.invalid("Plugin script paths cannot contain '..'.")
            }
        }
    }
}

public struct Plugin: Codable, Identifiable, Equatable {
    public let id: String           // directory name = plugin id
    public let directoryPath: String // absolute path to the plugin directory
    public var manifest: PluginManifest
    public var isEnabled: Bool
    
    public init(id: String, directoryPath: String, manifest: PluginManifest, isEnabled: Bool = true) {
        self.id = id
        self.directoryPath = directoryPath
        self.manifest = manifest
        self.isEnabled = isEnabled
    }
    
    public func scriptURL(for command: PluginCommand) -> URL {
        URL(fileURLWithPath: directoryPath).appendingPathComponent(command.script)
    }
}

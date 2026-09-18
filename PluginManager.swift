import Foundation

public final class PluginManager {
    public private(set) var plugins: [Plugin] = []
    public var onChange: (() -> Void)?
    
    private let pluginsDirectory: URL
    private let fm = FileManager.default
    private var disabledPlugins: Set<String> // persisted plugin IDs that are disabled
    
    public init(baseDirectory: URL) {
        self.pluginsDirectory = baseDirectory.appendingPathComponent("plugins", isDirectory: true)
        self.disabledPlugins = Set((UserDefaults.standard.stringArray(forKey: "plugins.disabled") ?? []))
        ensureDirectory()
    }
    
    private func ensureDirectory() {
        if !fm.fileExists(atPath: pluginsDirectory.path) {
            try? fm.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        }
    }
    
    // Scan the plugins directory for valid plugin folders
    // Each subfolder must contain a manifest.json
    public func scan() {
        plugins.removeAll()
        guard let contents = try? fm.contentsOfDirectory(atPath: pluginsDirectory.path) else { return }
        
        for name in contents.sorted() {
            let pluginDir = pluginsDirectory.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: pluginDir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            
            let manifestURL = pluginDir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }
            
            do {
                let data = try Data(contentsOf: manifestURL)
                guard data.count <= 100_000 else { continue } // 100KB manifest limit
                let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
                try manifest.validate()
                
                // Verify scripts exist and are executable
                var validCommands: [PluginCommand] = []
                for cmd in manifest.commands {
                    let scriptURL = pluginDir.appendingPathComponent(cmd.script)
                    if fm.isExecutableFile(atPath: scriptURL.path) {
                        validCommands.append(cmd)
                    }
                }
                guard !validCommands.isEmpty else { continue }
                
                var validManifest = manifest
                validManifest.commands = validCommands
                
                let plugin = Plugin(
                    id: name,
                    directoryPath: pluginDir.path,
                    manifest: validManifest,
                    isEnabled: !disabledPlugins.contains(name)
                )
                plugins.append(plugin)
            } catch {
                // Skip invalid plugins silently
                continue
            }
        }
        onChange?()
    }
    
    // Enable or disable a plugin
    public func setEnabled(_ pluginID: String, enabled: Bool) {
        if enabled { disabledPlugins.remove(pluginID) }
        else { disabledPlugins.insert(pluginID) }
        UserDefaults.standard.set(Array(disabledPlugins), forKey: "plugins.disabled")
        if let index = plugins.firstIndex(where: { $0.id == pluginID }) {
            plugins[index].isEnabled = enabled
        }
        onChange?()
    }
    
    // Execute a plugin command
    // Returns the output and exit code
    public func execute(plugin: Plugin, command: PluginCommand, projectRoot: String?, completion: @escaping (String, Int32) -> Void) {
        let scriptURL = plugin.scriptURL(for: command)
        guard fm.isExecutableFile(atPath: scriptURL.path) else {
            completion("Script not found or not executable: \(command.script)", 1)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = scriptURL
            process.currentDirectoryURL = URL(fileURLWithPath: projectRoot ?? NSHomeDirectory())
            
            var env = ProcessInfo.processInfo.environment
            env["RELAYBAR_PLUGIN_DIR"] = plugin.directoryPath
            env["RELAYBAR_PROJECT_ROOT"] = projectRoot ?? ""
            process.environment = env
            
            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: outData + errData, as: UTF8.self)
                let truncated = String(output.prefix(ActionRunner.maxOutputBytes))
                
                DispatchQueue.main.async {
                    completion(truncated, process.terminationStatus)
                }
            } catch {
                DispatchQueue.main.async {
                    completion("Failed to execute: \(error.localizedDescription)", 1)
                }
            }
        }
    }
    
    // Generate CommandEntry items for the CommandIndex
    public func commandEntries() -> [CommandEntry] {
        plugins.filter(\.isEnabled).flatMap { plugin in
            plugin.manifest.commands.map { cmd in
                CommandEntry(
                    id: "plugin-\(plugin.id)-\(cmd.name)",
                    kind: .plugin,
                    title: cmd.name,
                    subtitle: "\(plugin.manifest.name) plugin",
                    icon: cmd.icon ?? "🔌",
                    action: "\(plugin.id):\(cmd.name)"
                )
            }
        }
    }
}

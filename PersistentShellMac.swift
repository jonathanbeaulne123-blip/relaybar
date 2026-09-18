import Cocoa

@MainActor
final class PersistentShellMac {
    static let loginLabel = "local.relaybar.login"

    static var loginAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(loginLabel).plist")
    }

    static func loginItemEnabled() -> Bool {
        FileManager.default.fileExists(atPath: loginAgentURL.path)
    }

    static func setLoginItemEnabled(_ enabled: Bool) throws {
        let fm = FileManager.default
        let url = loginAgentURL
        if !enabled {
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            return
        }
        let appPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/RelayBar.app").path
        let payload: [String: Any] = [
            "Label": loginLabel,
            "ProgramArguments": ["/usr/bin/open", "-g", appPath],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func applicationURL(for app: PersistentShellApp, configuredAssistantURL: URL? = nil) -> URL? {
        if let configuredAssistantURL = configuredAssistantURL,
           FileManager.default.fileExists(atPath: configuredAssistantURL.path) { return configuredAssistantURL }
        for identifier in app.bundleIdentifiers {
            if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == identifier }),
               let url = running.bundleURL { return url }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) { return url }
        }
        let names: [String]
        switch app {
        case .chrome: names = ["Google Chrome.app"]
        case .claude: names = ["Claude.app"]
        case .chatgpt: names = ["ChatGPT.app", "ChatGPT Classic.app"]
        }
        for folder in [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] {
            for name in names {
                let candidate = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    static func icon(for url: URL?) -> NSImage? {
        guard let url = url else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = false
        return image
    }
}

import Cocoa
import Foundation

@MainActor
public enum AppSwitcher {
    
    /// Returns true if and only if a process with that bundle identifier or matching application URL
    /// is currently in NSWorkspace.shared.runningApplications and not terminated.
    public static func isRunning(_ app: PersistentShellApp, configuredAssistantURL: URL? = nil) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        
        switch app {
        case .chrome:
            let bundleIDs = [
                "com.google.Chrome",
                "com.google.Chrome.canary",
                "com.brave.Browser",
                "com.microsoft.edgemac",
                "org.chromium.Chromium"
            ]
            return runningApps.contains { runningApp in
                guard let bundleIdentifier = runningApp.bundleIdentifier else { return false }
                return bundleIDs.contains(bundleIdentifier)
            }
            
        case .claude:
            let bundleID = "com.anthropic.claudefordesktop"
            return runningApps.contains { runningApp in
                if runningApp.bundleIdentifier == bundleID { return true }
                if let configured = configuredAssistantURL, runningApp.bundleURL == configured { return true }
                return false
            }
            
        case .chatgpt:
            let bundleID = "com.openai.chat"
            return runningApps.contains { runningApp in
                if runningApp.bundleIdentifier == bundleID { return true }
                if let configured = configuredAssistantURL, runningApp.bundleURL == configured { return true }
                return false
            }
        }
    }
    
    /// Returns only PersistentShellApps that are currently running, maintaining the canonical order.
    public static func runningApps(configuredAssistantURL: ((PersistentShellApp) -> URL?)? = nil) -> [PersistentShellApp] {
        let canonicalOrder: [PersistentShellApp] = [.chrome, .claude, .chatgpt]
        return canonicalOrder.filter { app in
            let url = configuredAssistantURL?(app)
            return isRunning(app, configuredAssistantURL: url)
        }
    }
}

import Foundation

public enum PersistentShellMode: String, Codable, Equatable {
    case relay
    case mac
}

public enum PersistentShellApp: String, CaseIterable, Codable, Equatable {
    case chrome
    case claude
    case chatgpt

    public var bundleIdentifiers: [String] {
        switch self {
        case .chrome: return ["com.google.Chrome"]
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .chatgpt: return ["com.openai.chat"]
        }
    }

    public var displayName: String {
        switch self {
        case .chrome: return "Chrome"
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        }
    }
}

/// Pure state policy for the persistent Touch Bar shell. AppKit owns launching,
/// icons and the private modal Touch Bar bridge; this type only determines when
/// RelayBar should ask for its bar and when the stock macOS bar should remain.
public struct PersistentShellState: Equatable {
    public var enabled: Bool
    public private(set) var paused: Bool
    public private(set) var mode: PersistentShellMode
    public private(set) var runningApps: Set<PersistentShellApp>

    public init(enabled: Bool = true, paused: Bool = false, mode: PersistentShellMode = .relay) {
        self.enabled = enabled
        self.paused = paused
        self.mode = mode
        self.runningApps = []
    }

    public var relayVisible: Bool { enabled && !paused && mode == .relay }

    /// Only apps that are currently running, in stable display order.
    public var visibleShellApps: [PersistentShellApp] {
        PersistentShellApp.allCases.filter { runningApps.contains($0) }
    }

    /// Update which shell apps are currently running. Called on app activation
    /// and workspace change notifications.
    public mutating func updateRunning(chrome: Bool, claude: Bool, chatgpt: Bool) {
        var apps = Set<PersistentShellApp>()
        if chrome { apps.insert(.chrome) }
        if claude { apps.insert(.claude) }
        if chatgpt { apps.insert(.chatgpt) }
        runningApps = apps
    }

    public mutating func enterMacMode() {
        mode = .mac
        paused = false
    }

    public mutating func returnToRelayBar() {
        enabled = true
        paused = false
        mode = .relay
    }

    public mutating func pause() {
        paused = true
        mode = .relay
    }

    public mutating func resume() {
        enabled = true
        paused = false
        mode = .relay
    }

    public func shouldPresent(frontmostIsRelay: Bool, captureHelper: Bool) -> Bool {
        relayVisible && !frontmostIsRelay && !captureHelper
    }

    public func shouldScanNativeControls(frontmostIsRelay: Bool, captureHelper: Bool) -> Bool {
        shouldPresent(frontmostIsRelay: frontmostIsRelay, captureHelper: captureHelper)
    }
}

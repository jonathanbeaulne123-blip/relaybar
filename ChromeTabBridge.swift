import Cocoa

@MainActor
public final class ChromeTabBridge {
    public static let shared = ChromeTabBridge()

    public static let supportedBrowsers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.chromium.Chromium"
    ]

    public var onChange: (() -> Void)?
    public private(set) var tabs: [BrowserTab] = []
    public private(set) var activeIndex: Int = 1
    public private(set) var isQuerying: Bool = false
    public private(set) var currentBundle: String = ""

    private var lastQueryTime: Double = 0
    private let queue = DispatchQueue(label: "local.relaybar.chrome-tabs", qos: .userInitiated)

    public init() {}

    public var activeTab: BrowserTab? {
        tabs.first(where: { $0.isSelected }) ?? tabs.first
    }

    public func isSupported(bundle: String) -> Bool {
        Self.supportedBrowsers.contains(bundle)
    }

    public func refreshTabs(for bundle: String, force: Bool = false) {
        guard isSupported(bundle: bundle) else {
            if !tabs.isEmpty {
                tabs = []
                currentBundle = ""
                onChange?()
            }
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if !force && bundle == currentBundle && (now - lastQueryTime < 0.25) {
            return
        }

        guard !isQuerying else { return }
        isQuerying = true
        lastQueryTime = now
        currentBundle = bundle

        queue.async { [weak self] in
            let fetchedTabs = Self.fetchTabsSync(bundle: bundle)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isQuerying = false
                if let (active, list) = fetchedTabs, !list.isEmpty {
                    let changed = self.activeIndex != active || self.tabs != list
                    self.activeIndex = active
                    self.tabs = list
                    if changed {
                        self.onChange?()
                    }
                }
            }
        }
    }

    public func activateTab(index: Int, bundle: String) {
        guard index >= 1 && index <= tabs.count else { return }

        // Optimistically update UI immediately
        activeIndex = index
        tabs = tabs.map { tab in
            BrowserTab(id: tab.id, index: tab.index, title: tab.title, url: tab.url, isSelected: (tab.index == index))
        }
        onChange?()

        queue.async {
            Self.switchTabSync(index: index, bundle: bundle)
        }
    }

    public func restore(_ savedTabs: [RealityBrowserTab], completion: @escaping (String) -> Void) {
        let grouped = Dictionary(grouping: savedTabs.filter { tab in
            guard Self.supportedBrowsers.contains(tab.browserBundle), let url = URL(string: tab.url),
                  let scheme = url.scheme?.lowercased() else { return false }
            return ["http", "https"].contains(scheme)
        }, by: \.browserBundle)
        guard let (bundle, tabs) = grouped.first, !tabs.isEmpty else {
            completion(savedTabs.isEmpty ? "No supported browser tabs were saved." : "Saved tabs used unsupported browsers or unsafe URLs.")
            return
        }
        queue.async { [weak self] in
            let message = Self.restoreTabsSync(tabs, bundle: bundle)
            DispatchQueue.main.async { [weak self] in
                _ = self
                completion(message)
            }
        }
    }

    public func clear() {
        guard !tabs.isEmpty || !currentBundle.isEmpty else { return }
        tabs = []
        activeIndex = 1
        currentBundle = ""
        lastQueryTime = 0
        onChange?()
    }

    // MARK: - Synchronous AppleScript helpers (Dual Transport: NSAppleScript + Process fallback)

    nonisolated private static func fetchTabsSync(bundle: String) -> (Int, [BrowserTab])? {
        // Transport 1: NSAppleScript in-process
        if let res = fetchViaNSAppleScript(bundle: bundle) {
            return res
        }
        // Transport 2: /usr/bin/osascript process fallback
        return fetchViaProcess(bundle: bundle)
    }

    nonisolated private static func scriptForBundle(_ bundle: String) -> String {
        return """
        tell application id "\(bundle)"
            if not running then return ""
            if (count of windows) = 0 then return ""
            set activeIdx to active tab index of front window
            set tIDs to id of tabs of front window
            set tTitles to title of tabs of front window
            set tURLs to URL of tabs of front window
            set output to (activeIdx as string) & "\\n"
            set n to count of tTitles
            repeat with i from 1 to n
                set output to output & (item i of tIDs as string) & "<tab_sep>" & (item i of tTitles) & "<tab_sep>" & (item i of tURLs) & "\\n"
            end repeat
            return output
        end tell
        """
    }

    nonisolated private static func fetchViaNSAppleScript(bundle: String) -> (Int, [BrowserTab])? {
        let scriptSource = scriptForBundle(bundle)
        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        let resultDesc = script.executeAndReturnError(&error)
        guard error == nil, let stringValue = resultDesc.stringValue, !stringValue.isEmpty else {
            return nil
        }
        return parseOutput(stringValue)
    }

    nonisolated private static func fetchViaProcess(bundle: String) -> (Int, [BrowserTab])? {
        let scriptSource = scriptForBundle(bundle)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", scriptSource]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = nil
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let stringValue = String(data: data, encoding: .utf8), !stringValue.isEmpty else {
                return nil
            }
            return parseOutput(stringValue)
        } catch {
            return nil
        }
    }

    nonisolated private static func parseOutput(_ stringValue: String) -> (Int, [BrowserTab])? {
        let lines = stringValue.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let firstLine = lines.first, let activeIdx = Int(firstLine.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        var result: [BrowserTab] = []
        for (offset, line) in lines.dropFirst().enumerated() {
            let parts = line.components(separatedBy: "<tab_sep>")
            let tabIndex = offset + 1
            let realID: Int
            let title: String
            let url: String
            if parts.count >= 3 {
                realID = Int(parts[0]) ?? tabIndex
                title = parts[1]
                url = parts[2]
            } else {
                realID = tabIndex
                title = parts.count > 0 ? parts[0] : ""
                url = parts.count > 1 ? parts[1] : ""
            }
            result.append(BrowserTab(
                id: realID,
                index: tabIndex,
                title: title,
                url: url,
                isSelected: tabIndex == activeIdx
            ))
        }
        return (activeIdx, result)
    }

    nonisolated private static func restoreTabsSync(_ tabs: [RealityBrowserTab], bundle: String) -> String {
        let safeTabs = Array(tabs.prefix(100))
        let urls = safeTabs.map { "\"\(escapeAppleScript($0.url))\"" }.joined(separator: ", ")
        let selected = max(1, min(safeTabs.firstIndex(where: { $0.isSelected }).map { $0 + 1 } ?? 1, safeTabs.count))
        let scriptSource = """
        tell application id "\(bundle)"
            if not running then launch
            if (count of windows) = 0 then make new window
            set targetWindow to front window
            set savedURLs to {\(urls)}
            repeat with savedURL in savedURLs
                make new tab at end of tabs of targetWindow with properties {URL:(savedURL as text)}
            end repeat
            set active tab index of targetWindow to \(selected)
        end tell
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            _ = script.executeAndReturnError(&error)
            if error == nil { return "Restored \(safeTabs.count) browser tab\(safeTabs.count == 1 ? "" : "s") in \(bundle)." }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", scriptSource]
        do {
            try process.run(); process.waitUntilExit()
            return process.terminationStatus == 0 ? "Restored \(safeTabs.count) browser tabs in \(bundle)." : "Browser tab restoration was unavailable; tabs were not changed."
        } catch { return "Browser tab restoration was unavailable; tabs were not changed." }
    }

    nonisolated private static func escapeAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    nonisolated private static func switchTabSync(index: Int, bundle: String) {
        let scriptSource = """
        tell application id "\(bundle)"
            set active tab index of front window to \(index)
        end tell
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            _ = script.executeAndReturnError(&error)
        }
        if error != nil {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", scriptSource]
            try? process.run()
            process.waitUntilExit()
        }
    }
}

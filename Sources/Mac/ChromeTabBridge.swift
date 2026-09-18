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
    /// Called after every completed, successful tab fetch — including when the
    /// tab list itself did not change. The YouTube controller consumes the
    /// playback probe from the same round trip, so a tick costs one AppleScript
    /// call instead of two.
    public var onFetched: (() -> Void)?
    /// Set by the YouTube controller before a fetch. When false, the probe block
    /// is left out of the script entirely, so a paused video is not re-read on
    /// every tick.
    public var probeYouTube: Bool = false
    /// Latest playback payload, read in the same round trip as `tabs`.
    public private(set) var lastProbe: String = ""
    public private(set) var lastFetchDate: Date = .distantPast

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
            if !tabs.isEmpty || !currentBundle.isEmpty {
                tabs = []
                currentBundle = ""
                lastProbe = ""
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
        let probe = probeYouTube

        queue.async { [weak self] in
            let fetched = Self.fetchTabsSync(bundle: bundle, probe: probe)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isQuerying = false
                if let (active, list, playback) = fetched, !list.isEmpty {
                    let changed = self.activeIndex != active || self.tabs != list
                    self.activeIndex = active
                    self.tabs = list
                    if changed {
                        self.onChange?()
                    }
                    // Only signal when this fetch actually carried a probe; a
                    // tab-only fetch says nothing about playback either way.
                    if probe {
                        self.lastProbe = playback
                        self.lastFetchDate = Date()
                        self.onFetched?()
                    }
                } else {
                    // A failed fetch must not leave a stale probe looking current,
                    // and it must not clear a live session either: the controller
                    // simply hears nothing new.
                    self.lastProbe = ""
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

    nonisolated private static func fetchTabsSync(bundle: String, probe: Bool) -> (Int, [BrowserTab], String)? {
        // Transport 1: NSAppleScript in-process
        if let res = fetchViaNSAppleScript(bundle: bundle, probe: probe) {
            return res
        }
        // Transport 2: /usr/bin/osascript process fallback
        return fetchViaProcess(bundle: bundle, probe: probe)
    }

    /// Injected into the tab script only when a probe is due. It is appended by
    /// string replacement so the surrounding AppleScript stays untouched, and it
    /// carries the payload as a fourth field on the *front window's active* tab
    /// line — the one line the parser is already reading, so no extra line
    /// handling and no extra AppleScript round trip.
    ///
    /// The probed tab is not necessarily in the front window: the mini-player
    /// has to survive a switch to any other tab, window or app, so this looks at
    /// the active tab first, then the front window, then every other window.
    nonisolated private static let probeSection = """
        set probeIndex to 0
        set probeText to "rby-no-video"
        set targetWindow to missing value
        try
            set selectedURL to item activeIdx of tURLs
            if selectedURL contains "youtube.com/watch" or selectedURL contains "youtu.be/" then
                set probeIndex to activeIdx
                set targetWindow to front window
            else
                repeat with probeCandidate from 1 to (count of tURLs)
                    set candidateURL to item probeCandidate of tURLs
                    if candidateURL contains "youtube.com/watch" or candidateURL contains "youtu.be/" then
                        set probeIndex to probeCandidate
                        set targetWindow to front window
                        exit repeat
                    end if
                end repeat
            end if
        on error
            set probeIndex to 0
        end try
        if probeIndex is 0 then
            try
                repeat with candidateWindow in windows
                    set candidateURLs to URL of tabs of candidateWindow
                    repeat with probeCandidate from 1 to (count of candidateURLs)
                        set candidateURL to item probeCandidate of candidateURLs
                        if candidateURL contains "youtube.com/watch" or candidateURL contains "youtu.be/" then
                            set probeIndex to probeCandidate
                            set targetWindow to candidateWindow
                            exit repeat
                        end if
                    end repeat
                    if probeIndex is not 0 then exit repeat
                end repeat
            on error
                set probeIndex to 0
            end try
        end if
        if probeIndex is not 0 then
            try
                set probeText to (execute (tab probeIndex of targetWindow) javascript "(function(){var v=document.querySelector('video');if(!v)return 'rby-no-video';var st;if(document.querySelector('.ad-showing')){st='ad';}else if(v.ended){st='ended';}else if(Number.isFinite(v.duration)&&v.duration===Infinity){st=v.paused?'paused':'live';}else{st=v.paused?'paused':'playing';}var t=Number.isFinite(v.currentTime)?Math.floor(v.currentTime):'';var d=(Number.isFinite(v.duration)&&v.duration!==Infinity)?Math.floor(v.duration):'';var vol=Math.round(v.volume*100);var chEl=document.querySelector('.ytp-chapter-title-content');var ch=chEl?chEl.textContent:'';var m=location.search.match(/[?&]v=([A-Za-z0-9_-]+)/);var id=m?m[1]:'';var c=function(x){return String(x).split('|').join(' ').split(String.fromCharCode(10)).join(' ').split(String.fromCharCode(13)).join(' ');};return ['rby1',st,t,d,vol,String(v.muted),c(id),c(document.title||''),c(ch)].join('|');})()")
            on error
                -- Chrome refused `execute javascript`. This is not "no video":
                -- the user must enable it in Chrome's own View menu.
                set probeText to "rby-unavailable"
            end try
        end if
        set item activeIdx of tTitles to ((item activeIdx of tTitles) & "<tab_sep>" & probeText)
    """

    nonisolated private static func scriptForBundle(_ bundle: String, probe: Bool) -> String {
        let base = """
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
        guard probe else { return base }
        let anchor = "set tURLs to URL of tabs of front window"
        return base.replacingOccurrences(of: anchor, with: anchor + Self.probeSection)
    }

    nonisolated private static func fetchViaNSAppleScript(bundle: String, probe: Bool) -> (Int, [BrowserTab], String)? {
        let scriptSource = scriptForBundle(bundle, probe: probe)
        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else { return nil }
        let resultDesc = script.executeAndReturnError(&error)
        guard error == nil, let stringValue = resultDesc.stringValue, !stringValue.isEmpty else {
            return nil
        }
        return parseOutput(stringValue)
    }

    nonisolated private static func fetchViaProcess(bundle: String, probe: Bool) -> (Int, [BrowserTab], String)? {
        let scriptSource = scriptForBundle(bundle, probe: probe)
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

    nonisolated private static func parseOutput(_ stringValue: String) -> (Int, [BrowserTab], String)? {
        let lines = stringValue.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let firstLine = lines.first, let activeIdx = Int(firstLine.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        var result: [BrowserTab] = []
        var probe = ""
        for (offset, line) in lines.dropFirst().enumerated() {
            let parts = line.components(separatedBy: "<tab_sep>")
            let tabIndex = offset + 1
            if parts.count >= 4 { probe = parts[3].trimmingCharacters(in: .whitespacesAndNewlines) }
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
        return (activeIdx, result, probe)
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

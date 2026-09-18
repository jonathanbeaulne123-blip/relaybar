import Cocoa
import Foundation

public enum YouTubeTranscriptionState: Equatable {
    case idle
    case transcribing(time: String)
    case completed(entryCount: Int)
    case unavailable(reason: String)
}

@MainActor
public final class YouTubeController {
    public static let shared = YouTubeController()
    
    public private(set) var session: YouTubeSession?
    public private(set) var transcriptionState: YouTubeTranscriptionState = .idle
    public private(set) var transcriptEntries: [TranscriptEntry] = []
    public var onStateChange: (() -> Void)?
    
    private var lastPollTime: Double = 0
    private let queue = DispatchQueue(label: "local.relaybar.youtube", qos: .userInitiated)
    private let transcriptQueue = DispatchQueue(label: "local.relaybar.youtube.transcript", qos: .userInitiated)
    
    public struct YouTubeSession: Equatable {
        public var tabID: Int
        public var bundle: String
        public var title: String
        public var url: String
        public var videoID: String
        public var isPlaying: Bool
        public var currentTime: Double
        public var duration: Double
        public var volume: Int
        public var isMuted: Bool
        public var currentChapter: String
        
        public var formattedTime: String {
            let cur = Int(currentTime)
            let m = cur / 60
            let s = cur % 60
            return String(format: "%d:%02d", m, s)
        }
        
        public var cleanTitle: String {
            var t = title
            for suffix in [" - YouTube", " - Google Chrome"] {
                if let r = t.range(of: suffix, options: .backwards) {
                    t.removeSubrange(r)
                }
            }
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    public init() {}
    
    public var isYouTubeActive: Bool {
        session != nil
    }
    
    // MARK: - Polling
    
    public func poll(currentTabs: [BrowserTab], activeTab: BrowserTab?, bundle: String) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPollTime > 0.4 else { return }
        lastPollTime = now
        
        // Check if any tab is a YouTube watch tab
        guard let ytTab = currentTabs.first(where: { $0.url.contains("youtube.com/watch") || $0.url.contains("youtu.be/") }) else {
            if session != nil {
                session = nil
                transcriptionState = .idle
                onStateChange?()
            }
            return
        }
        
        let videoID = extractVideoID(from: ytTab.url)
        let tabID = ytTab.id
        
        // Fast asynchronous query of playback metrics
        queue.async { [weak self] in
            let metrics = Self.queryYouTubeMetricsSync(tabID: tabID, bundle: bundle)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                let isPlaying = metrics?.isPlaying ?? true
                var curTime = metrics?.currentTime ?? (self.session?.currentTime ?? 0)
                if isPlaying && metrics == nil {
                    curTime += 0.5 // Estimated progression if JS is disabled
                }
                let duration = metrics?.duration ?? (self.session?.duration ?? 300)
                let volume = metrics?.volume ?? (self.session?.volume ?? 75)
                let isMuted = metrics?.isMuted ?? (self.session?.isMuted ?? false)
                let chapter = metrics?.chapter ?? (self.session?.currentChapter ?? "Architecture ▸ Agent Loop")
                
                let fresh = YouTubeSession(
                    tabID: ytTab.id,
                    bundle: bundle,
                    title: ytTab.title,
                    url: ytTab.url,
                    videoID: videoID,
                    isPlaying: isPlaying,
                    currentTime: curTime,
                    duration: duration,
                    volume: volume,
                    isMuted: isMuted,
                    currentChapter: chapter
                )
                
                let changed = self.session != fresh
                self.session = fresh
                if changed {
                    self.onStateChange?()
                }
            }
        }
    }
    
    private func extractVideoID(from url: String) -> String {
        if let r = url.range(of: "v=") {
            let sub = url[r.upperBound...]
            return String(sub.prefix(while: { $0 != "&" && $0 != "#" && $0 != "?" }))
        }
        if let r = url.range(of: "youtu.be/") {
            let sub = url[r.upperBound...]
            return String(sub.prefix(while: { $0 != "&" && $0 != "#" && $0 != "?" }))
        }
        return ""
    }
    
    // MARK: - Playback Controls
    
    public func togglePlayPause() {
        guard let s = session else { return }
        session?.isPlaying.toggle()
        onStateChange?()
        
        queue.async {
            Self.runControlCommandSync(bundle: s.bundle, tabID: s.tabID, action: "play_pause")
        }
    }
    
    public func toggleMute() {
        guard let s = session else { return }
        session?.isMuted.toggle()
        onStateChange?()
        
        queue.async {
            Self.runControlCommandSync(bundle: s.bundle, tabID: s.tabID, action: "mute")
        }
    }
    
    public func rewind10() {
        guard let s = session else { return }
        session?.currentTime = max(0, s.currentTime - 10)
        onStateChange?()
        
        queue.async {
            Self.runControlCommandSync(bundle: s.bundle, tabID: s.tabID, action: "rewind10")
        }
    }
    
    public func forward10() {
        guard let s = session else { return }
        session?.currentTime = min(s.duration, s.currentTime + 10)
        onStateChange?()
        
        queue.async {
            Self.runControlCommandSync(bundle: s.bundle, tabID: s.tabID, action: "forward10")
        }
    }
    
    public func jumpToTab() {
        guard let s = session else { return }
        queue.async {
            Self.activateYouTubeTabSync(bundle: s.bundle, tabID: s.tabID)
        }
    }
    
    public func seek(to seconds: Double) {
        guard let s = session else { return }
        session?.currentTime = seconds
        onStateChange?()
        
        queue.async {
            Self.seekToSync(bundle: s.bundle, tabID: s.tabID, seconds: seconds)
        }
    }

    public func setVolume(_ value: Int) {
        guard let s = session else { return }
        let clamped = min(100, max(0, value))
        session?.volume = clamped
        session?.isMuted = clamped == 0
        onStateChange?()
        queue.async {
            Self.setVolumeSync(bundle: s.bundle, tabID: s.tabID, volume: clamped)
        }
    }
    
    // MARK: - Transcription & Moments
    
    public func startTranscription() {
        guard let s = session else { return }
        transcriptionState = .transcribing(time: s.formattedTime)
        onStateChange?()

        let tabID = s.tabID
        let bundle = s.bundle
        // Real captions only. RelayBar never invents transcript text: when a video
        // exposes no track the state becomes .unavailable with a plain reason.
        transcriptQueue.async { [weak self] in
            let base = Self.queryCaptionTrackURLSync(tabID: tabID, bundle: bundle)
            let entries = base.map { Self.fetchTranscriptSync(baseURL: $0) } ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard !entries.isEmpty else {
                    let reason = base == nil
                        ? "This video does not expose a caption track to RelayBar."
                        : "YouTube did not return usable captions for this video."
                    self.transcriptionState = .unavailable(reason: reason)
                    self.onStateChange?()
                    return
                }
                self.transcriptEntries = entries
                self.transcriptionState = .completed(entryCount: entries.count)
                self.onStateChange?()
                if let session = self.session {
                    YouTubeTranscriptPanel.show(videoTitle: session.cleanTitle, entries: entries,
                                               onSeek: { [weak self] time in self?.seek(to: time) },
                                               onOpenTranscript: { [weak self] in self?.openNativeTranscript() })
                }
            }
        }
    }
    
    public func openTranscriptPanel() {
        guard let s = session else { return }
        YouTubeTranscriptPanel.show(videoTitle: s.cleanTitle, entries: transcriptEntries,
                                   onSeek: { [weak self] time in self?.seek(to: time) },
                                   onOpenTranscript: { [weak self] in self?.openNativeTranscript() })
    }

    /// Best-effort: reveal YouTube's own transcript view in the playing tab.
    public func openNativeTranscript() {
        guard let s = session else { return }
        let tabID = s.tabID
        let bundle = s.bundle
        transcriptQueue.async { Self.openTranscriptPanelSync(bundle: bundle, tabID: tabID) }
    }
    
    public func captureMoment() -> String {
        guard let s = session else { return "" }
        let sec = Int(s.currentTime)
        let shareURL = "\(s.url)&t=\(sec)s"
        
        // Match current timestamp with closest transcript entry
        let excerpt = transcriptEntries.last(where: { $0.timestamp <= s.currentTime })?.text ?? "Moment captured at \(s.formattedTime)"
        
        let momentText = """
        ★ YouTube Moment • \(s.formattedTime)
        Video: \(s.cleanTitle)
        Link: \(shareURL)
        Quote: “\(excerpt)”
        """
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(momentText, forType: .string)
        return momentText
    }
    
    // MARK: - Touch Bar Slots Generator
    
    /// Layer 1: Global persistent mini-player slots. This survives losing focus
    /// in Chrome, another browser tab, or another app entirely, and the fixed
    /// order keeps play/pause and volume in the same physical position.
    /// `expanded` adds the small volume slider only when YouTube is foregrounded.
    func persistentSlots(expanded: Bool = false) -> [TouchBarDriver.Slot]? {
        guard let s = session else { return nil }
        
        let playTitle = s.isPlaying ? "❚❚" : "▶︎"
        let volTitle = s.isMuted ? "🔇" : "🔊 \(s.volume)%"
        let pillTitle = "YouTube • \(s.formattedTime) ↗"
        
        var slots: [TouchBarDriver.Slot] = [
            TouchBarDriver.Slot(
                key: "yt-mini-play",
                title: playTitle,
                help: s.isPlaying ? "Pause YouTube" : "Play YouTube",
                width: 38
            ) { [weak self] in
                self?.togglePlayPause()
            },
            TouchBarDriver.Slot(
                key: "yt-mini-vol",
                title: volTitle,
                help: s.isMuted ? "Tap to unmute. Drag the slider when YouTube is in front." : "Tap to mute. Drag the slider when YouTube is in front.",
                width: 48
            ) { [weak self] in
                self?.toggleMute()
            }
        ]
        if expanded {
            // Foregrounded on YouTube: the "jump back" pill would just point at
            // the page you are already on, so its width goes to the slider.
            slots.append(TouchBarDriver.Slot(
                key: "yt-mini-slider",
                title: "Volume",
                help: "Drag to set YouTube volume",
                width: 104,
                customView: VolumeSliderView(volume: s.volume, isMuted: s.isMuted) { [weak self] value in
                    self?.setVolume(value)
                },
                action: {}
            ))
        } else {
            slots.append(TouchBarDriver.Slot(
                key: "yt-mini-jump",
                title: pillTitle,
                help: "Jump directly to the playing YouTube tab (\(s.cleanTitle))",
                width: 98
            ) { [weak self] in
                self?.jumpToTab()
            })
        }
        return slots
    }
    
    /// Layer 2: Contextual controls when foregrounded on YouTube
    func contextSlots(onAsk: @escaping () -> Void) -> [TouchBarDriver.Slot] {
        guard let s = session else { return [] }
        
        let transcribeTitle: String
        let transcribeHelp: String
        switch transcriptionState {
        case .idle:
            transcribeTitle = "TRANSCRIBE"
            transcribeHelp = "Build a timestamped transcript from this video's real captions"
        case .transcribing(let time):
            transcribeTitle = "● \(time)"
            transcribeHelp = "Building a timestamped transcript…"
        case .completed(let count):
            transcribeTitle = "✓ TRANSCRIPT"
            transcribeHelp = "Open the synchronized transcript (\(count) lines). Tap a line to jump playback."
        case .unavailable(let reason):
            transcribeTitle = "TRANSCRIBE ↻"
            transcribeHelp = "Try again. \(reason)"
        }
        
        let chapterTitle = String(s.currentChapter.prefix(20))
        
        return [
            TouchBarDriver.Slot(
                key: "yt-ctx-rewind",
                title: "↶10",
                help: "Rewind 10 seconds (j)",
                width: 46
            ) { [weak self] in
                self?.rewind10()
            },
            TouchBarDriver.Slot(
                key: "yt-ctx-chapter",
                title: chapterTitle,
                help: "Current chapter: \(s.currentChapter)",
                width: 130
            ) { [weak self] in
                self?.openTranscriptPanel()
            },
            TouchBarDriver.Slot(
                key: "yt-ctx-moment",
                title: "★ MOMENT",
                help: "Capture this timestamp. With a transcript, the exact line at the playhead is quoted.",
                width: 82
            ) { [weak self] in
                _ = self?.captureMoment()
            },
            TouchBarDriver.Slot(
                key: "yt-ctx-transcribe",
                title: transcribeTitle,
                help: transcribeHelp,
                width: 96
            ) { [weak self] in
                guard let self = self else { return }
                if case .completed = self.transcriptionState {
                    self.openTranscriptPanel()
                } else {
                    self.startTranscription()
                }
            },
            TouchBarDriver.Slot(
                key: "yt-ctx-ask",
                title: "ASK",
                help: "Ask AI about this video segment with timestamp and quote",
                width: 46
            ) {
                onAsk()
            }
        ]
    }
    
    // MARK: - Synchronous AppleScript helpers
    
    private struct YouTubeMetrics {
        var isPlaying: Bool
        var currentTime: Double
        var duration: Double
        var volume: Int
        var isMuted: Bool
        var chapter: String
    }

    // MARK: - Real caption retrieval

    /// Reads the video's own caption-track URL from the page. This only touches
    /// YouTube's player metadata already loaded in the tab; no account data,
    /// cookies, or conversations are read or stored.
    nonisolated private static func queryCaptionTrackURLSync(tabID: Int, bundle: String) -> String? {
        let js = "(() => { const r = window.ytInitialPlayerResponse; const t = r && r.captions && r.captions.playerCaptionsTracklistRenderer && r.captions.playerCaptionsTracklistRenderer.captionTracks; if (!t || !t.length) return 'none'; const track = t.find(x => x.languageCode === 'en') || t[0]; return track.baseUrl || 'none'; })()"
        let script = """
        tell application id "\(bundle)"
            repeat with w in windows
                repeat with t in tabs of w
                    if (id of t as string) = "\(tabID)" or URL of t contains "youtube.com/watch" then
                        try
                            return (execute t javascript "\(js)")
                        on error
                            return "unsupported"
                        end try
                    end if
                end repeat
            end repeat
            return "not_found"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !out.isEmpty, out != "none", out != "unsupported", out != "not_found", out.hasPrefix("http") else {
            return nil
        }
        return out
    }

    nonisolated private static func fetchTranscriptSync(baseURL: String) -> [TranscriptEntry] {
        let separator = baseURL.contains("?") ? "&" : "?"
        guard let url = URL(string: baseURL + separator + "fmt=json3") else { return [] }
        let semaphore = DispatchSemaphore(value: 0)
        var payload: Data?
        let task = URLSession.shared.dataTask(with: url) { data, _, _ in
            payload = data
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 8) == .timedOut { task.cancel(); return [] }
        guard let data = payload,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else { return [] }
        var entries: [TranscriptEntry] = []
        for event in events {
            guard let startMs = event["tStartMs"] as? Double else { continue }
            let segments = event["segs"] as? [[String: Any]] ?? []
            let text = segments.compactMap { $0["utf8"] as? String }
                .joined()
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let seconds = startMs / 1000
            entries.append(TranscriptEntry(timestamp: seconds, timeString: timeString(seconds), text: text))
        }
        return entries
    }

    nonisolated private static func timeString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    nonisolated private static func openTranscriptPanelSync(bundle: String, tabID: Int) {
        let js = "(() => { const b = document.querySelector('ytd-video-description-transcript-section-renderer button') || document.querySelector('button[aria-label*=transcript i]'); if (b) { b.click(); return; } const more = document.querySelector('#expand'); if (more) more.click(); })()"
        let script = """
        tell application id "\(bundle)"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if (id of t as string) = "\(tabID)" or URL of t contains "youtube.com/watch" then
                        set active tab index of w to (index of t)
                        try
                            execute t javascript "\(js)"
                        end try
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }

    nonisolated private static func setVolumeSync(bundle: String, tabID: Int, volume: Int) {
        let js = "const v = document.querySelector('video'); if (v) { v.muted = \(volume) === 0; if (\(volume) > 0) v.volume = \(volume) / 100; }"
        let script = """
        tell application id "\(bundle)"
            repeat with w in windows
                repeat with t in tabs of w
                    if (id of t as string) = "\(tabID)" or URL of t contains "youtube.com/watch" then
                        try
                            execute t javascript "\(js)"
                        end try
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }
    
    nonisolated private static func queryYouTubeMetricsSync(tabID: Int, bundle: String) -> YouTubeMetrics? {
        let script = """
        tell application id "\(bundle)"
            repeat with w in windows
                repeat with t in tabs of w
                    if (id of t as string) = "\(tabID)" or URL of t contains "youtube.com/watch" then
                        try
                            set res to (execute t javascript "(() => {
                                const v = document.querySelector('video');
                                if (!v) return 'none';
                                const ch = document.querySelector('.ytp-chapter-title-content')?.textContent || '';
                                return [!v.paused, Math.floor(v.currentTime), Math.floor(v.duration), Math.floor(v.volume * 100), v.muted, ch].join('|');
                            })()")
                            return res
                        on error
                            return "unsupported"
                        end try
                    end if
                end repeat
            end repeat
            return "not_found"
        end tell
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !out.isEmpty, !out.contains("unsupported"), !out.contains("not_found") else {
            return nil
        }
        
        let parts = out.components(separatedBy: "|")
        guard parts.count >= 5 else { return nil }
        
        let playing = parts[0] == "true"
        let cur = Double(parts[1]) ?? 0
        let dur = Double(parts[2]) ?? 300
        let vol = Int(parts[3]) ?? 100
        let muted = parts[4] == "true"
        let chapter = parts.count > 5 && !parts[5].isEmpty ? parts[5] : "Architecture ▸ Agent Loop"
        
        return YouTubeMetrics(isPlaying: playing, currentTime: cur, duration: dur, volume: vol, isMuted: muted, chapter: chapter)
    }
    
    nonisolated private static func runControlCommandSync(bundle: String, tabID: Int, action: String) {
        // First try JS execution; if disabled, simulate key in active Chrome window
        let jsSnippet: String
        let keyChar: String
        
        switch action {
        case "play_pause":
            jsSnippet = "const v = document.querySelector('video'); if (v) { v.paused ? v.play() : v.pause(); }"
            keyChar = "k"
        case "mute":
            jsSnippet = "const v = document.querySelector('video'); if (v) v.muted = !v.muted;"
            keyChar = "m"
        case "rewind10":
            jsSnippet = "const v = document.querySelector('video'); if (v) v.currentTime = Math.max(0, v.currentTime - 10);"
            keyChar = "j"
        case "forward10":
            jsSnippet = "const v = document.querySelector('video'); if (v) v.currentTime = Math.min(v.duration, v.currentTime + 10);"
            keyChar = "l"
        default:
            return
        }
        
        let script = """
        tell application id "\(bundle)"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if (id of t as string) = "\(tabID)" or URL of t contains "youtube.com/watch" then
                        try
                            execute t javascript "\(jsSnippet)"
                            return
                        on error
                            -- Fallback to activating tab and sending keystroke
                            set active tab index of w to (index of t)
                            tell application "System Events" to keystroke "\(keyChar)"
                            return
                        end try
                    end if
                end repeat
            end repeat
        end tell
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }
    
    nonisolated private static func seekToSync(bundle: String, tabID: Int, seconds: Double) {
        let script = """
        tell application id "\(bundle)"
            repeat with w in windows
                repeat with t in tabs of w
                    if (id of t as string) = "\(tabID)" or URL of t contains "youtube.com/watch" then
                        try
                            execute t javascript "const v = document.querySelector('video'); if (v) v.currentTime = \(seconds);"
                        end try
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }
    
    nonisolated private static func activateYouTubeTabSync(bundle: String, tabID: Int) {
        let script = """
        tell application id "\(bundle)"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if (id of t as string) = "\(tabID)" or URL of t contains "youtube.com/watch" then
                        set active tab index of w to (index of t)
                        set index of w to 1
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }
}

import Cocoa
import Foundation

public enum YouTubeTranscriptionState: Equatable {
    case idle
    case loadingTrackList
    case transcribing(progress: String)
    case completed(entryCount: Int, fromCache: Bool)
    case unavailable(reason: String)

    public var isBusy: Bool {
        switch self {
        case .loadingTrackList, .transcribing: return true
        default: return false
        }
    }

    public var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}

/// The Touch Bar and panel front end for a playing YouTube video.
///
/// This class is deliberately thin. Every decision about *what is true* (states,
/// tab choice, chapters, transcript search, retention, cadence, the clock) lives
/// in `Sources/Core/YouTube.swift` and is unit tested there. What happens here is
/// only transport and presentation:
///
/// * playback is read from the tab fetch that already runs, so a tick costs one
///   AppleScript round trip instead of two;
/// * AppleScript runs in-process via `NSAppleScript`, with the `osascript`
///   process only as a fallback, so no process is spawned per tick or per tap;
/// * commands are coalesced latest-wins, so dragging the volume slider cannot
///   queue a process per tick;
/// * when Chrome refuses scripted control the bar says so and asks to be set up,
///   and it never invents a playhead, duration, volume or chapter.
@MainActor
public final class YouTubeController {
    public static let shared = YouTubeController()

    // MARK: - Observable state

    public private(set) var session: YouTubeSession?
    public private(set) var availability: YouTubeControlAvailability = .noSession
    public private(set) var transcriptionState: YouTubeTranscriptionState = .idle
    public private(set) var transcriptEntries: [TranscriptEntry] = []
    public private(set) var chapters = YouTubeChapterIndex()
    public private(set) var tracks = TranscriptTrackList()
    public private(set) var moments: [YouTubeMoment] = []
    public private(set) var trackProvenance: String = ""
    public private(set) var playbackRate: Double = 1
    /// Set while the machine is asleep, so cadence stops probing.
    public private(set) var screenAwake = true

    // MARK: - Callbacks

    /// Structure changed: the bar must be rebuilt.
    public var onStateChange: (() -> Void)?
    /// Only the clock/volume labels changed: update them in place instead of
    /// rebuilding the whole bar every poll.
    public var onProgressChange: (() -> Void)?
    /// A Moment was saved. `text` is the exact block that was copied.
    public var onMoment: ((YouTubeMoment, String) -> Void)?
    /// A plain message for the status line.
    public var onStatus: ((String) -> Void)?

    // MARK: - Session snapshot

    /// A real observation. Optional fields stay optional: an unreadable page is
    /// represented, not filled in with a default.
    public struct YouTubeSession: Equatable {
        public var tabID: Int
        public var bundle: String
        public var title: String
        public var url: String
        public var videoID: String
        public var state: YouTubePlaybackState
        public var currentTime: Double?
        public var duration: Double?
        public var volume: Int?
        public var isMuted: Bool?
        public var chapterTitle: String?
        public var sampledAt: Date
        public var availability: YouTubeControlAvailability

        public var cleanTitle: String {
            var text = title
            for suffix in [" - YouTube", " - Google Chrome", " — YouTube"] {
                if let range = text.range(of: suffix, options: .backwards) { text.removeSubrange(range) }
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "YouTube video" : trimmed
        }

        public var formattedTime: String { YouTubeTimecode.format(currentTime) }
    }

    // MARK: - Private state

    private let commandQueue = DispatchQueue(label: "local.relaybar.youtube.commands", qos: .userInitiated)
    private let transcriptQueue = DispatchQueue(label: "local.relaybar.youtube.transcript", qos: .userInitiated)

    private var store: YouTubeTranscriptStore?
    private var clock: YouTubeSessionClock?
    private var lastVideoID: YouTubeVideoID?
    private var lastProbeAttempt: Date = .distantPast
    private var settleUntil: Date = .distantPast
    private var pendingCommand: Command?
    private var commandInFlight = false
    private var storedRecord: YouTubeTranscriptRecord?
    private var sleepObservers: [NSObjectProtocol] = []

    private enum Command: Equatable {
        case playPause
        case mute
        case volume(Int)
        case rewind(Double)
        case forward(Double)
        case seek(Double)
        case rate(Double)
    }

    public init() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.screenAwake = false }
        })
        sleepObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.screenAwake = true; self?.lastProbeAttempt = .distantPast }
        })
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in sleepObservers { center.removeObserver(observer) }
    }

    public func attach(store: YouTubeTranscriptStore?) {
        self.store = store
    }

    // MARK: - Derived presentation values

    public var isActive: Bool { session != nil }

    /// The extrapolated playhead, or nil when no real sample has ever been read.
    public var liveTime: Double? { clock?.displayTime() }

    /// `—` until a real sample exists. This is the single guard that keeps a
    /// blocked probe from showing a believable clock.
    public var liveTimecode: String { clock?.displayTimecode() ?? "—" }

    public var liveDuration: Double? { session?.duration }

    public var progressFraction: Double? {
        guard let time = liveTime, let duration = liveDuration, duration > 0 else { return nil }
        return min(1, max(0, time / duration))
    }

    /// The chapter at the playhead, preferring the real chapter list over the
    /// label the page happened to expose.
    public var currentChapterTitle: String? {
        guard let time = liveTime else { return session?.chapterTitle }
        return chapters.label(at: time) ?? session?.chapterTitle
    }

    public var chapterCount: Int { chapters.count }

    public var hasTranscript: Bool { !transcriptEntries.isEmpty }

    /// Where the *stored* record says this video was left. Reported as a fact
    /// about the file ("last watched"), never written into the live clock: a
    /// stored position from an earlier session is not a reading of the page, and
    /// showing it as the current playhead would be exactly the kind of
    /// confident-but-stale value this layer refuses to display.
    public private(set) var storedPosition: Double?

    public var transcriptProvenance: String {
        trackProvenance.isEmpty ? (storedRecord?.provenance ?? "") : trackProvenance
    }

    public var recentMoments: [YouTubeMoment] {
        Array(moments.sorted { $0.timestamp > $1.timestamp }.prefix(YouTubePolicy.maximumMomentsPerVideo))
    }

    public var setupStatus: String { availability.status }

    /// Titles that change on every tick, keyed by slot. The app applies these in
    /// place instead of rebuilding the bar, so a playing video costs no new
    /// Touch Bar items and the tab strip keeps its scroll position.
    public var progressTitles: [String: String] {
        guard let session = session else { return [:] }
        return [
            "yt-mini-clock": liveTimecode,
            "yt-mini-jump": "YouTube • \(liveTimecode) ↗",
            "yt-mini-vol": volumeLabel(for: session)
        ]
    }

    private func volumeLabel(for session: YouTubeSession) -> String {
        if session.isMuted == true { return "🔇" }
        if let volume = session.volume { return "🔊 \(volume)%" }
        return "🔊 —"
    }

    // MARK: - Probing

    /// Consumed by the app before it asks the browser for tabs. Returns true when
    /// a probe is due, so a paused video is not re-read on every tick and the
    /// script can omit the probe block entirely.
    public func takeProbeSlot(at date: Date = Date()) -> Bool {
        guard screenAwake else { return false }
        let interval: TimeInterval
        if let session = session {
            interval = YouTubeCadence.interval(foreground: true,
                                               state: session.state,
                                               hasSession: true,
                                               screenAwake: screenAwake) ?? 1.0
        } else {
            // Looking for the first watch page: brisk, but not free.
            interval = 0.5
        }
        guard date.timeIntervalSince(lastProbeAttempt) >= interval else { return false }
        lastProbeAttempt = date
        return true
    }

    /// Adopts one round trip's worth of results: the browser tab list plus the
    /// playback payload that arrived on the same fetch.
    public func consume(tabs: [BrowserTab], bundle: String, probe: String, at date: Date = Date()) {
        // A command we just sent locally must win until the page catches up.
        let settling = date < settleUntil
        let result = YouTubeProbe.parse(payload: probe)

        switch result {
        case .noVideo:
            clearSession(reason: nil)
            return
        case .scriptingDisabled:
            adoptBlocked(tabs: tabs, bundle: bundle)
            return
        case .malformed(let reason):
            availability = .scriptingDisabled
            onStatus?("YouTube answered with \(reason) RelayBar will not guess at playback state.")
            return
        case .metrics(let metrics):
            // The probe names the video it read, so prefer that tab when several
            // YouTube tabs are open.
            let picked = YouTubeTabSelector.pick(tabs: tabs, lastVideoID: metrics.videoID ?? lastVideoID)
            if picked == nil && session == nil {
                // A playback payload arrived but nothing in the tab list is a
                // watch page. With no session to preserve there is nothing to
                // show, so say so instead of displaying a bar for no video.
                clearSession(reason: nil)
                return
            }
            // `picked` may legitimately be nil while a session is live: the
            // probe reads across every window, while the tab list only covers
            // the front one. Command routing is by tab identifier and searches
            // every window, so the existing session is kept, not dropped.
            adopt(metrics: metrics, tab: picked, bundle: bundle, at: date, settling: settling)
        }
    }

    /// Cheap liveness check for while the browser is not frontmost and therefore
    /// is not being polled at all. No AppleScript is involved: if the browser
    /// that owns the session has quit, the session is over and the pinned
    /// mini-player must not keep showing a frozen clock.
    public func validateSessionLiveness() {
        guard let session = session else { return }
        let running = NSWorkspace.shared.runningApplications.contains {
            ($0.bundleIdentifier ?? "") == session.bundle && !$0.isTerminated
        }
        if !running { clearSession(reason: nil) }
    }

    private func adoptBlocked(tabs: [BrowserTab], bundle: String) {
        availability = .scriptingDisabled
        let tab = YouTubeTabSelector.pick(tabs: tabs, lastVideoID: lastVideoID)
        if let tab = tab {
            let videoID = YouTubeVideoID.parse(url: tab.url)
            // A watch page exists but cannot be read. Keep the session so the bar
            // can offer setup, and keep a previously sampled clock — it is real
            // data, just stale — but never invent a new one.
            if session == nil || session?.tabID != tab.id || session?.videoID != (videoID?.raw ?? "") {
                session = YouTubeSession(
                    tabID: tab.id,
                    bundle: bundle,
                    title: tab.title,
                    url: tab.url,
                    videoID: videoID?.raw ?? "",
                    state: .unavailable,
                    currentTime: nil,
                    duration: nil,
                    volume: nil,
                    isMuted: nil,
                    chapterTitle: nil,
                    sampledAt: Date(),
                    availability: .scriptingDisabled
                )
                clock = YouTubeSessionClock(time: nil, state: .unavailable, duration: nil)
                lastVideoID = videoID
                resetTranscriptState()
                loadStoredRecord(for: videoID?.raw ?? "")
            } else {
                session?.state = .unavailable
                session?.availability = .scriptingDisabled
                session?.sampledAt = Date()
            }
        } else if session == nil {
            availability = .noSession
        }
        onStateChange?()
    }

    private func adopt(metrics: YouTubePlaybackMetrics, tab: BrowserTab?, bundle: String, at date: Date, settling: Bool) {
        availability = .ready
        let existing = session
        let videoID = metrics.videoID
            ?? tab.flatMap { YouTubeVideoID.parse(url: $0.url) }
            ?? existing.flatMap { YouTubeVideoID(raw: $0.videoID) }
        let videoChanged = videoID?.raw != lastVideoID?.raw
        if videoChanged {
            persistLastPosition()
            resetTranscriptState()
            lastVideoID = videoID
            loadStoredRecord(for: videoID?.raw ?? "")
            chapters = YouTubeChapterIndex()
            playbackRate = 1
        }

        // Latest-wins local command: while settling, the page has not caught up
        // yet, so only non-playback fields are adopted.
        let state = settling ? (session?.state ?? metrics.state) : metrics.state
        let time = settling ? (session?.currentTime ?? metrics.currentTime) : metrics.currentTime
        let duration = metrics.duration ?? session?.duration
        let volume = settling ? (session?.volume ?? metrics.volume) : metrics.volume
        let muted = settling ? (session?.isMuted ?? metrics.isMuted) : metrics.isMuted

        let next = YouTubeSession(
            tabID: tab?.id ?? existing?.tabID ?? 0,
            bundle: tab == nil ? (existing?.bundle ?? bundle) : bundle,
            title: tab?.title ?? existing?.title ?? "",
            url: tab?.url ?? existing?.url ?? "",
            videoID: videoID?.raw ?? "",
            state: state,
            currentTime: time,
            duration: duration,
            volume: volume,
            isMuted: muted,
            chapterTitle: metrics.chapter,
            sampledAt: date,
            availability: .ready
        )

        // Only genuine structural change may rebuild the bar. The clock and the
        // volume label change several times a second and are updated in place,
        // which is what keeps the tab strip's scroll position stable.
        let structureChanged = existing?.state != next.state
            || existing?.tabID != next.tabID
            || existing?.videoID != next.videoID
            || existing?.title != next.title
            || existing?.availability != next.availability
            || existing?.chapterTitle != next.chapterTitle
            || existing?.duration != next.duration
            || existing?.url != next.url

        session = next
        if settling {
            // Hold the optimistic anchor: a probe that was already in flight when
            // the user tapped must not snap the bar back.
            clock = clock ?? YouTubeSessionClock(time: time, state: state, duration: duration, at: date)
        } else {
            clock = (clock ?? YouTubeSessionClock(time: time, state: state, duration: duration, at: date))
                .adopting(metrics, at: date)
        }

        if videoChanged {
            refreshChapterList()
        }
        if structureChanged || videoChanged {
            onStateChange?()
        } else {
            onProgressChange?()
        }
    }

    private func clearSession(reason: String?) {
        guard session != nil || availability != .noSession else { return }
        persistLastPosition()
        session = nil
        clock = nil
        availability = .noSession
        lastVideoID = nil
        resetTranscriptState()
        if let reason = reason { onStatus?(reason) }
        onStateChange?()
    }

    private func resetTranscriptState() {
        transcriptionState = .idle
        transcriptEntries = []
        tracks = TranscriptTrackList()
        trackProvenance = ""
        storedRecord = nil
        storedPosition = nil
        moments = []
    }

    /// The session is genuinely gone (tab closed, or the browser is no longer
    /// supported). Called by the app on app switches.
    public func endSession(reason: String? = nil) {
        clearSession(reason: reason)
    }

    // MARK: - Playback controls

    public func togglePlayPause() {
        guard let session = session else { return }
        guard session.availability == .ready else { requireSetup(); return }
        let next: YouTubePlaybackState
        switch session.state {
        case .playing, .live: next = .paused
        case .paused, .unknown, .ended, .ad: next = .playing
        case .unavailable: next = .playing
        }
        self.session?.state = next
        settleUntil = Date().addingTimeInterval(YouTubeSessionClockPolicy.settleWindow)
        clock = YouTubeSessionClock(time: self.session?.currentTime, state: next, duration: session.duration)
        enqueue(.playPause)
        onStateChange?()
    }

    public func toggleMute() {
        guard let session = session else { return }
        guard session.availability == .ready else { requireSetup(); return }
        let muted = !(session.isMuted ?? false)
        self.session?.isMuted = muted
        self.session?.volume = muted ? 0 : (session.volume ?? 50)
        settleUntil = Date().addingTimeInterval(YouTubeSessionClockPolicy.settleWindow)
        enqueue(.mute)
        onStateChange?()
    }

    public func setVolume(_ value: Int) {
        guard let session = session else { return }
        guard session.availability == .ready else { requireSetup(); return }
        let clamped = min(100, max(0, value))
        self.session?.volume = clamped
        self.session?.isMuted = clamped == 0
        settleUntil = Date().addingTimeInterval(YouTubeSessionClockPolicy.settleWindow)
        // Continuous slider drags collapse into one in-flight call carrying the
        // newest value.
        enqueue(.volume(clamped))
        onProgressChange?()
    }

    public func rewind10() { seek(by: -10) }
    public func forward10() { seek(by: 10) }

    private func seek(by delta: Double) {
        guard let session = session, let time = liveTime ?? session.currentTime else { return }
        guard session.availability == .ready else { requireSetup(); return }
        let upper = session.duration ?? .greatestFiniteMagnitude
        let target = min(max(0, time + delta), upper)
        applyLocalSeek(target)
        enqueue(.seek(target))
    }

    public func seek(to seconds: Double) {
        guard let session = session, session.availability == .ready else { return }
        let upper = session.duration ?? .greatestFiniteMagnitude
        let target = min(max(0, seconds), upper)
        applyLocalSeek(target)
        enqueue(.seek(target))
    }

    private func applyLocalSeek(_ target: Double) {
        session?.currentTime = target
        clock = YouTubeSessionClock(time: target, state: session?.state ?? .paused, duration: session?.duration)
        settleUntil = Date().addingTimeInterval(YouTubeSessionClockPolicy.settleWindow)
        onProgressChange?()
    }

    public func cyclePlaybackRate() {
        guard let session = session, session.availability == .ready else { requireSetup(); return }
        let rates: [Double] = [1, 1.25, 1.5, 2]
        let index = rates.firstIndex(where: { abs($0 - playbackRate) < 0.01 }) ?? 0
        let next = rates[(index + 1) % rates.count]
        playbackRate = next
        enqueue(.rate(next))
        onStatus?("YouTube speed set to \(String(format: "%g", next))×.")
        onStateChange?()
    }

    public func nextChapter() { jumpChapter(forward: true) }
    public func previousChapter() { jumpChapter(forward: false) }

    private func jumpChapter(forward: Bool) {
        guard let session = session else { return }
        guard session.availability == .ready else { requireSetup(); return }
        guard let time = liveTime ?? session.currentTime else { return }
        let target = forward ? chapters.next(after: time) : chapters.previous(before: time)
        guard let chapter = target else {
            onStatus?(chapters.isEmpty ? "This video does not expose chapters." : "No further chapter in that direction.")
            return
        }
        seek(to: chapter.start)
        onStatus?("Jumped to \(chapter.title).")
    }

    public func jumpToTab() {
        guard let session = session else { return }
        let bundle = session.bundle
        let tabID = session.tabID
        commandQueue.async {
            _ = Self.run(js: "", bundle: bundle, tabID: tabID, activate: true)
        }
    }

    private func requireSetup() {
        availability = .scriptingDisabled
        onStatus?(YouTubeControlAvailability.scriptingDisabled.status)
        onStateChange?()
    }

    /// Explicit user retry after enabling the Chrome flag.
    public func retryControl() {
        lastProbeAttempt = .distantPast
        settleUntil = .distantPast
        onStatus?("Retrying YouTube control…")
        onStateChange?()
    }

    // MARK: - Command coalescing

    private func enqueue(_ command: Command) {
        pendingCommand = command
        pumpCommands()
    }

    private func pumpCommands() {
        guard !commandInFlight, let command = pendingCommand, let session = session else { return }
        pendingCommand = nil
        commandInFlight = true
        let bundle = session.bundle
        let tabID = session.tabID
        commandQueue.async { [weak self] in
            let output = Self.run(js: Self.javaScript(for: command), bundle: bundle, tabID: tabID)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.commandInFlight = false
                if output == nil {
                    self.onStatus?("Chrome refused that command. Enable scripted control in Chrome → View → Developer, then tap Retry.")
                    self.availability = .scriptingDisabled
                    self.onStateChange?()
                }
                self.pumpCommands()
            }
        }
    }

    private static func javaScript(for command: Command) -> String {
        switch command {
        case .playPause:
            return "(function(){var v=document.querySelector('video');if(!v)return 'rby-no-video';if(v.paused){v.play();}else{v.pause();}return 'ok';})()"
        case .mute:
            return "(function(){var v=document.querySelector('video');if(!v)return 'rby-no-video';v.muted=!v.muted;return 'ok';})()"
        case .volume(let value):
            return "(function(){var v=document.querySelector('video');if(!v)return 'rby-no-video';var n=\(max(0, min(100, value)));v.muted=n===0;if(n>0){v.volume=n/100;}return 'ok';})()"
        case .rewind(let seconds):
            return "(function(){var v=document.querySelector('video');if(!v)return 'rby-no-video';v.currentTime=Math.max(0,v.currentTime-\(abs(seconds)));return 'ok';})()"
        case .forward(let seconds):
            return "(function(){var v=document.querySelector('video');if(!v)return 'rby-no-video';v.currentTime=Math.min(v.duration||1e9,v.currentTime+\(abs(seconds)));return 'ok';})()"
        case .seek(let seconds):
            return "(function(){var v=document.querySelector('video');if(!v)return 'rby-no-video';var t=\(max(0, seconds));v.currentTime=t;return 'ok';})()"
        case .rate(let rate):
            return "(function(){var v=document.querySelector('video');if(!v)return 'rby-no-video';v.playbackRate=\(rate);return String(v.playbackRate);})()"
        }
    }

    // MARK: - Chapters

    /// One extra round trip per *video*, never per tick.
    private func refreshChapterList() {
        guard let session = session, session.availability == .ready else { return }
        let bundle = session.bundle
        let tabID = session.tabID
        transcriptQueue.async { [weak self] in
            let output = Self.run(js: Self.chapterListJavaScript, bundle: bundle, tabID: tabID)
            DispatchQueue.main.async {
                guard let self = self, let output = output, !output.contains("rby-no-chapters") else { return }
                let index = YouTubeChapterIndex(payload: output)
                guard !index.isEmpty else { return }
                self.chapters = index
                self.onStateChange?()
            }
        }
    }

    // MARK: - Transcription

    /// Uses the video's own caption track. When a transcript is already stored
    /// locally it is loaded immediately and nothing is fetched.
    public func startTranscription() {
        guard let session = session else { return }
        guard session.availability == .ready else { requireSetup(); return }

        if let stored = storedRecord, !stored.entries.isEmpty {
            adoptStored(stored, fromCache: true)
            return
        }
        guard !transcriptionState.isBusy else { return }
        transcriptionState = .loadingTrackList
        onStateChange?()

        let bundle = session.bundle
        let tabID = session.tabID
        transcriptQueue.async { [weak self] in
            let trackOutput = Self.run(js: Self.trackListJavaScript, bundle: bundle, tabID: tabID)
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let output = trackOutput, !output.contains("rby-no-tracks") else {
                    self.transcriptionState = .unavailable(reason: "This video does not expose a caption track to RelayBar.")
                    self.onStateChange?()
                    return
                }
                let tracks = TranscriptTrackList(payload: output)
                guard let track = tracks.preferred(preferring: nil) else {
                    self.transcriptionState = .unavailable(reason: "This video lists caption tracks, but none of them is usable.")
                    self.onStateChange?()
                    return
                }
                self.tracks = tracks
                self.transcriptionState = .transcribing(progress: "Reading \(track.name)")
                self.onStateChange?()
                self.fetchCaptionTrack(track, videoTitle: session.cleanTitle, videoID: session.videoID)
            }
        }
    }

    /// Fetch one of the video's other caption tracks.
    public func loadTrack(languageCode: String) {
        guard let track = tracks.track(languageCode: languageCode), let session = session else { return }
        transcriptionState = .transcribing(progress: "Reading \(track.name)")
        onStateChange?()
        fetchCaptionTrack(track, videoTitle: session.cleanTitle, videoID: session.videoID)
    }

    private func fetchCaptionTrack(_ track: TranscriptTrack, videoTitle: String, videoID: String) {
        let separator = track.url.contains("?") ? "&" : "?"
        guard let url = URL(string: track.url + separator + "fmt=json3"),
              url.scheme?.lowercased() == "https" else {
            transcriptionState = .unavailable(reason: "This caption track does not use an https URL, so RelayBar refused to fetch it.")
            onStateChange?()
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("RelayBar/local-transcript", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let entries: [TranscriptEntry]
            if let data = data {
                entries = TranscriptIndex.parseJSON3(data)
            } else {
                entries = []
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard !entries.isEmpty else {
                    let reason: String
                    if let error = error {
                        reason = "The caption track could not be read: \(error.localizedDescription)"
                    } else if status >= 400 {
                        reason = "YouTube refused the caption request (HTTP \(status))."
                    } else {
                        reason = "YouTube returned no usable captions for this video."
                    }
                    self.transcriptionState = .unavailable(reason: reason)
                    self.onStateChange?()
                    return
                }
                let record = YouTubeTranscriptRecord(
                    videoID: videoID,
                    title: videoTitle,
                    trackLanguage: track.languageCode,
                    trackIsAutoGenerated: track.isAutoGenerated,
                    fetchedAt: Date(),
                    entries: entries,
                    moments: self.storedRecord?.moments ?? [],
                    lastPosition: self.liveTime
                )
                self.adopt(record, fromCache: false)
            }
        }.resume()
    }

    private func adoptStored(_ record: YouTubeTranscriptRecord, fromCache: Bool) {
        transcriptEntries = record.entries
        moments = record.recentMoments
        trackProvenance = record.provenance
        storedRecord = record
        // Kept as a labelled fact for the transcript panel. The live clock is
        // untouched: it only ever follows a real sample from this session.
        storedPosition = record.lastPosition
        transcriptionState = .completed(entryCount: record.entries.count, fromCache: fromCache)
        onStateChange?()
        onStatus?(fromCache
            ? "Loaded \(record.entries.count) stored transcript lines for “\(record.title)”, \(record.provenance)."
            : "Transcribed \(record.entries.count) lines from \(record.provenance).")
    }

    private func adopt(_ record: YouTubeTranscriptRecord, fromCache: Bool) {
        do {
            try record.validate()
            try store?.save(record)
        } catch {
            // A storage refusal must not hide a good transcript.
            onStatus?("The transcript is ready but could not be stored locally: \(error.localizedDescription)")
        }
        adoptStored(record, fromCache: fromCache)
    }

    private func loadStoredRecord(for videoID: String) {
        guard let store = store, !videoID.isEmpty,
              let record = try? store.load(videoID: videoID) else {
            storedRecord = nil
            return
        }
        storedRecord = record
        storedPosition = record.lastPosition
        moments = record.recentMoments
        trackProvenance = record.provenance
        if !record.entries.isEmpty {
            transcriptEntries = record.entries
            transcriptionState = .completed(entryCount: record.entries.count, fromCache: true)
        }
    }

    public func openTranscriptPanel() {
        guard let session = session else { return }
        let videoID = session.videoID
        let title = session.cleanTitle
        YouTubeTranscriptPanel.show(
            videoTitle: title,
            videoID: videoID,
            provenance: transcriptProvenance,
            chapters: chapters,
            entries: transcriptEntries,
            moments: recentMoments,
            lastPosition: storedPosition,
            currentTime: { [weak self] in self?.liveTime },
            onSeek: { [weak self] time in self?.seek(to: time) },
            onOpenTranscript: { [weak self] in self?.openNativeTranscript() },
            onForget: { [weak self] in self?.forgetCurrentTranscript(videoID: videoID) },
            onStar: { [weak self] in _ = self?.captureMoment() },
            onSearch: { [weak self] query in self?.searchTranscript(query) ?? [] }
        )
    }

    /// Real, local, offline search over the transcript lines.
    public func searchTranscript(_ query: String) -> [TranscriptMatch] {
        TranscriptIndex.search(query, in: transcriptEntries)
    }

    /// A bounded block of real caption lines around `time`, or nil when there is
    /// no transcript. Used for both the Moment quote and the Ask prompt, so a
    /// saved Moment and a question about the same instant quote the same lines.
    public func momentExcerpt(around time: Double?, window: Double = YouTubePolicy.excerptWindow) -> String? {
        guard let time = time else { return nil }
        let excerpt = TranscriptIndex.excerpt(around: time, window: window, in: transcriptEntries)
        return excerpt.isEmpty ? nil : excerpt
    }

    /// A single saved Moment, nearest the playhead, for the panel's "recent" row.
    public func moment(nearest time: Double?) -> YouTubeMoment? {
        guard let time = time else { return recentMoments.first }
        return moments.min { abs($0.timestamp - time) < abs($1.timestamp - time) }
    }

    public func openNativeTranscript() {
        guard let session = session else { return }
        let bundle = session.bundle
        let tabID = session.tabID
        transcriptQueue.async {
            _ = Self.run(js: Self.openTranscriptJavaScript, bundle: bundle, tabID: tabID, activate: true)
        }
    }

    // MARK: - Moments

    @discardableResult
    public func captureMoment() -> String {
        guard let session = session else { return "" }
        guard let time = liveTime ?? session.currentTime else {
            onStatus?(session.availability.setupRequired
                ? YouTubeControlAvailability.scriptingDisabled.status
                : "RelayBar has no real playhead for this video yet, so a Moment would be a guess. Tap Retry first.")
            return ""
        }
        let chapterTitle = currentChapterTitle
        let excerpt = TranscriptIndex.snapped(to: time, in: transcriptEntries)?.text
            ?? TranscriptIndex.excerpt(around: time, window: 20, in: transcriptEntries)
        let moment = YouTubeMoment(videoID: session.videoID,
                                   timestamp: time,
                                   excerpt: excerpt,
                                   chapter: chapterTitle)
        let text = moment.pastedText(title: session.cleanTitle)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        moments.append(moment)
        if moments.count > YouTubePolicy.maximumMomentsPerVideo {
            moments = Array(moments.sorted { $0.timestamp > $1.timestamp }.prefix(YouTubePolicy.maximumMomentsPerVideo))
        }
        persistMoment(moment)
        onMoment?(moment, text)
        onStatus?(excerpt.isEmpty
            ? "Moment saved at \(moment.timecode) and copied. No transcript yet, so the quote is empty."
            : "Moment saved at \(moment.timecode) with the exact line playing then.")
        onStateChange?()
        return text
    }

    private func persistMoment(_ moment: YouTubeMoment) {
        // A Moment for an unidentifiable video stays in memory rather than being
        // written under a guessed identifier.
        guard let store = store, let videoID = session?.videoID, !videoID.isEmpty,
              YouTubeVideoID(raw: videoID) != nil else { return }
        var record = storedRecord ?? YouTubeTranscriptRecord(
            videoID: videoID,
            title: session?.cleanTitle ?? "",
            trackLanguage: "",
            trackIsAutoGenerated: false,
            fetchedAt: Date(),
            entries: transcriptEntries,
            lastPosition: moment.timestamp
        )
        record.moments.append(moment)
        if record.moments.count > YouTubePolicy.maximumMomentsPerVideo {
            record.moments = Array(record.moments.sorted { $0.timestamp > $1.timestamp }.prefix(YouTubePolicy.maximumMomentsPerVideo))
        }
        record.lastPosition = moment.timestamp
        storedRecord = record
        try? store.save(record)
    }

    private func persistLastPosition() {
        guard let store = store, var record = storedRecord, let position = liveTime else { return }
        record.lastPosition = position
        storedRecord = record
        try? store.save(record)
    }

    public func forgetCurrentTranscript(videoID: String) {
        guard !videoID.isEmpty else { return }
        do {
            try store?.delete(videoID: videoID)
            resetTranscriptState()
            onStatus?("The stored transcript and Moments for this video were deleted. The video itself is unchanged.")
            onStateChange?()
        } catch {
            onStatus?("Could not delete that transcript: \(error.localizedDescription)")
        }
    }

    public func storedLibrary() -> YouTubeTranscriptLibrary {
        (try? store?.loadLibrary()) ?? YouTubeTranscriptLibrary()
    }

    public func clearStoredLibrary() {
        do {
            let removed = try store?.deleteAll() ?? 0
            resetTranscriptState()
            onStatus?("Deleted \(removed) stored transcript file\(removed == 1 ? "" : "s").")
            onStateChange?()
        } catch {
            onStatus?("Could not clear stored transcripts: \(error.localizedDescription)")
        }
    }

    // MARK: - Touch Bar slots

    /// Layer 1: the pinned mini-player. Tabs and apps can change around it; the
    /// order inside it never changes, so play/pause and volume stay put.
    func persistentSlots(expanded: Bool = false) -> [TouchBarDriver.Slot]? {
        guard let session = session else { return nil }

        if session.availability == .scriptingDisabled {
            var slots: [TouchBarDriver.Slot] = [
                TouchBarDriver.Slot(
                    key: "yt-mini-setup",
                    title: "⚠ Enable control",
                    help: YouTubeControlAvailability.scriptingDisabled.status,
                    width: 132
                ) { [weak self] in self?.retryControl() }
            ]
            if !expanded, !session.videoID.isEmpty {
                slots.append(jumpSlot(for: session))
            }
            return slots
        }

        let playTitle = session.state == .playing || session.state == .live ? "❚❚" : "▶︎"
        let volTitle = volumeLabel(for: session)

        var slots: [TouchBarDriver.Slot] = [
            TouchBarDriver.Slot(
                key: "yt-mini-play",
                title: playTitle,
                help: playHelp(for: session.state),
                width: 38
            ) { [weak self] in self?.togglePlayPause() },
            TouchBarDriver.Slot(
                key: "yt-mini-vol",
                title: volTitle,
                help: session.isMuted == true
                    ? "Tap to unmute. Drag the slider when YouTube is in front."
                    : "Tap to mute. Drag the slider when YouTube is in front.",
                width: 48
            ) { [weak self] in self?.toggleMute() }
        ]
        if expanded {
            slots.append(TouchBarDriver.Slot(
                key: "yt-mini-slider",
                title: "Volume",
                help: "Drag to set YouTube volume",
                width: 104,
                customView: VolumeSliderView(volume: session.volume ?? 0, isMuted: session.isMuted ?? false) { [weak self] value in
                    self?.setVolume(value)
                },
                action: {}
            ))
            // Still the pinned layer, so the elapsed time stays in the same
            // place whether or not the YouTube page is in front.
            slots.append(TouchBarDriver.Slot(
                key: "yt-mini-clock",
                title: liveTimecode,
                help: "\(session.cleanTitle)\n\(session.state.shortLabel)\(liveDuration.map { " of \(YouTubeTimecode.format($0))" } ?? "")",
                width: 58
            ) { [weak self] in self?.jumpToTab() })
        } else {
            slots.append(jumpSlot(for: session))
        }
        return slots
    }

    private func jumpSlot(for session: YouTubeSession) -> TouchBarDriver.Slot {
        TouchBarDriver.Slot(
            key: "yt-mini-jump",
            title: "YouTube • \(liveTimecode) ↗",
            help: "Jump to the playing tab: \(session.cleanTitle)",
            width: 108
        ) { [weak self] in self?.jumpToTab() }
    }

    private func playHelp(for state: YouTubePlaybackState) -> String {
        switch state {
        case .playing, .live: return "Pause YouTube"
        case .paused: return "Play YouTube"
        case .ended: return "Replay from here"
        case .ad: return "An ad is playing; play/pause is still sent to the video"
        case .unknown: return "Play or pause YouTube"
        case .unavailable: return "RelayBar cannot control this video yet"
        }
    }

    /// Layer 2: the controls that only make sense while YouTube is in front.
    func contextSlots(onSetup: @escaping () -> Void, onAsk: @escaping () -> Void) -> [TouchBarDriver.Slot] {
        guard let session = session else { return [] }

        if session.availability == .scriptingDisabled {
            return [
                TouchBarDriver.Slot(
                    key: "yt-ctx-setup",
                    title: "⚠ Enable YouTube control",
                    help: YouTubeControlAvailability.scriptingDisabled.status,
                    width: 178
                ) { onSetup() },
                TouchBarDriver.Slot(
                    key: "yt-ctx-retry",
                    title: "Retry",
                    help: "Re-check scripted control without changing any Chrome setting",
                    width: 54
                ) { [weak self] in self?.retryControl() }
            ]
        }

        let transcribeTitle: String
        let transcribeHelp: String
        switch transcriptionState {
        case .idle:
            transcribeTitle = hasTranscript ? "✓ TRANSCRIPT" : "TRANSCRIBE"
            transcribeHelp = hasTranscript
                ? "Open the transcript already stored for this video"
                : "Build a timestamped transcript from this video's own caption track"
        case .loadingTrackList:
            transcribeTitle = "● TRACKS…"
            transcribeHelp = "Reading this video's caption tracks"
        case .transcribing(let progress):
            transcribeTitle = "● TRANSCRIBING"
            transcribeHelp = progress
        case .completed(let count, let fromCache):
            transcribeTitle = "✓ TRANSCRIPT"
            transcribeHelp = "\(count) lines\(fromCache ? " (stored locally)" : ""). Tap a line to jump playback."
        case .unavailable(let reason):
            transcribeTitle = "TRANSCRIBE ↻"
            transcribeHelp = "Try again. \(reason)"
        }

        let chapterTitle = currentChapterTitle ?? (chapters.isEmpty ? "No chapters" : "Chapters")
        let chapterHelp: String
        if let chapter = chapters.chapter(at: liveTime ?? 0) {
            chapterHelp = "Chapter: \(chapter.title) · \(chapter.timecode). Tap to jump to the next chapter."
        } else if chapters.isEmpty {
            chapterHelp = "This video does not expose chapters."
        } else {
            chapterHelp = "\(chapters.count) chapters. Tap to jump to the next chapter."
        }

        return [
            TouchBarDriver.Slot(
                key: "yt-ctx-rewind",
                title: "↶10",
                help: "Rewind 10 seconds",
                width: 46
            ) { [weak self] in self?.rewind10() },
            TouchBarDriver.Slot(
                key: "yt-ctx-forward",
                title: "↷10",
                help: "Forward 10 seconds",
                width: 44
            ) { [weak self] in self?.forward10() },
            TouchBarDriver.Slot(
                key: "yt-ctx-chapter",
                title: String(chapterTitle.prefix(22)),
                help: chapterHelp,
                width: 132
            ) { [weak self] in self?.nextChapter() },
            TouchBarDriver.Slot(
                key: "yt-ctx-moment",
                title: "★ MOMENT",
                help: "Save this timestamp. With a transcript, the exact line playing now is quoted.",
                width: 82
            ) { [weak self] in _ = self?.captureMoment() },
            TouchBarDriver.Slot(
                key: "yt-ctx-transcribe",
                title: transcribeTitle,
                help: transcribeHelp,
                width: 100
            ) { [weak self] in
                guard let self = self else { return }
                if self.transcriptionState.isCompleted || self.hasTranscript {
                    self.openTranscriptPanel()
                } else {
                    self.startTranscription()
                }
            },
            TouchBarDriver.Slot(
                key: "yt-ctx-rate",
                title: String(format: "%g×", playbackRate),
                help: "Cycle playback speed: 1×, 1.25×, 1.5×, 2×",
                width: 44
            ) { [weak self] in self?.cyclePlaybackRate() },
            TouchBarDriver.Slot(
                key: "yt-ctx-ask",
                title: "ASK",
                help: "Ask AI about this exact moment, with the caption lines around it",
                width: 46
            ) { onAsk() }
        ]
    }

    // MARK: - JavaScript payloads

    private static let trackListJavaScript = "(function(){var r=window.ytInitialPlayerResponse;var l=r&&r.captions&&r.captions.playerCaptionsTracklistRenderer;var t=l&&l.captionTracks;if(!t||!t.length)return 'rby-no-tracks';var out=[];for(var i=0;i<t.length;i++){var c=t[i];var n='';if(c.name){n=c.name.simpleText||((c.name.runs&&c.name.runs[0]&&c.name.runs[0].text)||'');}out.push([c.languageCode||'',String(n).split('|').join(' '),c.baseUrl||''].join('|'));}return out.join(String.fromCharCode(10));})()"

    private static let chapterListJavaScript = "(function(){var r=window.ytInitialPlayerResponse;var o=r&&r.playerOverlays&&r.playerOverlays.playerOverlayRenderer;var d=o&&o.decoratedPlayerBarRenderer&&o.decoratedPlayerBarRenderer.decoratedPlayerBarRenderer;var b=d&&d.playerBar;var m=b&&b.multiMarkersPlayerBarRenderer&&b.multiMarkersPlayerBarRenderer.markersMap;var out=[];if(m){for(var k in m){var mm=m[k];var ch=mm&&mm.value&&mm.value.chapters;if(!ch)continue;for(var i=0;i<ch.length;i++){var cr=ch[i]&&ch[i].chapterRenderer;if(!cr)continue;var st=cr.timeRangeStartMillis||0;var t='';if(cr.title){t=cr.title.simpleText||((cr.title.runs&&cr.title.runs[0]&&cr.title.runs[0].text)||'');}out.push(Math.round(st/1000)+':'+String(t).split(':').join(' ').split('|').join(' '));}}}return out.length?out.join(String.fromCharCode(10)):'rby-no-chapters';})()"

    private static let openTranscriptJavaScript = "(function(){var b=document.querySelector('ytd-video-description-transcript-section-renderer button');if(b){b.click();return 'ok';}var alt=document.querySelector('button[aria-label*=transcript i]');if(alt){alt.click();return 'ok';}var more=document.querySelector('#expand');if(more){more.click();return 'ok';}return 'rby-no-transcript-ui';})()"

    // MARK: - AppleScript transport

    /// Runs one snippet against the session's tab. In-process `NSAppleScript`
    /// first — that is the difference between a ~2 ms call and a ~60 ms process
    /// spawn — with `/usr/bin/osascript` only as a fallback.
    nonisolated private static func run(js: String, bundle: String, tabID: Int, activate: Bool = false) -> String? {
        let source = script(js: js, bundle: bundle, tabID: tabID, activate: activate)
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let result = script.executeAndReturnError(&error)
            if error == nil {
                let value = result.stringValue ?? ""
                return value == "rby-error" ? nil : value
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = nil
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "rby-error" ? nil : trimmed
    }

    nonisolated private static func script(js: String, bundle: String, tabID: Int, activate: Bool) -> String {
        let activation = activate ? "set active tab index of w to (index of t)\n                        set index of w to 1\n                        " : ""
        let evaluation = js.isEmpty
            ? "return \"ok\""
            : """
            try
                                return (execute t javascript "\(js)")
                            on error
                                return "rby-error"
                            end try
            """
        return """
        tell application id "\(bundle)"
            repeat with w in windows
                repeat with t in tabs of w
                    if (id of t as string) = "\(tabID)" or URL of t contains "youtube.com/watch" then
                        \(activation)\(evaluation)
                    end if
                end repeat
            end repeat
            return "rby-no-video"
        end tell
        """
    }
}

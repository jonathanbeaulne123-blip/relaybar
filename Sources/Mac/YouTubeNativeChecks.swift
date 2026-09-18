import Cocoa

/// Native (Mac-only) checks for the YouTube layer. Run only from an explicit
/// command-line flag, never on launch.
///
/// Everything here is driven by *synthetic probe payloads*, so these checks are
/// fully offline: no AppleScript is sent, no Chrome tab is read or changed, the
/// user's clipboard is never touched (the one Moment path that would write it is
/// only exercised where the controller must refuse), and no transcript is
/// fetched over the network. Storage checks use a throwaway temporary directory.
@MainActor
enum YouTubeNativeChecks {
    static func run() -> Int32 {
        var passed = 0
        var failures: [String] = []
        func check(_ condition: Bool, _ name: String) {
            if condition { passed += 1; print("PASS: \(name)") }
            else { failures.append(name); print("FAIL: \(name)") }
        }
        func keys(_ slots: [TouchBarDriver.Slot]) -> [String] { slots.map(\.key) }

        // A bundle identifier that belongs to no application: even if a code path
        // tried to script the browser, nothing would be reached.
        let bundle = "local.relaybar.youtube-self-test"
        let videoID = "dQw4w9WgXcQ"
        let watchTab = BrowserTab(id: 77, index: 0, title: "Agent Loops, Explained",
                                  url: "https://www.youtube.com/watch?v=\(videoID)", isSelected: true)

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("relaybar-youtube-selftest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try? YouTubeTranscriptStore(directory: directory)

        let youTube = YouTubeController.shared
        youTube.onStateChange = nil
        youTube.onProgressChange = nil
        youTube.onStatus = nil
        youTube.attach(store: store)
        youTube.endSession()

        var stateChanges = 0
        var progressChanges = 0
        youTube.onStateChange = { stateChanges += 1 }
        youTube.onProgressChange = { progressChanges += 1 }

        // MARK: An idle RelayBar draws nothing at all

        check(youTube.session == nil, "no session before any probe")
        check(youTube.persistentSlots() == nil, "no mini-player without a video")
        check(youTube.persistentSlots(expanded: true) == nil, "no expanded mini-player without a video")
        check(youTube.contextSlots(onSetup: {}, onAsk: {}).isEmpty, "no YouTube context controls without a video")
        check(youTube.liveTime == nil, "no playhead before any real sample")
        check(youTube.liveTimecode == "—", "the clock shows an unknown time, not 0:00")
        check(youTube.progressTitles.isEmpty, "nothing to retitle without a session")
        check(youTube.availability == .noSession, "availability starts as no session")
        check(youTube.captureMoment().isEmpty, "a Moment without a session produces nothing")
        check(youTube.setupStatus == YouTubeControlAvailability.noSession.status,
              "the status line explains that no watch page is open")

        // MARK: Blocked control: explain, do not guess

        youTube.consume(tabs: [watchTab], bundle: bundle, probe: YouTubeProbe.unavailableToken)
        check(youTube.availability == .scriptingDisabled, "a refused probe is reported as needing setup")
        check(youTube.session != nil, "the watch page is still tracked while control is blocked")
        check(youTube.session?.state == .unavailable, "blocked control is its own state")

        let blockedMini = youTube.persistentSlots() ?? []
        check(keys(blockedMini).contains("yt-mini-setup"), "the pinned bar offers setup while blocked")
        check(!keys(blockedMini).contains("yt-mini-play"), "no play button is offered while blocked")
        check(!keys(blockedMini).contains("yt-mini-vol"), "no volume control is offered while blocked")
        check(keys(blockedMini).contains("yt-mini-jump"), "the jump-back pill survives while blocked")

        let blockedContext = youTube.contextSlots(onSetup: {}, onAsk: {})
        check(keys(blockedContext) == ["yt-ctx-setup", "yt-ctx-retry"], "context controls are setup and retry only")
        check(blockedContext.first?.help.contains("View → Developer") == true, "the setup slot names Chrome's own menu")
        check(youTube.liveTimecode == "—", "a blocked probe never produces a clock")
        check(youTube.captureMoment().isEmpty, "a Moment is refused while the playhead is unknown")

        // MARK: A real sample with unreadable fields stays honest

        youTube.consume(tabs: [watchTab], bundle: bundle,
                        probe: "rby1|paused|-|-|-|-|\(videoID)|-|-")
        check(youTube.availability == .ready, "a readable payload restores control")
        check(youTube.session?.state == .paused, "the reported state is adopted")
        check(youTube.liveTime == nil, "an unreadable playhead stays unknown")
        check(youTube.liveTimecode == "—", "the clock stays unknown even with a live session")
        check(youTube.liveDuration == nil, "an unreadable duration stays unknown")
        check(youTube.currentChapterTitle == nil, "no chapter is invented for a video that reports none")
        check(youTube.progressTitles["yt-mini-clock"] == "—", "the pinned clock is unknown, not fabricated")
        check(youTube.progressTitles["yt-mini-vol"] == "🔊 —", "an unknown volume is not shown as a percentage")

        // MARK: A full sample drives the two layers

        youTube.consume(tabs: [watchTab], bundle: bundle,
                        probe: "rby1|playing|744|3723|42|false|\(videoID)|Agent Loops, Explained|Tool Calls")
        check(youTube.session?.state == .playing, "playback state is adopted")
        check(youTube.liveTimecode == "12:24", "the clock reads the real playhead")
        check(youTube.progressTitles["yt-mini-clock"] == "12:24", "the pinned clock carries the real time")
        check(youTube.progressTitles["yt-mini-vol"] == "🔊 42%", "the pinned volume carries the real volume")
        check(youTube.progressTitles["yt-mini-jump"] == "YouTube • 12:24 ↗", "the jump pill carries the real time")
        check(youTube.liveDuration == 3723, "the real duration is exposed for the help text")
        check(abs((youTube.progressFraction ?? 0) - 744.0 / 3723.0) < 0.01, "progress uses the real playhead and length")
        check(youTube.currentChapterTitle == "Tool Calls", "the page's own chapter label is used when no list exists")

        let mini = youTube.persistentSlots() ?? []
        check(keys(mini) == ["yt-mini-play", "yt-mini-vol", "yt-mini-jump"], "the pinned layer keeps its exact order")
        check(mini.first?.title == "❚❚", "play/pause reflects that the video is playing")

        let expanded = youTube.persistentSlots(expanded: true) ?? []
        check(keys(expanded) == ["yt-mini-play", "yt-mini-vol", "yt-mini-slider", "yt-mini-clock"],
              "with YouTube in front the jump pill yields to the slider and the clock")
        check(expanded.contains { $0.key == "yt-mini-slider" && $0.customView is VolumeSliderView },
              "the volume slider is a real control, not a label")
        check(expanded.first?.title == mini.first?.title,
              "play/pause sits in the same physical position in both layers")

        let context = youTube.contextSlots(onSetup: {}, onAsk: {})
        check(keys(context) == ["yt-ctx-rewind", "yt-ctx-forward", "yt-ctx-chapter", "yt-ctx-moment",
                                "yt-ctx-transcribe", "yt-ctx-rate", "yt-ctx-ask"],
              "the foreground layer is the YouTube control set")
        check(context.first { $0.key == "yt-ctx-transcribe" }?.title == "TRANSCRIBE",
              "transcribe offers to build a transcript when none exists")

        let slider = VolumeSliderView(volume: 42, isMuted: false) { _ in }
        check(slider.subviews.count == 1 && slider.subviews.first is NSSlider,
              "the volume slider constructs a real NSSlider")
        check(slider.subviews.first?.accessibilityLabel() == "YouTube volume",
              "the volume slider is labelled for accessibility")

        // MARK: A clock tick must not rebuild the bar

        stateChanges = 0
        progressChanges = 0
        youTube.consume(tabs: [watchTab], bundle: bundle,
                        probe: "rby1|playing|760|3723|43|false|\(videoID)|Agent Loops, Explained|Tool Calls")
        check(progressChanges == 1, "a moving playhead is reported as progress")
        check(stateChanges == 0, "a moving playhead does not announce a structural change")
        check(youTube.progressTitles["yt-mini-clock"] == "12:40", "the clock follows the new sample")

        let driver = TouchBarDriver()
        driver.update(youTube.persistentSlots() ?? [])
        let identifiers = driver.bar.defaultItemIdentifiers
        let titlesBefore = driver.currentTitles
        driver.retitle(youTube.progressTitles)
        check(driver.bar.defaultItemIdentifiers == identifiers, "retitling rebuilds no Touch Bar items")
        check(driver.currentTitles["yt-mini-play"] == titlesBefore["yt-mini-play"],
              "retitling leaves controls that did not change alone")
        // Out of focus the clock lives in the jump pill; in focus it has its own slot.
        check(driver.currentTitles["yt-mini-jump"] == "YouTube • 12:40 ↗",
              "retitling updates the pinned pill's clock in place")
        check(driver.currentTitles["yt-mini-vol"] == "🔊 43%",
              "retitling updates the pinned volume in place")

        let expandedDriver = TouchBarDriver()
        expandedDriver.update(youTube.persistentSlots(expanded: true) ?? [])
        let expandedIdentifiers = expandedDriver.bar.defaultItemIdentifiers
        expandedDriver.retitle(youTube.progressTitles)
        check(expandedDriver.currentTitles["yt-mini-clock"] == "12:40",
              "retitling updates the in-focus clock in place")
        check(expandedDriver.bar.defaultItemIdentifiers == expandedIdentifiers,
              "retitling the in-focus bar rebuilds no Touch Bar items")

        // MARK: Mute is reported, not inferred

        youTube.consume(tabs: [watchTab], bundle: bundle,
                        probe: "rby1|playing|760|3723|0|true|\(videoID)|Agent Loops, Explained|Tool Calls")
        check(youTube.progressTitles["yt-mini-vol"] == "🔇", "a muted video shows a muted label")

        // MARK: A stored transcript is reused, quoted, and removable

        var record = YouTubeTranscriptRecord(
            videoID: videoID,
            title: "Agent Loops, Explained",
            trackLanguage: "en",
            trackIsAutoGenerated: true,
            entries: [],
            moments: [YouTubeMoment(videoID: videoID, timestamp: 30, excerpt: "An agent loop calls a tool.")],
            lastPosition: 30
        )
        record.entries = [
            TranscriptEntry(timestamp: 0, timeString: "0:00", text: "Welcome back."),
            TranscriptEntry(timestamp: 30, timeString: "0:30", text: "An agent loop calls a tool."),
            TranscriptEntry(timestamp: 60, timeString: "1:00", text: "Tool calls return results.")
        ]
        if let store = store, (try? store.save(record)) != nil {
            check(true, "a transcript with a Moment is stored locally")
        } else {
            check(false, "a transcript with a Moment is stored locally")
        }

        // Adopting the video again is what reloads the stored transcript, which is
        // what happens after switching away and back, or after a relaunch. It is
        // deliberately not a disk read on every tick.
        youTube.endSession()
        youTube.consume(tabs: [watchTab], bundle: bundle,
                        probe: "rby1|paused|-|-|42|false|\(videoID)|Agent Loops, Explained|Tool Calls")
        check(youTube.hasTranscript, "a stored transcript is loaded when the video is adopted")
        check(youTube.transcriptProvenance == "en · auto-generated captions",
              "the provenance names the real track")
        // A stored position belongs to the file, not to this session.
        check(youTube.storedPosition == 30, "the stored position is exposed as a labelled fact")
        check(youTube.session?.currentTime == nil, "a stored position is never presented as the live playhead")
        check(youTube.liveTimecode == "—", "with no real sample the clock stays unknown, not restored")
        check(youTube.recentMoments.count == 1, "stored Moments come back with the transcript")
        check(youTube.moment(nearest: 31)?.excerpt == "An agent loop calls a tool.",
              "the nearest stored Moment is found")
        check(youTube.searchTranscript("tool").count == 2, "transcript search is local and offline")
        check(youTube.searchTranscript("").isEmpty, "an empty search returns nothing")
        check(youTube.momentExcerpt(around: 30, window: 1)?.contains("An agent loop calls a tool.") == true,
              "a Moment quotes the exact caption line at the playhead")
        check(youTube.momentExcerpt(around: nil) == nil, "no playhead means no excerpt, not a guess")
        check(youTube.contextSlots(onSetup: {}, onAsk: {})
                .first { $0.key == "yt-ctx-transcribe" }?.title == "✓ TRANSCRIPT",
              "transcribe offers the stored transcript once one exists")

        youTube.forgetCurrentTranscript(videoID: videoID)
        check((try? store?.load(videoID: videoID)) == nil, "forgetting a video deletes its stored transcript")
        check(youTube.storedLibrary().count == 0, "the stored library is empty after forgetting")
        check(!youTube.hasTranscript, "the in-memory transcript is cleared too")

        // MARK: Session teardown

        youTube.consume(tabs: [watchTab], bundle: bundle, probe: YouTubeProbe.noVideoToken)
        check(youTube.session == nil, "a closed video ends the session")
        check(youTube.availability == .noSession, "the availability follows the session")
        check(youTube.persistentSlots() == nil, "the pinned mini-player disappears with the session")

        youTube.consume(tabs: [watchTab], bundle: bundle,
                        probe: "rby1|playing|10|100|50|false|\(videoID)|Title|-")
        check(youTube.session != nil, "a fresh payload starts a new session")
        youTube.consume(tabs: [watchTab], bundle: bundle, probe: "rby7|playing|10|100|50|false|x|y|z")
        check(youTube.availability == .scriptingDisabled,
              "a payload this version cannot read is treated as blocked, not as playback")

        let failed = failures.count
        print("\n\(passed) YouTube checks passed; \(failed) failed.")
        if failed > 0 {
            for name in failures { print("  ✗ \(name)") }
        }
        print("Synthetic probe payloads only. No Chrome tab was read, no AppleScript was sent, no caption was fetched, "
              + "the general pasteboard was never written, and no physical Touch Bar rendering was verified.")
        return failed == 0 ? 0 : 1
    }
}

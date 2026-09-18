"""YouTube wiring contracts.

Source checks, NOT native AppKit or browser execution. These lock in the four
things the feature is built on: one AppleScript round trip per tick, an honest
"scripted control is unavailable" state, no fabricated playback values, and
transcripts/Moments that are only ever produced because the user asked.
"""
from pathlib import Path
import unittest

R = Path(__file__).resolve().parents[2]
APP = (R / 'Sources/Mac/AppMain.swift').read_text()
CTRL = (R / 'Sources/Mac/YouTubeController.swift').read_text()
BRIDGE = (R / 'Sources/Mac/ChromeTabBridge.swift').read_text()
PANEL = (R / 'Sources/Mac/YouTubeTranscriptPanel.swift').read_text()
SETTINGS = (R / 'Sources/Mac/YouTubeSettingsPanel.swift').read_text()
CORE = (R / 'Sources/Core/YouTube.swift').read_text()
STORE = (R / 'Sources/Core/YouTubeTranscriptStore.swift').read_text()
COMP = (R / 'Sources/Mac/Components.swift').read_text()


def code(text):
    """Source with comments removed, so a comment about a banned pattern
    (for example the note that the old `?? 300` fallback is gone) cannot be
    mistaken for the pattern itself."""
    out = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith('//'):
            continue
        cut = line.find('//')
        if cut != -1 and line.count('"', 0, cut) % 2 == 0:
            line = line[:cut]
        out.append(line)
    return '\n'.join(out)


def body(text, signature):
    """The balanced-brace body of `signature`, so assertions stay scoped."""
    i = text.index(signature)
    i = text.index('{', i)
    depth = 0
    for j in range(i, len(text)):
        depth += (text[j] == '{') - (text[j] == '}')
        if depth == 0:
            return text[i:j + 1]
    raise ValueError(signature)


class YouTubeWiring(unittest.TestCase):

    # ---------------------------------------------------------------- cadence

    def test_probe_rides_along_with_the_tab_fetch(self):
        """A playback tick must not cost a second AppleScript round trip."""
        self.assertIn('chromeBridge.probeYouTube = youTube.takeProbeSlot()', APP)
        self.assertIn('public var probeYouTube: Bool = false', BRIDGE)
        self.assertIn('let probe = probeYouTube', BRIDGE)
        # The adapter is fed from the fetch the browser bridge already completed.
        self.assertIn('chromeBridge.onFetched = ', APP)
        consume = body(APP, 'chromeBridge.onFetched = ')
        self.assertIn('youTube.consume(tabs: self.chromeBridge.tabs', consume)
        self.assertIn('probe: self.chromeBridge.lastProbe', consume)

    def test_one_probe_payload_builder_shared_by_both_transports(self):
        """Both transports read the same in-page payload, so they cannot drift."""
        self.assertEqual(BRIDGE.count('rby1'), 1)
        self.assertEqual(BRIDGE.count('rby-unavailable'), 1)
        self.assertIn('public static let wireVersion = "rby1"', CORE)
        self.assertIn("['rby1',st,t,d,vol,String(v.muted)", BRIDGE)
        # The process fallback is used only when the in-process script fails.
        self.assertIn('/usr/bin/osascript', BRIDGE)
        self.assertLess(BRIDGE.index('NSAppleScript'),
                        BRIDGE.index('/usr/bin/osascript'))

    def test_probing_is_gated_by_a_pure_cadence_table(self):
        gated = body(CTRL, 'public func takeProbeSlot(')
        self.assertIn('YouTubeCadence.interval(', gated)
        self.assertIn('screenAwake', gated)
        self.assertIn('lastProbeAttempt', gated)
        # The Mac layer may not invent its own polling rhythm.
        self.assertNotIn('Timer.scheduledTimer', CTRL)
        self.assertNotIn('DispatchQueue.main.asyncAfter', CTRL)

    def test_idle_states_stop_polling(self):
        self.assertIn('guard hasSession, screenAwake else { return nil }', CORE)
        self.assertIn('case .unavailable:', CORE)
        self.assertIn('screenAwake = true', CTRL)

    # ----------------------------------------------------------- honest state

    def test_no_fabricated_playback_values(self):
        """The previous build invented a clock, a duration, a volume and a chapter."""
        for text, name in ((code(CTRL), 'YouTubeController'), (code(CORE), 'YouTube.swift')):
            self.assertNotIn('Architecture', text, name)
            self.assertNotIn('?? 300', text, name)
            self.assertNotIn('?? 75', text, name)
            self.assertNotIn('?? true', text, name)
            self.assertNotIn('isPlaying = true', text, name)
        self.assertNotIn('currentTime += 0.5', code(CTRL))
        self.assertIn('public var liveTimecode: String { clock?.displayTimecode() ?? "—" }', CTRL)

    def test_blocked_control_is_explained_and_retryable(self):
        self.assertIn('View → Developer → Allow JavaScript from Apple Events', CORE)
        self.assertIn('will not guess', CORE)
        self.assertIn('YouTubeControlAvailability.setupInstructions', SETTINGS)
        self.assertIn('youTube.retryControl()', SETTINGS)
        self.assertIn('⚠ Enable control', CTRL)
        self.assertIn('key: "yt-ctx-retry"', CTRL)
        # A refused probe must not become a confident-looking mini-player.
        setupslot = CTRL[CTRL.index('if session.availability == .scriptingDisabled'):
                        CTRL.index('let playTitle =')]
        self.assertIn('retryControl()', setupslot)
        self.assertNotIn('yt-mini-play', setupslot)

    def test_no_session_produces_no_bar(self):
        slots = body(CTRL, 'func persistentSlots(expanded: Bool = false)')
        self.assertIn('guard let session = session else { return nil }', slots)
        self.assertTrue(slots.index('return nil') < slots.index('yt-mini-play'))
        # A malformed payload is reported, never treated as playback.
        start = CTRL.index('case .malformed(let reason):')
        malformed = CTRL[start:start + 320]
        self.assertIn('availability = .scriptingDisabled', malformed)
        self.assertIn('will not guess', malformed)

    def test_tab_selection_is_deterministic(self):
        self.assertIn('YouTubeTabSelector.pick(tabs:', CTRL)
        self.assertNotIn('first(where: { $0.url.contains("youtube")', CTRL)
        self.assertIn('if let active = watchTabs.first(where: { $0.isSelected }) { return active }', CORE)
        self.assertIn('if let match = watchTabs.first(where: { YouTubeVideoID.parse(url: $0.url) == last })', CORE)

    # ------------------------------------------------------------- the bar

    def test_clock_and_volume_update_in_place_instead_of_rebuilding(self):
        """A rebuild every tick destroyed the tab strip's finger-scroll position."""
        progress = body(APP, 'youTube.onProgressChange = ')
        self.assertIn('self.youTube.progressTitles', progress)
        self.assertIn('retitle(', progress)
        self.assertNotIn('rebuildBars()', progress)

        changed = body(APP, 'youTube.onStateChange = ')
        self.assertIn('self.rebuildBars()', changed)

        keys = body(CTRL, 'public var progressTitles:')
        for key in ('yt-mini-clock', 'yt-mini-jump', 'yt-mini-vol'):
            self.assertIn(key, keys)
        # The changed-in-place titles must be keys the bar actually draws.
        for key in ('yt-mini-clock', 'yt-mini-vol', 'yt-mini-play'):
            self.assertIn(f'key: "{key}"', CTRL)
        self.assertIn('func retitle(', COMP)

    def test_mini_player_is_pinned_and_yields_space_when_foreground(self):
        slots = body(CTRL, 'func persistentSlots(expanded: Bool = false)')
        self.assertIn('if expanded {', slots)
        self.assertIn('key: "yt-mini-slider"', slots)
        self.assertIn('VolumeSliderView(', slots)
        # Play/pause and volume come first and never move, in both layers.
        self.assertLess(slots.index('yt-mini-play'), slots.index('yt-mini-vol'))
        self.assertLess(slots.index('yt-mini-vol'), slots.index('yt-mini-slider'))
        # The "jump back to the tab" pill is only for the un-expanded bar, and
        # the pinned clock takes its place once YouTube is in front.
        ready = slots[slots.index('let playTitle'):]
        expanded, collapsed = ready[:ready.index('if expanded {')], ready[ready.index('if expanded {'):]
        self.assertNotIn('jumpSlot(for: session)', expanded)
        self.assertIn('jumpSlot(for: session)', collapsed)

    def test_foreground_layer_is_added_after_the_pinned_layer(self):
        shell = body(APP, 'private func persistentShellSlots(')
        self.assertLess(shell.index('persistentSlots(expanded: ytForeground)'),
                        shell.index('shellAppSlot(.chrome)'))
        self.assertIn('YouTubeVideoID.isWatchPage(activeURL)', shell)
        contextual = body(APP, 'private func familySlots(')
        self.assertIn('youTube.contextSlots(', contextual)

    # ------------------------------------------------------- transcripts

    def test_captions_are_only_fetched_because_the_user_asked(self):
        self.assertEqual(CTRL.count('URLSession'), 1)
        fetch = body(CTRL, 'private func fetchCaptionTrack(')
        self.assertIn('URLSession', fetch)
        self.assertIn('fmt=json3', fetch)
        # Only the two user-initiated entry points reach a network fetch.
        self.assertEqual(CTRL.count('fetchCaptionTrack(track,'), 2)
        self.assertIn('public func startTranscription()', CTRL)
        self.assertIn('public func loadTrack(languageCode: String)', CTRL)
        self.assertIn('self.startTranscription()', CTRL)
        # Nothing about polling starts a transcript.
        consume = body(CTRL, 'public func consume(tabs:')
        self.assertNotIn('startTranscription', consume)
        self.assertNotIn('URLSession', consume)

    def test_a_stored_transcript_is_reused_instead_of_refetched(self):
        start = body(CTRL, 'public func startTranscription()')
        self.assertLess(start.index('adoptStored(stored, fromCache: true)'),
                        start.index('transcriptionState = .loadingTrackList'),
                        'a stored transcript is shown before a track list is fetched')
        self.assertNotIn('URLSession', start)
        self.assertIn('loadStoredRecord(for: videoID?.raw ?? "")', CTRL)
        self.assertIn('try? store.load(videoID: videoID)', CTRL)

    def test_storage_is_local_bounded_and_removable(self):
        self.assertIn('try store?.save(record)', CTRL)
        self.assertIn('try store?.delete(videoID: videoID)', CTRL)
        self.assertIn('store?.deleteAll()', CTRL)
        self.assertIn('public func forgetCurrentTranscript(videoID: String)', CTRL)
        self.assertIn('maximumVideos', CORE)
        self.assertIn('maximumMomentsPerVideo', CORE)
        # A record is validated before it is written and after it is read.
        self.assertIn('try record.validate()', STORE)
        self.assertEqual(STORE.count('try record.validate()'), 2)
        self.assertIn('posixPermissions: 0o600', STORE)
        self.assertIn('posixPermissions: 0o700', STORE)

    def test_moment_quotes_the_real_caption_line_at_the_playhead(self):
        capture = body(CTRL, 'public func captureMoment()')
        self.assertIn('TranscriptIndex.snapped(to: time, in: transcriptEntries)', capture)
        self.assertIn('currentChapterTitle', capture)
        self.assertIn('pastedText(title:', capture)
        self.assertIn('momentExcerpt', CTRL)
        self.assertIn('shareURL(at: timestamp)', CORE)

    def test_transcript_panel_is_synchronized_with_playback(self):
        self.assertIn('onSeek: { [weak self] time in self?.seek(to: time) }', CTRL)
        self.assertIn('onSearch: { [weak self] query in self?.searchTranscript(query)', CTRL)
        self.assertIn('private func followTick()', PANEL)
        self.assertIn('private func startFollowing()', PANEL)
        # A transcript line jumps playback, which is what makes it synchronized.
        self.assertIn('onSeek', PANEL)
        self.assertIn('TranscriptIndex.search', CTRL)

    def test_a_stored_position_is_never_shown_as_the_live_clock(self):
        self.assertIn('public private(set) var storedPosition: Double?', CTRL)
        adopt = body(CTRL, 'private func adoptStored(_ record: YouTubeTranscriptRecord')
        self.assertIn('storedPosition = record.lastPosition', adopt)
        self.assertNotIn('session?.currentTime = position', adopt)
        self.assertNotIn('clock = YouTubeSessionClock', adopt)
        # It is surfaced to the panel as a labelled fact about the stored file.
        self.assertIn('lastPosition: storedPosition', CTRL)
        self.assertIn('lastPosition: Double? = nil', PANEL)
        self.assertIn('last watched ', PANEL)

    def test_provenance_is_reported_with_the_transcript(self):
        self.assertIn('transcriptProvenance', CTRL)
        self.assertIn('auto-generated captions', CORE)

    # --------------------------------------------------------- commands

    def test_volume_drag_coalesces_to_the_newest_value(self):
        volume = body(CTRL, 'public func setVolume(_ value: Int)')
        self.assertIn('enqueue(.volume(clamped))', volume)
        self.assertIn('onProgressChange?()', volume)
        enqueue = body(CTRL, 'private func enqueue(_ command: Command)')
        self.assertIn('pendingCommand = command', enqueue)
        pump = body(CTRL, 'private func pumpCommands()')
        self.assertIn('guard !commandInFlight', pump)
        # One command at a time, newest wins: a drag cannot queue a process each tick.
        self.assertIn('pendingCommand = nil', pump)

    def test_a_command_suppresses_the_reconciling_probe(self):
        self.assertIn('YouTubeSessionClockPolicy.settleWindow', CTRL)
        consume = body(CTRL, 'public func consume(tabs:')
        self.assertIn('let settling = date < settleUntil', consume)
        self.assertIn('settling: settling', consume)

    def test_commands_are_only_sent_when_control_works(self):
        for signature in ('public func togglePlayPause()', 'public func toggleMute()',
                          'public func setVolume(_ value: Int)',
                          'public func cyclePlaybackRate()'):
            scoped = body(CTRL, signature)
            self.assertIn('session.availability == .ready', scoped, signature)
            self.assertIn('requireSetup()', scoped, signature)

    # ----------------------------------------------------------- reachability

    def test_settings_and_transcript_panels_are_reachable(self):
        self.assertIn('YouTube Control & Storage…', APP)
        self.assertIn('#selector(showYouTubeSettingsFromMenu)', APP)
        self.assertIn('@objc private func showYouTubeSettingsFromMenu()', APP)
        self.assertIn('YouTubeTranscriptStore(directory: store.transcriptsURL)', APP)
        self.assertIn('youTube.attach(store: youTubeStore)', APP)
        self.assertIn('YouTubeSettingsPanel(store: youTubeStore)', APP)
        self.assertIn('onSetup:', CTRL)
        self.assertIn('self.openTranscriptPanel()', CTRL)

    def test_ask_about_youtube_is_bounded_and_never_sends_itself(self):
        ask = body(APP, 'private func askAIAboutYouTube()')
        self.assertIn('momentExcerpt(around: time)', ask)
        # No real playhead means no invented timecode in the header.
        self.assertIn('if time != nil { header += " at \\(timecode)" }', ask)
        # An empty transcript is stated, not silently quoted as empty.
        self.assertIn('No transcript has been built for this video yet, so no caption lines are quoted.', ask)
        # The prompt only becomes a reviewable draft: nothing is sent or copied.
        self.assertIn('navigate(to: .draft)', ask)
        self.assertNotIn('URLSession', ask)
        self.assertNotIn('NSPasteboard', ask)
        self.assertNotIn('openURL', ask)


class YouTubeCoreContracts(unittest.TestCase):

    def test_core_is_pure(self):
        for forbidden in ('import AppKit', 'import Cocoa', 'NSAppleScript',
                          'Process()', 'URLSession'):
            self.assertNotIn(forbidden, CORE, forbidden)

    def test_policy_constants_are_used_not_inlined(self):
        self.assertIn('YouTubePolicy.maximumTranscriptCharacters', CORE)
        self.assertIn('YouTubePolicy.maximumVideos', CORE)
        self.assertIn('YouTubePolicy.excerptWindow', CORE)
        self.assertIn('YouTubePolicy.searchLimit', CORE)

    def test_wire_format_is_versioned(self):
        self.assertIn('public static let wireVersion = "rby1"', CORE)
        self.assertIn('Unsupported probe payload.', CORE)
        self.assertIn('Truncated probe payload.', CORE)

    def test_no_default_duration_or_chapter_survives(self):
        self.assertNotIn('duration ?? ', CORE.replace('metrics.duration ?? duration', ''))
        self.assertNotIn('volume ?? 75', CORE)
        self.assertNotIn('currentTime ?? 0', CORE)

    def test_short_links_are_recognised(self):
        # youtu.be/<id> has a one-component path; the parser must still accept it.
        self.assertIn('if host == "youtu.be" || host.hasSuffix(".youtu.be")', CORE)


if __name__ == '__main__':
    unittest.main(verbosity=2)

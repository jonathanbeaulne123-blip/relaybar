import Foundation
import XCTest
@testable import RelayCore

/// YouTube policy is tested without a browser, a network, or a Touch Bar.
///
/// Several tests here exist solely to lock in the *absence* of fabrication: a
/// probe that cannot read the page must not become a confident clock, a
/// default duration, or an invented chapter.
final class YouTubeTests: XCTestCase {

    // MARK: - Video identity

    func testWatchPageParsing() {
        XCTAssertEqual(YouTubeVideoID.parse(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")?.raw, "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeVideoID.parse(url: "https://m.youtube.com/watch?v=dQw4w9WgXcQ")?.raw, "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeVideoID.parse(url: "https://youtube.com/watch?v=abc_123-XYZ&t=42s")?.raw, "abc_123-XYZ")
        XCTAssertEqual(YouTubeVideoID.parse(url: "https://youtu.be/dQw4w9WgXcQ")?.raw, "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeVideoID.parse(url: "https://youtu.be/dQw4w9WgXcQ?t=90")?.raw, "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeVideoID.parse(url: "https://www.youtube.com/shorts/abc123DEF45")?.raw, "abc123DEF45")
        XCTAssertEqual(YouTubeVideoID.parse(url: "https://www.youtube.com/embed/abc123DEF45")?.raw, "abc123DEF45")
        XCTAssertEqual(YouTubeVideoID.parse(url: "https://www.youtube.com/live/abc123DEF45")?.raw, "abc123DEF45")
        XCTAssertEqual(YouTubeVideoID.parse(url: "https://www.youtube-nocookie.com/embed/abc123DEF45")?.raw, "abc123DEF45")
    }

    func testWatchPageParsingRefusesNonWatchPages() {
        XCTAssertNil(YouTubeVideoID.parse(url: ""))
        XCTAssertNil(YouTubeVideoID.parse(url: "https://www.youtube.com/"))
        XCTAssertNil(YouTubeVideoID.parse(url: "https://www.youtube.com/watch"))
        XCTAssertNil(YouTubeVideoID.parse(url: "https://www.youtube.com/@somechannel"))
        XCTAssertNil(YouTubeVideoID.parse(url: "https://example.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(YouTubeVideoID.parse(url: "https://notyoutube.com/watch?v=dQw4w9WgXcQ"))
        // A host that merely ends with the substring is not YouTube.
        XCTAssertNil(YouTubeVideoID.parse(url: "https://evil-youtube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertFalse(YouTubeVideoID.isWatchPage("chrome://newtab"))
    }

    func testRawIdentifierValidation() {
        XCTAssertEqual(YouTubeVideoID(raw: "  abc  ")?.raw, "abc")
        XCTAssertNil(YouTubeVideoID(raw: ""))
        XCTAssertNil(YouTubeVideoID(raw: "   "))
        XCTAssertNil(YouTubeVideoID(raw: "abc def"))
        XCTAssertNil(YouTubeVideoID(raw: "abc/def"))
        XCTAssertNil(YouTubeVideoID(raw: String(repeating: "a", count: 65)))
        XCTAssertNotNil(YouTubeVideoID(raw: String(repeating: "a", count: 64)))
    }

    func testShareURLKeepsTheMomentTime() {
        let id = YouTubeVideoID(raw: "dQw4w9WgXcQ")!
        XCTAssertEqual(id.watchURL?.absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(id.shareURL(at: 764.9)?.absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=764s")
        // A negative or unknown time never produces a bogus offset.
        XCTAssertEqual(id.shareURL(at: -12)?.absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=0s")
    }

    // MARK: - Probe payloads

    func testProbeParsesAFullPayload() {
        let result = YouTubeProbe.parse(payload: "rby1|playing|744.5|3723|42|false|dQw4w9WgXcQ|Agent Loops, Explained|Tool Calls")
        guard let metrics = result.metrics else { return XCTFail("expected metrics, got \(result)") }
        XCTAssertEqual(metrics.state, .playing)
        XCTAssertEqual(metrics.currentTime, 744.5)
        XCTAssertEqual(metrics.duration, 3723)
        XCTAssertEqual(metrics.volume, 42)
        XCTAssertEqual(metrics.isMuted, false)
        XCTAssertEqual(metrics.videoID?.raw, "dQw4w9WgXcQ")
        XCTAssertEqual(metrics.title, "Agent Loops, Explained")
        XCTAssertEqual(metrics.chapter, "Tool Calls")
        XCTAssertEqual(metrics.formattedTime, "12:24")
    }

    /// The central invariant: unreadable fields stay unknown. No `?? true`,
    /// no `?? 300`, no `?? 75`, and no hard-coded chapter may reappear.
    func testProbeNeverInventsMissingFields() {
        let result = YouTubeProbe.parse(payload: "rby1|paused|-|-|-|-|dQw4w9WgXcQ|-|-")
        guard let metrics = result.metrics else { return XCTFail("expected metrics, got \(result)") }
        XCTAssertEqual(metrics.state, .paused)
        XCTAssertNil(metrics.currentTime, "an unreadable playhead must stay unknown")
        XCTAssertNil(metrics.duration, "an unreadable duration must stay unknown")
        XCTAssertNil(metrics.volume, "an unreadable volume must stay unknown")
        XCTAssertNil(metrics.isMuted, "an unreadable mute flag must stay unknown")
        XCTAssertNil(metrics.title)
        XCTAssertNil(metrics.chapter, "RelayBar must never name a chapter the page did not report")
    }

    func testProbeReportsScriptingDisabledRatherThanGuessing() {
        XCTAssertEqual(YouTubeProbe.parse(payload: "rby-unavailable"), .scriptingDisabled)
        XCTAssertEqual(YouTubeProbe.parse(payload: "  rby-unavailable "), .scriptingDisabled)
        XCTAssertEqual(YouTubeProbe.parse(payload: "rby-no-video"), .noVideo)
        XCTAssertEqual(YouTubeProbe.parse(payload: ""), .noVideo)
        XCTAssertNil(YouTubeProbe.parse(payload: "rby-unavailable").metrics)
    }

    func testProbeRejectsUnusablePayloads() {
        // A newer RelayBar's payload is refused, not misread.
        XCTAssertEqual(YouTubeProbe.parse(payload: "rby2|playing|1|2|3|false|x|y|z"),
                       .malformed("Unsupported probe payload."))
        XCTAssertEqual(YouTubeProbe.parse(payload: "rby1|playing"),
                       .malformed("Truncated probe payload."))
        XCTAssertEqual(YouTubeProbe.parse(payload: "rby1|buffering|1|2|3|false|x|y|z"),
                       .malformed("Unknown playback state “buffering”."))

        // Control characters are stripped before they can reach the UI.
        let noisy = YouTubeProbe.parse(payload: "rby1|\u{7}playing|1|2|3|false|x|y|z")
        if case .malformed(let message) = noisy {
            XCTAssertFalse(message.unicodeScalars.contains { $0.value == 7 })
        } else {
            XCTFail("expected a malformed result")
        }
    }

    func testProbeClampsNonsenseNumbers() {
        let result = YouTubeProbe.parse(payload: "rby1|playing|-90|-5|150|TRUE|-|Title|-")
        guard let metrics = result.metrics else { return XCTFail("expected metrics, got \(result)") }
        XCTAssertEqual(metrics.currentTime, 0)
        XCTAssertEqual(metrics.duration, 0)
        XCTAssertEqual(metrics.volume, 100)
        XCTAssertNil(metrics.isMuted, "an unparseable mute flag must stay unknown")
        XCTAssertNil(metrics.videoID)
    }

    func testProbeTruncatesOverlongText() {
        let title = String(repeating: "t", count: YouTubePolicy.maximumTitle + 500)
        let result = YouTubeProbe.parse(payload: "rby1|playing|1|2|3|false|x|\(title)|-")
        XCTAssertEqual(result.metrics?.title?.count, YouTubePolicy.maximumTitle)
    }

    // MARK: - Availability

    func testAvailabilityDistinguishesSetupFromFailure() {
        XCTAssertFalse(YouTubeControlAvailability.ready.setupRequired)
        XCTAssertEqual(YouTubeControlAvailability.ready.buttonTitle, "YouTube")
        XCTAssertFalse(YouTubeControlAvailability.noSession.setupRequired)
        XCTAssertEqual(YouTubeControlAvailability.noSession.status, "No YouTube watch page is open.")

        XCTAssertTrue(YouTubeControlAvailability.scriptingDisabled.setupRequired)
        let status = YouTubeControlAvailability.scriptingDisabled.status
        XCTAssertTrue(status.contains("View → Developer"), "the guidance must name Chrome's real menu path")
        XCTAssertTrue(status.contains("Apple Events"))
        XCTAssertTrue(status.contains("will not guess"), "a blocked probe must explain itself, not pretend")
    }

    func testSetupInstructionsNameChromesExactMenuPath() {
        let instructions = YouTubeControlAvailability.setupInstructions
        XCTAssertTrue(instructions.contains("View → Developer → Allow JavaScript from Apple Events"))
        XCTAssertTrue(instructions.contains("privacy") == false)
        XCTAssertTrue(instructions.lowercased().contains("no cookies"))
    }

    // MARK: - Tab selection

    private func tab(_ id: Int, _ url: String, selected: Bool = false) -> BrowserTab {
        BrowserTab(id: id, index: id, title: "Tab \(id)", url: url, isSelected: selected)
    }

    func testTabSelectionIsDeterministic() {
        let watch = "https://www.youtube.com/watch?v=aaaaaaaaaaa"
        let other = "https://www.youtube.com/watch?v=bbbbbbbbbbb"
        let news = "https://news.ycombinator.com"

        // 1. The active watch page wins even if another video was tracked.
        let active = YouTubeTabSelector.pick(tabs: [tab(1, watch), tab(2, other, selected: true), tab(3, news)],
                                            lastVideoID: YouTubeVideoID(raw: "aaaaaaaaaaa"))
        XCTAssertEqual(active?.id, 2)

        // 2. With nothing foregrounded, the tracked video is preferred.
        let tracked = YouTubeTabSelector.pick(tabs: [tab(1, other), tab(2, watch), tab(3, news)],
                                             lastVideoID: YouTubeVideoID(raw: "aaaaaaaaaaa"))
        XCTAssertEqual(tracked?.id, 2)

        // 3. Otherwise the first watch page in tab order, never a non-watch tab.
        let first = YouTubeTabSelector.pick(tabs: [tab(1, news), tab(2, other), tab(3, watch)], lastVideoID: nil)
        XCTAssertEqual(first?.id, 2)
    }

    func testTabSelectionRefusesOffTopicTabs() {
        XCTAssertNil(YouTubeTabSelector.pick(tabs: [], lastVideoID: nil))
        XCTAssertNil(YouTubeTabSelector.pick(tabs: [tab(1, "https://news.ycombinator.com"),
                                                    tab(2, "https://www.youtube.com/")],
                                             lastVideoID: nil))
        XCTAssertNil(YouTubeTabSelector.pick(tabs: [tab(1, "chrome://newtab")], lastVideoID: nil))
    }

    // MARK: - Timecode

    func testTimecodeFormatting() {
        XCTAssertEqual(YouTubeTimecode.format(0), "0:00")
        XCTAssertEqual(YouTubeTimecode.format(9), "0:09")
        XCTAssertEqual(YouTubeTimecode.format(59), "0:59")
        XCTAssertEqual(YouTubeTimecode.format(60), "1:00")
        XCTAssertEqual(YouTubeTimecode.format(764), "12:44")
        XCTAssertEqual(YouTubeTimecode.format(3599), "59:59")
        XCTAssertEqual(YouTubeTimecode.format(3600), "1:00:00")
        XCTAssertEqual(YouTubeTimecode.format(3725.9), "1:02:05")
    }

    func testUnknownTimeRendersAsADash() {
        XCTAssertEqual(YouTubeTimecode.format(nil), "—")
        XCTAssertEqual(YouTubeTimecode.format(.nan), "—")
        XCTAssertEqual(YouTubeTimecode.format(.infinity), "—")
        XCTAssertEqual(YouTubeTimecode.format(-1), "—")
        XCTAssertEqual(YouTubeTimecode.format(Double?.none), "—")
        XCTAssertNotEqual(YouTubeTimecode.format(nil), YouTubeTimecode.format(0))
    }

    func testTimecodeParsing() {
        XCTAssertEqual(YouTubeTimecode.parse("12:44"), 764)
        XCTAssertEqual(YouTubeTimecode.parse("1:02:03"), 3723)
        XCTAssertEqual(YouTubeTimecode.parse("90"), 90)
        XCTAssertEqual(YouTubeTimecode.parse(" 1 : 00 "), 60)
        XCTAssertNil(YouTubeTimecode.parse(""))
        XCTAssertNil(YouTubeTimecode.parse("abc"))
        XCTAssertNil(YouTubeTimecode.parse("1:2:3:4"))
        XCTAssertNil(YouTubeTimecode.parse("-5"))
    }

    // MARK: - Chapters

    func testChapterPayloadIsSortedAndDeduplicated() {
        let payload = """
        289:Tool Calls
        0:Architecture
        120:Agent Loop
        120:Agent Loop (repeat)
        nonsense:Broken
        -4:Negative
        :Untitled
        """
        let index = YouTubeChapterIndex(payload: payload)
        XCTAssertEqual(index.count, 3, "invalid, negative and duplicate starts are dropped")
        XCTAssertEqual(index.chapters.map(\.title), ["Architecture", "Agent Loop", "Tool Calls"])
        XCTAssertEqual(index.chapters.map(\.timecode), ["0:00", "2:00", "4:49"])
    }

    func testChapterLookupAroundThePlayhead() {
        let index = YouTubeChapterIndex(chapters: [
            YouTubeChapter(start: 0, title: "Intro"),
            YouTubeChapter(start: 120, title: "Middle"),
            YouTubeChapter(start: 300, title: "End")
        ])
        XCTAssertNil(index.chapter(at: -1), "there is no chapter before the video starts")
        XCTAssertEqual(index.label(at: 0), "Intro")
        XCTAssertEqual(index.label(at: 119.9), "Intro")
        XCTAssertEqual(index.label(at: 120), "Middle")
        XCTAssertEqual(index.label(at: 10_000), "End")
        XCTAssertEqual(index.next(after: 0)?.title, "Middle")
        XCTAssertEqual(index.next(after: 299)?.title, "End")
        XCTAssertNil(index.next(after: 300))
        XCTAssertEqual(index.previous(before: 300)?.title, "Middle")
        XCTAssertNil(index.previous(before: 2), "there is no chapter before the first one")
        XCTAssertEqual(index.previous(before: 290)?.title, "Middle",
                       "a chapter only counts as 'previous' once it is well behind the playhead")
    }

    func testEmptyChapterIndexStaysEmpty() {
        let index = YouTubeChapterIndex()
        XCTAssertTrue(index.isEmpty)
        XCTAssertEqual(index.count, 0)
        XCTAssertNil(index.chapter(at: 500), "no chapters must stay no chapters, not a placeholder")
        XCTAssertNil(index.label(at: 500))
    }

    // MARK: - Caption tracks

    func testTrackListPayload() {
        let payload = """
        en|English|https://www.youtube.com/api/timedtext?v=abc&lang=en
        en-asr|English (auto-generated)|https://www.youtube.com/api/timedtext?v=abc&lang=en&kind=asr
        fr|Français|https://www.youtube.com/api/timedtext?v=abc&lang=fr
        ||https://example.com/empty-language
        de|German|not-a-url
        """
        let list = TranscriptTrackList(payload: payload)
        XCTAssertEqual(list.tracks.count, 3)
        XCTAssertFalse(list.track(languageCode: "en-asr")!.isAutoGenerated == false)
        XCTAssertTrue(list.track(languageCode: "fr")!.isAutoGenerated == false)
        XCTAssertNil(list.track(languageCode: "de"), "a track without a usable URL is not offered")
    }

    func testTrackPreferenceOrder() {
        let list = TranscriptTrackList(tracks: [
            TranscriptTrack(languageCode: "en", name: "English (auto-generated)", isAutoGenerated: true,
                            url: "https://example.com/asr"),
            TranscriptTrack(languageCode: "en", name: "English", isAutoGenerated: false,
                            url: "https://example.com/manual"),
            TranscriptTrack(languageCode: "fr", name: "Français", isAutoGenerated: false,
                            url: "https://example.com/fr")
        ])
        XCTAssertEqual(list.preferred(preferring: nil)?.url, "https://example.com/manual",
                       "a manual track beats an auto-generated one")
        XCTAssertEqual(list.preferred(preferring: "fr")?.url, "https://example.com/fr")
    }

    func testAutoGeneratedDetection() {
        XCTAssertTrue(TranscriptTrack.autoGenerated(languageCode: "en", name: "English (auto-generated)"))
        XCTAssertTrue(TranscriptTrack.autoGenerated(languageCode: "en-asr", name: ""))
        XCTAssertFalse(TranscriptTrack.autoGenerated(languageCode: "en", name: "English"))
    }

    // MARK: - Transcript index

    private func entries(_ pairs: [(Double, String)]) -> [TranscriptEntry] {
        pairs.compactMap { TranscriptEntry(timestamp: $0.0, text: $0.1) }
    }

    private var sample: [TranscriptEntry] {
        entries([
            (0, "Welcome back to the channel."),
            (12, "Today we are talking about agent loops."),
            (30, "An agent loop is a cycle of tool calls."),
            (60, "The tool call returns a result."),
            (90, "That result feeds the next model call."),
            (120, "So the loop keeps going until it stops.")
        ])
    }

    func testNormalizeCollapsesWhitespaceAndControlCharacters() {
        XCTAssertEqual(TranscriptIndex.normalize("  hello \n\t world  "), "hello world")
        XCTAssertEqual(TranscriptIndex.normalize("a\u{0}b"), "ab")
        XCTAssertEqual(TranscriptIndex.normalize(""), "")
    }

    func testEntryRefusesEmptyCaptionText() {
        XCTAssertNil(TranscriptEntry(timestamp: 10, text: "   "))
        XCTAssertNil(TranscriptEntry(timestamp: .nan, text: "text"))
        XCTAssertNil(TranscriptEntry(timestamp: -1, text: "text"))
        XCTAssertEqual(TranscriptEntry(timestamp: 65, text: " hi  there ")?.timeString, "1:05")
        XCTAssertEqual(TranscriptEntry(timestamp: 65, text: " hi  there ")?.text, "hi there")
    }

    func testLineAtPlayhead() {
        let lines = sample
        XCTAssertNil(TranscriptIndex.line(at: -5, in: lines), "before the first line there is nothing to quote")
        XCTAssertEqual(TranscriptIndex.line(at: 0, in: lines)?.text, "Welcome back to the channel.")
        XCTAssertEqual(TranscriptIndex.line(at: 29, in: lines)?.text, "Today we are talking about agent loops.")
        XCTAssertEqual(TranscriptIndex.line(at: 30, in: lines)?.text, "An agent loop is a cycle of tool calls.")
        XCTAssertEqual(TranscriptIndex.line(at: 200, in: lines)?.text, "So the loop keeps going until it stops.")
        XCTAssertEqual(TranscriptIndex.snapped(to: 61, in: lines)?.text, "The tool call returns a result.")
        XCTAssertNil(TranscriptIndex.line(at: .nan, in: lines))
    }

    func testEntryIndexLookup() {
        let lines = sample
        XCTAssertEqual(TranscriptIndex.index(of: lines[2], in: lines), 2)
        XCTAssertNil(TranscriptIndex.index(of: TranscriptEntry(timestamp: 999, timeString: "16:39", text: "nope"), in: lines))
    }

    func testExcerptKeepsTimecodesAndStaysBounded() {
        let excerpt = TranscriptIndex.excerpt(around: 60, window: 31, in: sample)
        XCTAssertTrue(excerpt.contains("[0:30] An agent loop is a cycle of tool calls."))
        XCTAssertTrue(excerpt.contains("[1:00] The tool call returns a result."))
        XCTAssertFalse(excerpt.contains("Welcome back"), "the window is respected")

        let whole = TranscriptIndex.excerpt(around: 60, window: 10_000, in: sample)
        XCTAssertTrue(whole.contains("[2:00]"))

        XCTAssertEqual(TranscriptIndex.excerpt(around: .nan, in: sample), "")
        XCTAssertEqual(TranscriptIndex.excerpt(around: 60, window: 0, in: sample), "")
        XCTAssertEqual(TranscriptIndex.excerpt(around: 60, in: []), "")

        let huge = entries((0..<600).map { (Double($0), "Line number \($0) with some filler text in it.") })
        XCTAssertLessThanOrEqual(TranscriptIndex.excerpt(around: 300, window: 10_000, in: huge).count,
                                 YouTubePolicy.maximumExcerptCharacters)
    }

    func testLocalSearchRequiresEveryTokenAndRanksByRelevance() {
        let lines = entries([
            (0, "An agent loop calls a tool."),
            (10, "Tool calls are the interesting part of a tool loop."),
            (20, "Unrelated sentence."),
            (30, "TOOL CALLS again, in capitals.")
        ])
        let hits = TranscriptIndex.search("tool calls", in: lines)
        XCTAssertEqual(hits.count, 3)
        XCTAssertFalse(hits.contains { $0.entry.text == "Unrelated sentence." })
        XCTAssertTrue(hits.allSatisfy { $0.score > 0 })
        XCTAssertEqual(hits.map(\.entry.timestamp), [10, 30, 0],
                       "more occurrences rank first, then the earliest line")

        XCTAssertTrue(TranscriptIndex.search("tool cave", in: lines).isEmpty, "all tokens must be present")
        XCTAssertTrue(TranscriptIndex.search("", in: lines).isEmpty)
        XCTAssertTrue(TranscriptIndex.search("   ", in: lines).isEmpty)
        XCTAssertTrue(TranscriptIndex.search("tool", in: []).isEmpty)
        XCTAssertEqual(TranscriptIndex.search("tool", in: lines, limit: 1).count, 1)
    }

    func testSearchIsCaseInsensitiveAndQueryBounded() {
        let lines = entries([(0, "Hello World")])
        XCTAssertEqual(TranscriptIndex.search("hello", in: lines).count, 1)
        XCTAssertEqual(TranscriptIndex.search("HELLO WORLD", in: lines).count, 1)
        let longQuery = String(repeating: "hello ", count: 100)
        XCTAssertEqual(TranscriptIndex.search(longQuery, in: lines).count, 1)
    }

    func testCharacterCountTracksTheCap() {
        XCTAssertEqual(TranscriptIndex.characterCount(sample),
                       sample.reduce(0) { $0 + $1.text.count })
        XCTAssertEqual(TranscriptIndex.characterCount([]), 0)
    }

    func testJSON3Parsing() {
        let json = """
        {"events":[
          {"tStartMs":0,"segs":[{"utf8":"Welcome "},{"utf8":"back."}]},
          {"tStartMs":12500,"segs":[{"utf8":"Second line."}]},
          {"tStartMs":20000}
        ]}
        """
        let parsed = TranscriptIndex.parseJSON3(Data(json.utf8))
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].timestamp, 0)
        XCTAssertEqual(parsed[0].text, "Welcome back.")
        XCTAssertEqual(parsed[1].timestamp, 12.5)
        XCTAssertEqual(parsed[1].timeString, "0:12")
    }

    func testJSON3ParsingIsTotal() {
        XCTAssertTrue(TranscriptIndex.parseJSON3(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(TranscriptIndex.parseJSON3(Data("{}".utf8)).isEmpty)
        XCTAssertTrue(TranscriptIndex.parseJSON3(Data(#"{"events":[]}"#.utf8)).isEmpty)
        XCTAssertTrue(TranscriptIndex.parseJSON3(Data()).isEmpty)
    }

    // MARK: - Moments

    func testMomentPastedTextIsSelfContained() {
        let moment = YouTubeMoment(videoID: "dQw4w9WgXcQ", timestamp: 764, excerpt: "The tool call returns a result.",
                                   chapter: "Tool Calls")
        XCTAssertEqual(moment.timecode, "12:44")
        let text = moment.pastedText(title: "Agent Loops, Explained")
        XCTAssertTrue(text.contains("★ YouTube Moment • 12:44"))
        XCTAssertTrue(text.contains("Video: Agent Loops, Explained"))
        XCTAssertTrue(text.contains("Chapter: Tool Calls"))
        XCTAssertTrue(text.contains("watch?v=dQw4w9WgXcQ&t=764s"))
        XCTAssertTrue(text.contains("Quote: “The tool call returns a result.”"))
    }

    func testMomentOmitsWhatItDoesNotKnow() {
        let moment = YouTubeMoment(videoID: "dQw4w9WgXcQ", timestamp: 5, excerpt: "", chapter: nil)
        let text = moment.pastedText(title: "")
        XCTAssertFalse(text.contains("Video:"))
        XCTAssertFalse(text.contains("Chapter:"))
        XCTAssertFalse(text.contains("Quote:"), "an empty quote must not be presented as a caption")
        XCTAssertTrue(text.contains("★ YouTube Moment • 0:05"))
    }

    // MARK: - Records and the library

    private func record(_ id: String,
                        fetched: Date = Date(timeIntervalSince1970: 1_700_000_000),
                        entries: [TranscriptEntry] = [],
                        moments: [YouTubeMoment] = []) -> YouTubeTranscriptRecord {
        YouTubeTranscriptRecord(videoID: id, title: "Video \(id)", trackLanguage: "en",
                                trackIsAutoGenerated: false, fetchedAt: fetched,
                                entries: entries, moments: moments)
    }

    func testRecordProvenanceNamesTheTrackHonestly() {
        var manual = record("aaaaaaaaaaa")
        manual.trackIsAutoGenerated = false
        XCTAssertEqual(manual.provenance, "en · captions")

        var auto = record("aaaaaaaaaaa")
        auto.trackLanguage = ""
        auto.trackIsAutoGenerated = true
        XCTAssertEqual(auto.provenance, "unknown language · auto-generated captions")
    }

    func testRecordValidationRefusesBadData() {
        var future = record("aaaaaaaaaaa")
        future.schemaVersion = 2
        XCTAssertThrowsError(try future.validate())

        var badID = record("has a space")
        badID.schemaVersion = YouTubeTranscriptRecord.currentSchemaVersion
        XCTAssertThrowsError(try badID.validate())

        var longTitle = record("aaaaaaaaaaa")
        longTitle.title = String(repeating: "t", count: YouTubePolicy.maximumTitle + 1)
        XCTAssertThrowsError(try longTitle.validate())

        XCTAssertThrowsError(try record("aaaaaaaaaaa",
                                        entries: [TranscriptEntry(timestamp: .nan, timeString: "0:00", text: "x")]).validate())

        XCTAssertNoThrow(try record("aaaaaaaaaaa", entries: sample).validate())
    }

    func testLibraryFindsAndOrdersRecords() {
        let older = record("aaaaaaaaaaa", fetched: Date(timeIntervalSince1970: 100))
        let newer = record("bbbbbbbbbbb", fetched: Date(timeIntervalSince1970: 200))
        let library = YouTubeTranscriptLibrary(records: [older, newer])
        XCTAssertEqual(library.count, 2)
        XCTAssertEqual(library.records.first?.videoID, "bbbbbbbbbbb", "newest first")
        XCTAssertEqual(library.record(for: "aaaaaaaaaaa")?.videoID, "aaaaaaaaaaa")
        XCTAssertNil(library.record(for: "ccccccccccc"))
    }

    func testLibraryDropsUnusableFiles() {
        var broken = record("ccccccccccc")
        broken.schemaVersion = 99
        let library = YouTubeTranscriptLibrary(records: [record("aaaaaaaaaaa"), broken])
        XCTAssertEqual(library.count, 1)
        XCTAssertEqual(library.records.first?.videoID, "aaaaaaaaaaa")
    }

    func testLibraryUpsertReplacesAndEvicts() {
        var library = YouTubeTranscriptLibrary()
        library.upsert(record("aaaaaaaaaaa", fetched: Date(timeIntervalSince1970: 100)))
        var replacement = record("aaaaaaaaaaa", fetched: Date(timeIntervalSince1970: 300), entries: sample)
        replacement.title = "Replaced"
        let evicted = library.upsert(replacement)
        XCTAssertTrue(evicted.isEmpty)
        XCTAssertEqual(library.count, 1, "the same video is replaced, never duplicated")
        XCTAssertEqual(library.record(for: "aaaaaaaaaaa")?.title, "Replaced")
        XCTAssertEqual(library.record(for: "aaaaaaaaaaa")?.entries.count, sample.count)
    }

    func testLibraryEvictsTheLeastRecentlyFetched() {
        var library = YouTubeTranscriptLibrary()
        let total = YouTubePolicy.maximumVideos + 5
        for index in 0..<total {
            let id = String(format: "v%011d", index)
            library.upsert(record(id, fetched: Date(timeIntervalSince1970: Double(index))))
        }
        XCTAssertEqual(library.count, YouTubePolicy.maximumVideos)
        XCTAssertNotNil(library.record(for: String(format: "v%011d", total - 1)))
        XCTAssertNil(library.record(for: "v00000000000"), "the oldest transcript is the one evicted")
        XCTAssertEqual(library.records.first?.videoID, String(format: "v%011d", total - 1))
    }

    func testLibraryRemove() {
        var library = YouTubeTranscriptLibrary(records: [record("aaaaaaaaaaa")])
        XCTAssertTrue(library.remove(videoID: "aaaaaaaaaaa"))
        XCTAssertFalse(library.remove(videoID: "aaaaaaaaaaa"))
        XCTAssertTrue(library.records.isEmpty)
    }

    func testLibraryMomentHandling() {
        var library = YouTubeTranscriptLibrary(records: [record("aaaaaaaaaaa")])
        let moment = YouTubeMoment(videoID: "aaaaaaaaaaa", timestamp: 764, excerpt: "quote")
        XCTAssertTrue(library.addMoment(moment))
        XCTAssertEqual(library.moments(for: "aaaaaaaaaaa").count, 1)
        XCTAssertEqual(library.totalMoments, 1)

        let stranger = YouTubeMoment(videoID: "bbbbbbbbbbb", timestamp: 1, excerpt: "quote")
        XCTAssertFalse(library.addMoment(stranger), "a Moment without a stored transcript cannot be filed")

        for index in 0..<(YouTubePolicy.maximumMomentsPerVideo + 20) {
            library.addMoment(YouTubeMoment(videoID: "aaaaaaaaaaa", timestamp: Double(index), excerpt: "q"))
        }
        XCTAssertEqual(library.record(for: "aaaaaaaaaaa")?.moments.count, YouTubePolicy.maximumMomentsPerVideo)
    }

    func testRecordMomentLookups() {
        let moments = [
            YouTubeMoment(videoID: "aaaaaaaaaaa", timestamp: 10, excerpt: "first"),
            YouTubeMoment(videoID: "aaaaaaaaaaa", timestamp: 900, excerpt: "last")
        ]
        let rec = record("aaaaaaaaaaa", moments: moments)
        XCTAssertEqual(rec.recentMoments.first?.excerpt, "last", "newest first")
        XCTAssertEqual(rec.moment(nearest: 12)?.excerpt, "first")
        XCTAssertEqual(rec.moment(nearest: 890)?.excerpt, "last")
        XCTAssertNil(record("aaaaaaaaaaa").moment(nearest: 10))
    }

    // MARK: - Cadence

    func testCadenceStaysIdleWithoutASession() {
        XCTAssertNil(YouTubeCadence.interval(foreground: true, state: .playing, hasSession: false))
        XCTAssertNil(YouTubeCadence.interval(foreground: false, state: .playing, hasSession: true, screenAwake: false),
                     "a sleeping display is not worth polling")
        XCTAssertNil(YouTubeCadence.interval(foreground: false, state: .unavailable, hasSession: true),
                     "a refused probe is retried by the user, not by a timer")
        XCTAssertNotNil(YouTubeCadence.interval(foreground: true, state: .unavailable, hasSession: true))
    }

    func testCadenceRespondsToPlaybackAndFocus() {
        XCTAssertEqual(YouTubeCadence.interval(foreground: true, state: .playing, hasSession: true), 0.25)
        XCTAssertEqual(YouTubeCadence.interval(foreground: false, state: .playing, hasSession: true), 1.0)
        XCTAssertEqual(YouTubeCadence.interval(foreground: true, state: .live, hasSession: true), 0.25)
        XCTAssertEqual(YouTubeCadence.interval(foreground: true, state: .paused, hasSession: true), 1.0)
        XCTAssertEqual(YouTubeCadence.interval(foreground: false, state: .paused, hasSession: true), 2.5)
        XCTAssertEqual(YouTubeCadence.interval(foreground: false, state: .unknown, hasSession: true), 2.5)
        XCTAssertEqual(YouTubeCadence.interval(foreground: true, state: .ad, hasSession: true), 0.5)
        XCTAssertEqual(YouTubeCadence.interval(foreground: true, state: .ended, hasSession: true), 5.0)
    }

    func testForegroundPollingIsAlwaysAtLeastAsFrequent() {
        for state in [YouTubePlaybackState.unknown, .playing, .paused, .ended, .ad, .live, .unavailable] {
            let front = YouTubeCadence.interval(foreground: true, state: state, hasSession: true)
            let back = YouTubeCadence.interval(foreground: false, state: state, hasSession: true)
            if let front = front, let back = back {
                XCTAssertLessThanOrEqual(front, back, "\(state) must not poll faster in the background")
            }
            if let front = front { XCTAssertGreaterThanOrEqual(front, 0.25) }
        }
    }

    // MARK: - Clock

    func testClockRefusesToDisplayATimeItNeverSaw() {
        let clock = YouTubeSessionClock(time: nil, state: .playing, duration: nil)
        XCTAssertFalse(clock.hasSample)
        XCTAssertNil(clock.displayTime(), "no sample means no clock")
        XCTAssertEqual(clock.displayTimecode(), "—")
    }

    func testClockOnlyAdvancesWhilePlaying() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let playing = YouTubeSessionClock(time: 100, state: .playing, duration: 600, at: start)
        XCTAssertEqual(playing.displayTime(at: start.addingTimeInterval(2))!, 102, accuracy: 0.001)

        let paused = YouTubeSessionClock(time: 100, state: .paused, duration: 600, at: start)
        XCTAssertEqual(paused.displayTime(at: start.addingTimeInterval(30))!, 100, accuracy: 0.001,
                       "a paused video's playhead does not move")

        let ad = YouTubeSessionClock(time: 100, state: .ad, duration: 600, at: start)
        XCTAssertEqual(ad.displayTime(at: start.addingTimeInterval(30))!, 100, accuracy: 0.001)

        let unknown = YouTubeSessionClock(time: 100, state: .unknown, duration: 600, at: start)
        XCTAssertEqual(unknown.displayTime(at: start.addingTimeInterval(30))!, 100, accuracy: 0.001)
    }

    func testClockNeverRunsPastTheVideo() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = YouTubeSessionClock(time: 595, state: .playing, duration: 600, at: start)
        XCTAssertEqual(clock.displayTime(at: start.addingTimeInterval(60))!, 600, accuracy: 0.001)

        let unmatched = YouTubeSessionClock(time: 595, state: .playing, duration: nil, at: start)
        XCTAssertEqual(unmatched.displayTime(at: start.addingTimeInterval(60))!, 655, accuracy: 0.001,
                       "an unknown duration cannot be used to clamp")
    }

    func testClockTimeTravelAndResync() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = YouTubeSessionClock(time: 100, state: .playing, duration: 600, at: start)
        // A clock is not permitted to run backwards if the system date moves back.
        XCTAssertEqual(clock.displayTime(at: start.addingTimeInterval(-30))!, 100, accuracy: 0.001)
    }

    func testAdoptingASampleResyncsAndKeepsTheLastGoodAnchor() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = YouTubeSessionClock(time: 100, state: .playing, duration: 600, at: start)

        let resynced = clock.adopting(YouTubePlaybackMetrics(state: .playing, currentTime: 103,
                                                             duration: 600, volume: 50), at: start.addingTimeInterval(3))
        XCTAssertEqual(resynced.anchorTime!, 103, accuracy: 0.001)
        XCTAssertEqual(resynced.state, .playing)

        // A probe that could not read a time must not blank or rewind the clock.
        let degraded = resynced.adopting(YouTubePlaybackMetrics(state: .paused, currentTime: nil, duration: nil),
                                         at: start.addingTimeInterval(10))
        XCTAssertEqual(degraded.anchorTime!, 103, accuracy: 0.001)
        XCTAssertEqual(degraded.duration!, 600, accuracy: 0.001)
        XCTAssertEqual(degraded.state, .paused, "the state is still adopted honestly")
        XCTAssertEqual(degraded.displayTime(at: start.addingTimeInterval(20))!, 103, accuracy: 0.001)
    }

    func testSettleWindowIsShortButNonZero() {
        XCTAssertGreaterThan(YouTubeSessionClockPolicy.settleWindow, 0)
        XCTAssertLessThanOrEqual(YouTubeSessionClockPolicy.settleWindow, 2)
    }

    // MARK: - Local storage

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("relaybar-youtube-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return url
    }

    func testStoreRoundTrip() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try YouTubeTranscriptStore(directory: directory)
        XCTAssertTrue(store.isEmptyOnDisk)

        var rec = record("dQw4w9WgXcQ", entries: sample)
        rec.moments = [YouTubeMoment(videoID: "dQw4w9WgXcQ", timestamp: 60, excerpt: "The tool call returns a result.")]
        rec.lastPosition = 61.5
        try store.save(rec)

        let loaded = try store.load(videoID: "dQw4w9WgXcQ")
        XCTAssertEqual(loaded?.entries.count, sample.count)
        XCTAssertEqual(loaded?.entries.first?.text, sample.first?.text)
        XCTAssertEqual(loaded?.moments.count, 1)
        XCTAssertEqual(loaded?.lastPosition, 61.5)
        XCTAssertFalse(store.isEmptyOnDisk)
    }

    func testStoreIsPerVideoAndCaseSensitive() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try YouTubeTranscriptStore(directory: directory)
        try store.save(record("abcDEF"))
        try store.save(record("ABCdef"))
        XCTAssertEqual(try store.storedVideoIDs().sorted(), ["ABCdef", "abcDEF"])
        XCTAssertNotEqual(store.recordURL(for: "abcDEF"), store.recordURL(for: "ABCdef"),
                          "APFS is case-insensitive, so the file names must not collide")
    }

    func testStoreRefusesInvalidRecords() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try YouTubeTranscriptStore(directory: directory)
        var future = record("aaaaaaaaaaa")
        future.schemaVersion = 7
        XCTAssertThrowsError(try store.save(future))
        XCTAssertTrue(store.isEmptyOnDisk, "a refused write leaves nothing behind")
    }

    func testStoreDeleteAndDeleteAll() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try YouTubeTranscriptStore(directory: directory)
        try store.save(record("aaaaaaaaaaa"))
        try store.save(record("bbbbbbbbbbb"))

        XCTAssertTrue(try store.delete(videoID: "aaaaaaaaaaa"))
        XCTAssertFalse(try store.delete(videoID: "aaaaaaaaaaa"))
        XCTAssertNil(try store.load(videoID: "aaaaaaaaaaa"))
        XCTAssertEqual(try store.deleteAll(), 1)
        XCTAssertTrue(store.isEmptyOnDisk)
    }

    func testStoreLibraryIsNewestFirst() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try YouTubeTranscriptStore(directory: directory)
        try store.save(record("aaaaaaaaaaa", fetched: Date(timeIntervalSince1970: 100)))
        try store.save(record("bbbbbbbbbbb", fetched: Date(timeIntervalSince1970: 200)))
        let library = try store.loadLibrary()
        XCTAssertEqual(library.records.map(\.videoID), ["bbbbbbbbbbb", "aaaaaaaaaaa"])
    }

    func testStoreCreatesAPrivateDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try YouTubeTranscriptStore(directory: directory)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testStoreRefusesToDeleteSomethingThatIsNotATranscriptFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try YouTubeTranscriptStore(directory: directory)
        let decoy = store.recordURL(for: "aaaaaaaaaaa")
        try FileManager.default.createDirectory(at: decoy, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.delete(videoID: "aaaaaaaaaaa"),
                             "a directory in the store is never removed")
        XCTAssertEqual(try store.deleteAll(), 0)
    }

    // MARK: - Policy sanity

    func testPolicyBoundsAreSane() {
        XCTAssertGreaterThan(YouTubePolicy.maximumEntriesPerVideo, 100)
        XCTAssertGreaterThan(YouTubePolicy.maximumVideos, 1)
        XCTAssertGreaterThan(YouTubePolicy.maximumMomentsPerVideo, 1)
        XCTAssertGreaterThan(YouTubePolicy.excerptWindow, 0)
        XCTAssertGreaterThan(YouTubePolicy.searchLimit, 0)
        XCTAssertGreaterThan(YouTubePolicy.maximumTranscriptCharacters, 0)
    }
}

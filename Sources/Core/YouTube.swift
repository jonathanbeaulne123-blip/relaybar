import Foundation

// YouTube — pure policy, no AppKit, no network, no process.
//
// Everything that decides *what is true* about a playing video lives here so it
// can be tested without a browser. The Mac adapter is only allowed to fetch a
// payload and render the result.
//
// Hard rule for this file: it never invents playback state. A missing sample
// stays missing (`nil`), an unreadable page stays `.unavailable`, and a clock
// with no real anchor refuses to display a time rather than extrapolating from
// a default. Every previous "?? true" / "?? 300" style fallback is deliberately
// absent, and the tests assert that.

public enum YouTubePolicy {
    /// A video's transcript is bounded; long videos are refused, not truncated.
    public static let maximumTranscriptCharacters = 400_000
    public static let maximumEntriesPerVideo = 4_000
    /// How many videos may be cached locally before least-recently-fetched wins.
    public static let maximumVideos = 200
    public static let maximumMomentsPerVideo = 100
    public static let maximumExcerptCharacters = 8_000
    /// Seconds either side of the playhead used when quoting a transcript.
    public static let excerptWindow: Double = 90
    public static let searchLimit = 40
    public static let maximumTitle = 300
    public static let maximumSearchQuery = 120
}

// MARK: - Video identity

public struct YouTubeVideoID: Equatable, Hashable, Codable, CustomStringConvertible {
    public let raw: String

    public init?(raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64,
              trimmed.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value != 127 }),
              trimmed.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        self.raw = trimmed
    }

    public var description: String { raw }

    /// Accepts /watch?v=, youtu.be/, /shorts/ and /embed/. Returns nil rather
    /// than guessing when the URL is not a watch page.
    public static func parse(url: String) -> YouTubeVideoID? {
        guard !url.isEmpty, url.count <= 4096,
              let components = URLComponents(string: url),
              let host = components.host?.lowercased() else { return nil }
        guard host == "youtu.be" || host.hasSuffix(".youtu.be") || host == "youtube.com"
                || host.hasSuffix(".youtube.com") || host == "youtube-nocookie.com"
                || host.hasSuffix(".youtube-nocookie.com") else { return nil }
        if let value = components.queryItems?.first(where: { $0.name == "v" })?.value,
           let id = YouTubeVideoID(raw: value) {
            return id
        }
        let parts = components.path.split(separator: "/").map(String.init)
        switch parts.first {
        case "shorts", "embed", "live", "v":
            guard parts.count >= 2 else { return nil }
            return YouTubeVideoID(raw: parts[1])
        case .some:
            // A short link carries the identifier as its whole path: youtu.be/<id>.
            if host == "youtu.be" || host.hasSuffix(".youtu.be") {
                return YouTubeVideoID(raw: parts[0])
            }
            return nil
        case .none:
            return nil
        }
    }

    public var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(raw)") }

    public func shareURL(at seconds: Double) -> URL? {
        let clamped = max(0, Int(seconds.rounded(.down)))
        return URL(string: "https://www.youtube.com/watch?v=\(raw)&t=\(clamped)s")
    }

    public static func isWatchPage(_ url: String) -> Bool { parse(url: url) != nil }
}

// MARK: - Playback state

public enum YouTubePlaybackState: String, Codable, Equatable {
    case unknown
    case playing
    case paused
    case ended
    case ad
    case live
    case unavailable

    /// True only for states where the playhead is genuinely advancing.
    public var isAdvancing: Bool { self == .playing || self == .live }

    public var shortLabel: String {
        switch self {
        case .unknown: return "…"
        case .playing: return "PLAYING"
        case .paused: return "PAUSED"
        case .ended: return "ENDED"
        case .ad: return "AD"
        case .live: return "LIVE"
        case .unavailable: return "NO CONTROL"
        }
    }
}

/// One real observation of the page. Every field except `state` is optional on
/// purpose: unknown is representable, and therefore never needs inventing.
public struct YouTubePlaybackMetrics: Equatable {
    public var state: YouTubePlaybackState
    public var currentTime: Double?
    public var duration: Double?
    public var volume: Int?
    public var isMuted: Bool?
    public var videoID: YouTubeVideoID?
    public var title: String?
    public var chapter: String?

    public init(state: YouTubePlaybackState,
                currentTime: Double? = nil,
                duration: Double? = nil,
                volume: Int? = nil,
                isMuted: Bool? = nil,
                videoID: YouTubeVideoID? = nil,
                title: String? = nil,
                chapter: String? = nil) {
        self.state = state
        self.currentTime = currentTime
        self.duration = duration
        self.volume = volume
        self.isMuted = isMuted
        self.videoID = videoID
        self.title = title
        self.chapter = chapter
    }

    public var formattedTime: String? {
        guard let time = currentTime else { return nil }
        return YouTubeTimecode.format(time)
    }
}

/// The outcome of one probe of the page. Failure modes are explicit so the UI
/// can explain what happened instead of displaying confident nonsense.
public enum YouTubeProbeResult: Equatable {
    case metrics(YouTubePlaybackMetrics)
    /// Chrome refused scripted control (Allow JavaScript from Apple Events).
    case scriptingDisabled
    /// The tab exists but is not a watch page any more.
    case noVideo
    /// The page answered, but not in a shape this version understands.
    case malformed(String)

    public var metrics: YouTubePlaybackMetrics? {
        if case .metrics(let value) = self { return value }
        return nil
    }
}

/// Whether RelayBar can actually read and control the page. Kept explicit so a
/// blocked browser produces an explanation instead of a confident-looking bar.
public enum YouTubeControlAvailability: Equatable {
    /// A video was found and scripted control works.
    case ready
    /// A watch page is open but Chrome refused `execute javascript`. Chrome
    /// disables this by default (View → Developer → Allow JavaScript from Apple
    /// Events), so it is a setup problem, not a failure.
    case scriptingDisabled
    /// No watch page is open.
    case noSession

    public var setupRequired: Bool { self == .scriptingDisabled }

    public var buttonTitle: String {
        switch self {
        case .ready: return "YouTube"
        case .scriptingDisabled: return "Enable control"
        case .noSession: return "YouTube"
        }
    }

    public var status: String {
        switch self {
        case .ready:
            return "Playing in Chrome."
        case .scriptingDisabled:
            return "Chrome is blocking scripted control. Open Chrome → View → Developer → Allow JavaScript from Apple Events, then tap Retry. RelayBar will not guess at playback until then."
        case .noSession:
            return "No YouTube watch page is open."
        }
    }

    /// The exact guidance shown in the setup panel. Deliberately names Chrome's
    /// own menu path so the instruction cannot drift.
    public static let setupInstructions = """
    1. Open Google Chrome.
    2. Choose View → Developer → Allow JavaScript from Apple Events.
    3. Return to RelayBar and tap Retry.

    RelayBar needs this to read the playhead and to send play, pause, mute and seek \
    to the playing tab. It reads only the video's own player state: no account data, \
    no cookies, no history, and no page text beyond the caption track you ask for.
    """
}

public enum YouTubeProbe {
    /// Wire format produced in-page. Versioned so an older RelayBar can refuse a
    /// newer payload instead of misreading it.
    /// `rby1|state|time|duration|volume|muted|videoId|title|chapter`
    public static let wireVersion = "rby1"
    public static let unavailableToken = "rby-unavailable"
    public static let noVideoToken = "rby-no-video"

    public static func parse(payload: String) -> YouTubeProbeResult {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .noVideo }
        if text == unavailableToken { return .scriptingDisabled }
        if text == noVideoToken { return .noVideo }
        let parts = text.components(separatedBy: "|")
        guard let version = parts.first, version == wireVersion else {
            return .malformed("Unsupported probe payload.")
        }
        guard parts.count >= 3 else { return .malformed("Truncated probe payload.") }
        guard let state = YouTubePlaybackState(rawValue: parts[1]) else {
            return .malformed("Unknown playback state “\(sanitize(parts[1]))”.")
        }
        func number(_ index: Int) -> Double? {
            guard index < parts.count else { return nil }
            let value = parts[index].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, value != "-", let parsed = Double(value), parsed.isFinite else { return nil }
            return parsed
        }
        func string(_ index: Int) -> String? {
            guard index < parts.count else { return nil }
            let value = parts[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != "-" else { return nil }
            return String(value.prefix(YouTubePolicy.maximumTitle))
        }
        let volume: Int?
        if let raw = number(4) { volume = min(100, max(0, Int(raw.rounded()))) } else { volume = nil }
        let muted: Bool?
        switch string(5) {
        case "true": muted = true
        case "false": muted = false
        default: muted = nil
        }
        return .metrics(YouTubePlaybackMetrics(
            state: state,
            currentTime: number(2).map { max(0, $0) },
            duration: number(3).map { max(0, $0) },
            volume: volume,
            isMuted: muted,
            videoID: string(6).flatMap { YouTubeVideoID(raw: $0) },
            title: string(7),
            chapter: string(8)
        ))
    }

    private static func sanitize(_ text: String) -> String {
        String(text.filter { $0.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 } }.prefix(40))
    }
}

// MARK: - Tab selection

public enum YouTubeTabSelector {
    /// Deterministic and explainable, in this order:
    /// 1. the active tab, when it is a watch page;
    /// 2. the tab that still holds the video we were tracking;
    /// 3. the only watch page, or the first one in tab order.
    public static func pick(tabs: [BrowserTab], lastVideoID: YouTubeVideoID?) -> BrowserTab? {
        let watchTabs = tabs.filter { YouTubeVideoID.isWatchPage($0.url) }
        guard !watchTabs.isEmpty else { return nil }
        if let active = watchTabs.first(where: { $0.isSelected }) { return active }
        if let last = lastVideoID {
            if let match = watchTabs.first(where: { YouTubeVideoID.parse(url: $0.url) == last }) { return match }
        }
        return watchTabs.first
    }
}

// MARK: - Timecode

public enum YouTubeTimecode {
    /// `h:mm:ss` past an hour, otherwise `m:ss`. Returns "—" only when asked to,
    /// so callers decide how to present an unknown time.
    public static func format(_ seconds: Double, unknown: String = "—") -> String {
        guard seconds.isFinite, seconds >= 0 else { return unknown }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    public static func format(_ seconds: Double?) -> String {
        guard let seconds = seconds else { return "—" }
        return format(seconds)
    }

    /// Parses `m:ss`, `h:mm:ss` or a bare number of seconds from a transcript row.
    public static func parse(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total: Double = 0
        for part in parts {
            guard let value = Double(part.trimmingCharacters(in: .whitespaces)), value.isFinite, value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

// MARK: - Chapters

public struct YouTubeChapter: Equatable, Codable {
    public var start: Double
    public var title: String
    public init(start: Double, title: String) {
        self.start = start
        self.title = title
    }
    public var timecode: String { YouTubeTimecode.format(start) }
}

public struct YouTubeChapterIndex: Equatable, Codable {
    public private(set) var chapters: [YouTubeChapter]

    public init(chapters: [YouTubeChapter] = []) {
        // Sorted and deduplicated by start, so a malformed page cannot produce
        // an out-of-order timeline.
        var seen = Set<Double>()
        self.chapters = chapters
            .filter { $0.start.isFinite && $0.start >= 0 && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
            .filter { seen.insert($0.start).inserted }
    }

    /// Payload is one `seconds:title` per line, as produced in-page.
    public init(payload: String) {
        var parsed: [YouTubeChapter] = []
        for line in payload.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let separator = trimmed.firstIndex(of: ":") else { continue }
            let head = String(trimmed[trimmed.startIndex..<separator])
            let title = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let start = Double(head), start.isFinite, start >= 0, !title.isEmpty else { continue }
            parsed.append(YouTubeChapter(start: start, title: String(title.prefix(YouTubePolicy.maximumTitle))))
        }
        self.init(chapters: parsed)
    }

    public var isEmpty: Bool { chapters.isEmpty }
    public var count: Int { chapters.count }

    /// The chapter containing `time`, or nil before the first chapter starts.
    public func chapter(at time: Double) -> YouTubeChapter? {
        guard time.isFinite, time >= 0 else { return nil }
        var result: YouTubeChapter?
        for chapter in chapters where chapter.start <= time { result = chapter }
        return result
    }

    public func next(after time: Double) -> YouTubeChapter? {
        guard time.isFinite else { return nil }
        return chapters.first { $0.start > time + 0.5 }
    }

    public func previous(before time: Double) -> YouTubeChapter? {
        guard time.isFinite else { return nil }
        return chapters.last { $0.start < time - 3 }
    }

    public func label(at time: Double) -> String? { chapter(at: time)?.title }
}

// MARK: - Transcript

public struct TranscriptEntry: Equatable, Codable {
    public let timestamp: Double
    public let timeString: String
    public let text: String

    public init(timestamp: Double, timeString: String, text: String) {
        self.timestamp = timestamp
        self.timeString = timeString
        self.text = text
    }

    /// Builds an entry from a raw cue, deriving the display timecode. Refuses
    /// empty text so a caption track cannot inject blank rows.
    public init?(timestamp: Double, text: String) {
        let cleaned = TranscriptIndex.normalize(text)
        guard !cleaned.isEmpty, timestamp.isFinite, timestamp >= 0 else { return nil }
        self.timestamp = timestamp
        self.timeString = YouTubeTimecode.format(timestamp)
        self.text = cleaned
    }
}

public struct TranscriptTrack: Equatable, Codable {
    public var languageCode: String
    public var name: String
    public var isAutoGenerated: Bool
    public var url: String

    public init(languageCode: String, name: String, isAutoGenerated: Bool, url: String) {
        self.languageCode = languageCode
        self.name = name
        self.isAutoGenerated = isAutoGenerated
        self.url = url
    }

    /// Auto-generated English usually reports `asr` in the track name.
    public static func autoGenerated(languageCode: String, name: String) -> Bool {
        name.lowercased().contains("auto-generated") || languageCode.lowercased().hasSuffix("-asr")
    }
}

public struct TranscriptTrackList: Equatable, Codable {
    public private(set) var tracks: [TranscriptTrack]

    public init(tracks: [TranscriptTrack] = []) {
        self.tracks = tracks.filter { !$0.languageCode.isEmpty && !$0.url.isEmpty }
    }

    public var isEmpty: Bool { tracks.isEmpty }

    /// Payload is one `language|name|url` per line, as produced in-page.
    public init(payload: String) {
        var parsed: [TranscriptTrack] = []
        for line in payload.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 3 else { continue }
            let language = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let url = parts[2...].joined(separator: "|").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !language.isEmpty, url.hasPrefix("http") else { continue }
            parsed.append(TranscriptTrack(languageCode: language,
                                          name: name.isEmpty ? language : name,
                                          isAutoGenerated: TranscriptTrack.autoGenerated(languageCode: language, name: name),
                                          url: url))
        }
        self.init(tracks: parsed)
    }

    /// Preference order: the video's own language when known, then a manual
    /// track, then an auto-generated one. Never silently mixes languages.
    public func preferred(preferring language: String?) -> TranscriptTrack? {
        if let language = language?.lowercased(), !language.isEmpty {
            if let exact = tracks.first(where: { $0.languageCode.lowercased() == language }) { return exact }
            let base = language.split(separator: "-").first.map(String.init) ?? language
            if let baseMatch = tracks.first(where: { $0.languageCode.lowercased().hasPrefix(base) && !$0.isAutoGenerated }) { return baseMatch }
        }
        if let manual = tracks.first(where: { !$0.isAutoGenerated }) { return manual }
        return tracks.first
    }

    public func track(languageCode: String) -> TranscriptTrack? {
        tracks.first { $0.languageCode.lowercased() == languageCode.lowercased() }
    }
}

public struct TranscriptMatch: Equatable {
    public var entry: TranscriptEntry
    public var score: Int
    public init(entry: TranscriptEntry, score: Int) {
        self.entry = entry
        self.score = score
    }
}

public enum TranscriptIndex {
    /// Collapses whitespace and strips control characters so search and display
    /// see identical text.
    public static func normalize(_ text: String) -> String {
        let filtered = text.filter { scalar in
            scalar.unicodeScalars.allSatisfy { ($0.value >= 32 || $0.value == 10) && $0.value != 127 }
        }
        return filtered.replacingOccurrences(of: "\t", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func sorted(_ entries: [TranscriptEntry]) -> [TranscriptEntry] {
        entries.sorted { $0.timestamp < $1.timestamp }
    }

    /// The line playing at `time`, or nil before the first line.
    public static func line(at time: Double, in entries: [TranscriptEntry]) -> TranscriptEntry? {
        guard time.isFinite else { return nil }
        var result: TranscriptEntry?
        for entry in entries where entry.timestamp <= time + 0.25 { result = entry }
        return result
    }

    /// The line at or before the playhead — the honest basis for a Moment quote.
    public static func snapped(to time: Double, in entries: [TranscriptEntry]) -> TranscriptEntry? {
        line(at: time, in: entries)
    }

    public static func index(of entry: TranscriptEntry, in entries: [TranscriptEntry]) -> Int? {
        entries.firstIndex { $0.timestamp == entry.timestamp && $0.text == entry.text }
    }

    /// A bounded window of real captions around `time`, with timecodes kept so
    /// the assistant can be told where each line came from.
    public static func excerpt(around time: Double,
                               window: Double = YouTubePolicy.excerptWindow,
                               in entries: [TranscriptEntry]) -> String {
        guard time.isFinite, window > 0, !entries.isEmpty else { return "" }
        let lower = time - window
        let upper = time + window
        let selected = entries.filter { $0.timestamp >= lower && $0.timestamp <= upper }
        guard !selected.isEmpty else { return "" }
        var text = ""
        for entry in selected {
            let line = "[\(entry.timeString)] \(entry.text)\n"
            if text.count + line.count > YouTubePolicy.maximumExcerptCharacters { break }
            text += line
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Deterministic local search. All query tokens must appear; ranking is
    /// occurrence count, then earliest line. No index is built and nothing is
    /// sent anywhere.
    public static func search(_ query: String,
                              in entries: [TranscriptEntry],
                              limit: Int = YouTubePolicy.searchLimit) -> [TranscriptMatch] {
        let trimmed = String(query.prefix(YouTubePolicy.maximumSearchQuery)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0, !entries.isEmpty else { return [] }
        let tokens = trimmed.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        var matches: [TranscriptMatch] = []
        for entry in entries {
            let haystack = entry.text.lowercased()
            var score = 0
            var allPresent = true
            for token in tokens {
                let hits = occurrences(of: token, in: haystack)
                if hits == 0 { allPresent = false; break }
                score += hits
            }
            guard allPresent else { continue }
            // A whole phrase is a stronger signal than loose tokens.
            if tokens.count > 1, haystack.contains(trimmed.lowercased()) { score += tokens.count * 2 }
            matches.append(TranscriptMatch(entry: entry, score: score))
        }
        return matches
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.timestamp < $1.entry.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var start = haystack.startIndex
        while let range = haystack.range(of: needle, range: start..<haystack.endIndex) {
            count += 1
            start = range.upperBound
            if count > 50 { break }
        }
        return count
    }

    /// Total characters, used to enforce the per-video cap before writing.
    public static func characterCount(_ entries: [TranscriptEntry]) -> Int {
        entries.reduce(0) { $0 + $1.text.count }
    }

    /// json3 is YouTube's own caption JSON. Parsing is total: anything it does
    /// not understand is skipped, never guessed at.
    public static func parseJSON3(_ data: Data) -> [TranscriptEntry] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }
        var entries: [TranscriptEntry] = []
        for event in events {
            guard let start = (event["tStartMs"] as? NSNumber)?.doubleValue else { continue }
            let segments = event["segs"] as? [[String: Any]] ?? []
            let text = segments.compactMap { $0["utf8"] as? String }.joined(separator: " ")
            guard let entry = TranscriptEntry(timestamp: start / 1000, text: text) else { continue }
            entries.append(entry)
        }
        return sorted(entries)
    }
}

// MARK: - Moments

public struct YouTubeMoment: Codable, Equatable, Identifiable {
    public var id: UUID
    public var videoID: String
    public var timestamp: Double
    public var excerpt: String
    public var chapter: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), videoID: String, timestamp: Double,
                excerpt: String, chapter: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.videoID = videoID
        self.timestamp = timestamp
        self.excerpt = excerpt
        self.chapter = chapter
        self.createdAt = createdAt
    }

    public var timecode: String { YouTubeTimecode.format(timestamp) }

    /// The shareable, human-readable block. Deliberately plain text so it can be
    /// pasted anywhere without a RelayBar dependency.
    public func pastedText(title: String) -> String {
        var lines = ["★ YouTube Moment • \(timecode)"]
        if !title.isEmpty { lines.append("Video: \(title)") }
        if let chapter = chapter, !chapter.isEmpty { lines.append("Chapter: \(chapter)") }
        if let url = YouTubeVideoID(raw: videoID)?.shareURL(at: timestamp) { lines.append("Link: \(url.absoluteString)") }
        if !excerpt.isEmpty { lines.append("Quote: “\(excerpt)”") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Persisted transcript records

public struct YouTubeTranscriptRecord: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var videoID: String
    public var title: String
    public var trackLanguage: String
    public var trackIsAutoGenerated: Bool
    public var fetchedAt: Date
    public var entries: [TranscriptEntry]
    public var moments: [YouTubeMoment]
    public var lastPosition: Double?

    public init(videoID: String,
                title: String = "",
                trackLanguage: String = "",
                trackIsAutoGenerated: Bool = false,
                fetchedAt: Date = Date(),
                entries: [TranscriptEntry] = [],
                moments: [YouTubeMoment] = [],
                lastPosition: Double? = nil) {
        self.schemaVersion = Self.currentSchemaVersion
        self.videoID = videoID
        self.title = title
        self.trackLanguage = trackLanguage
        self.trackIsAutoGenerated = trackIsAutoGenerated
        self.fetchedAt = fetchedAt
        self.entries = entries
        self.moments = moments
        self.lastPosition = lastPosition
    }

    public var totalCharacters: Int { TranscriptIndex.characterCount(entries) }

    public var provenance: String {
        let language = trackLanguage.isEmpty ? "unknown language" : trackLanguage
        let kind = trackIsAutoGenerated ? "auto-generated captions" : "captions"
        return "\(language) · \(kind)"
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw RelayError.invalid("Unsupported transcript version. Nothing was changed.")
        }
        guard YouTubeVideoID(raw: videoID) != nil else {
            throw RelayError.invalid("The transcript record has an invalid video identifier.")
        }
        guard entries.count <= YouTubePolicy.maximumEntriesPerVideo else {
            throw RelayError.invalid("The transcript has more than \(YouTubePolicy.maximumEntriesPerVideo) lines. Nothing was changed.")
        }
        guard totalCharacters <= YouTubePolicy.maximumTranscriptCharacters else {
            throw RelayError.invalid("The transcript exceeds \(YouTubePolicy.maximumTranscriptCharacters) characters. Nothing was changed.")
        }
        guard moments.count <= YouTubePolicy.maximumMomentsPerVideo else {
            throw RelayError.invalid("This video has more than \(YouTubePolicy.maximumMomentsPerVideo) saved Moments. Nothing was changed.")
        }
        guard title.count <= YouTubePolicy.maximumTitle else {
            throw RelayError.invalid("The transcript title is too long.")
        }
        for entry in entries where !entry.timestamp.isFinite || entry.timestamp < 0 {
            throw RelayError.invalid("The transcript contains a line with an invalid timecode. Nothing was changed.")
        }
    }

    /// Moments as they should be shown: newest first, capped.
    public var recentMoments: [YouTubeMoment] {
        Array(moments.sorted { $0.timestamp > $1.timestamp }.prefix(YouTubePolicy.maximumMomentsPerVideo))
    }

    public func moment(nearest time: Double) -> YouTubeMoment? {
        moments.min { abs($0.timestamp - time) < abs($1.timestamp - time) }
    }
}

/// The on-disk library, with the retention rules applied in one place so the
/// Mac layer never has to reason about caps.
public struct YouTubeTranscriptLibrary: Equatable {
    public private(set) var records: [YouTubeTranscriptRecord]

    public init(records: [YouTubeTranscriptRecord] = []) {
        self.records = records
            .filter { (try? $0.validate()) != nil }
            .sorted { $0.fetchedAt > $1.fetchedAt }
    }

    public var count: Int { records.count }
    public var totalCharacters: Int { records.reduce(0) { $0 + $1.totalCharacters } }
    public var totalMoments: Int { records.reduce(0) { $0 + $1.moments.count } }

    public func record(for videoID: String) -> YouTubeTranscriptRecord? {
        records.first { $0.videoID == videoID }
    }

    public func moments(for videoID: String) -> [YouTubeMoment] {
        record(for: videoID)?.recentMoments ?? []
    }

    /// Inserts or replaces a record and returns the video identifiers that had to
    /// be evicted to stay inside the retention cap.
    @discardableResult
    public mutating func upsert(_ record: YouTubeTranscriptRecord) -> [String] {
        var next = records.filter { $0.videoID != record.videoID }
        next.append(record)
        next.sort { $0.fetchedAt > $1.fetchedAt }
        var evicted: [String] = []
        while next.count > YouTubePolicy.maximumVideos {
            evicted.append(next.removeLast().videoID)
        }
        records = next
        return evicted
    }

    @discardableResult
    public mutating func remove(videoID: String) -> Bool {
        let before = records.count
        records.removeAll { $0.videoID == videoID }
        return records.count != before
    }

    @discardableResult
    public mutating func addMoment(_ moment: YouTubeMoment) -> Bool {
        guard let index = records.firstIndex(where: { $0.videoID == moment.videoID }) else { return false }
        var record = records[index]
        record.moments.append(moment)
        if record.moments.count > YouTubePolicy.maximumMomentsPerVideo {
            record.moments = Array(record.recentMoments.prefix(YouTubePolicy.maximumMomentsPerVideo))
        }
        records[index] = record
        return true
    }
}

// MARK: - Cadence

public enum YouTubeCadence {
    /// How long to wait before probing again, or nil to stay idle. Rules are
    /// stated once here rather than scattered as magic numbers, and the adapter
    /// can only pick from this table.
    public static func interval(foreground: Bool,
                               state: YouTubePlaybackState,
                               hasSession: Bool,
                               screenAwake: Bool = true) -> TimeInterval? {
        guard hasSession, screenAwake else { return nil }
        switch state {
        case .playing, .live:
            return foreground ? 0.25 : 1.0
        case .ad:
            return foreground ? 0.5 : 1.5
        case .paused, .unknown:
            return foreground ? 1.0 : 2.5
        case .ended:
            return 5.0
        case .unavailable:
            // Nothing to poll for: scripted control is refused, so probing harder
            // would only burn cycles. The user's retry is the trigger.
            return foreground ? 4.0 : nil
        }
    }
}

// MARK: - Fabrication-free clock

/// Holds the last *real* sample and can extrapolate between samples. It refuses
/// to render a time when it has never seen one, which is what stops a blocked
/// probe from producing a plausible clock.
public struct YouTubeSessionClock: Equatable {
    public private(set) var anchorTime: Double?
    public private(set) var anchorDate: Date
    public private(set) var state: YouTubePlaybackState
    public private(set) var duration: Double?

    public init(time: Double?, state: YouTubePlaybackState, duration: Double?, at date: Date = Date()) {
        self.anchorTime = time
        self.anchorDate = date
        self.state = state
        self.duration = duration
    }

    public var hasSample: Bool { anchorTime != nil }

    public func displayTime(at date: Date = Date()) -> Double? {
        guard let anchor = anchorTime else { return nil }
        guard state.isAdvancing else { return anchor }
        let elapsed = max(0, date.timeIntervalSince(anchorDate))
        var projected = anchor + elapsed
        if let duration = duration, duration > 0 { projected = min(projected, duration) }
        return projected
    }

    public func displayTimecode(at date: Date = Date()) -> String {
        YouTubeTimecode.format(displayTime(at: date))
    }

    /// Adopts a new real sample. Keeps the previous anchor when the probe could
    /// not read a time, so a single failed probe does not blank the clock.
    public func adopting(_ metrics: YouTubePlaybackMetrics, at date: Date = Date()) -> YouTubeSessionClock {
        YouTubeSessionClock(time: metrics.currentTime ?? anchorTime,
                            state: metrics.state,
                            duration: metrics.duration ?? duration,
                            at: date)
    }
}

public enum YouTubeSessionClockPolicy {
    /// A command we just issued locally should not be contradicted by a probe
    /// that was already in flight. The adapter uses this window to hold off
    /// reconciling until the page has caught up.
    public static let settleWindow: TimeInterval = 0.9
}

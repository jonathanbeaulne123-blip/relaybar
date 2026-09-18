import Cocoa

/// The synchronized transcript viewer.
///
/// Everything it shows comes from the video's own caption track or from a
/// locally stored copy of it. It never rewrites, summarises or invents caption
/// text: the prompt-building buttons copy a *prompt* and leave the transcript
/// untouched, and the footer always names the caption source.
@MainActor
public final class YouTubeTranscriptPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private enum Row {
        case chapter(YouTubeChapter)
        case entry(TranscriptEntry)
    }

    private let tableView = NSTableView()
    private let titleLabel = label("YouTube Transcript", size: 14, weight: .bold)
    private let provenanceLabel = label("", size: 11, secondary: true)
    private let statusLabel = label("", size: 11, secondary: true)
    private let searchField = NSSearchField()
    private let followButton = ActionButton("Follow", help: "Keep the transcript scrolled to the line that is playing", handler: {})

    private var entries: [TranscriptEntry] = []
    private var chapters = YouTubeChapterIndex()
    private var moments: [YouTubeMoment] = []
    private var rows: [Row] = []
    private var searchMatches: [TranscriptMatch] = []
    private var videoTitle = ""
    private var videoID = ""
    private var followsPlayback = true
    private var highlightedEntry: TranscriptEntry?
    private var rangeAnchor: Double?
    private var rangeEnd: Double?

    /// The stored record's own "where you left off", shown as a labelled fact.
    /// It is never used as the live playhead.
    private var lastPosition: Double?

    private var currentTime: (() -> Double?)?
    private var onSeek: ((Double) -> Void)?
    private var onOpenTranscript: (() -> Void)?
    private var onForget: (() -> Void)?
    private var onStar: (() -> Void)?
    private var onSearch: ((String) -> [TranscriptMatch])?

    private var followTimer: Timer?

    public static var shared: YouTubeTranscriptPanel?

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.title = "Video Transcript"
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.level = .floating
        self.center()
        buildContent()
    }

    /// Reuses one window. A second transcript opening replaces the first rather
    /// than stacking, so the panel always describes the video you are on now.
    public static func show(videoTitle: String,
                            videoID: String,
                            provenance: String,
                            chapters: YouTubeChapterIndex,
                            entries: [TranscriptEntry],
                            moments: [YouTubeMoment],
                            lastPosition: Double? = nil,
                            currentTime: @escaping () -> Double?,
                            onSeek: @escaping (Double) -> Void,
                            onOpenTranscript: (() -> Void)? = nil,
                            onForget: (() -> Void)? = nil,
                            onStar: (() -> Void)? = nil,
                            onSearch: @escaping (String) -> [TranscriptMatch]) {
        let panel = shared ?? YouTubeTranscriptPanel()
        shared = panel
        panel.show(videoTitle: videoTitle,
                   videoID: videoID,
                   provenance: provenance,
                   chapters: chapters,
                   entries: entries,
                   moments: moments,
                   lastPosition: lastPosition,
                   currentTime: currentTime,
                   onSeek: onSeek,
                   onOpenTranscript: onOpenTranscript,
                   onForget: onForget,
                   onStar: onStar,
                   onSearch: onSearch)
    }

    private func buildContent() {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        provenanceLabel.lineBreakMode = .byTruncatingTail
        statusLabel.lineBreakMode = .byTruncatingTail

        searchField.placeholderString = "Search this transcript"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        searchField.setAccessibilityLabel("Search this transcript")

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TranscriptCol"))
        column.width = 500
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.setAccessibilityLabel("Timestamped transcript. Tapping a timecode moves playback.")
        scroll.documentView = tableView

        func copyToPasteboard(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        func transcriptText() -> String {
            entries.map { "[\($0.timeString)] \($0.text)" }.joined(separator: "\n")
        }

        let copyAll = ActionButton("Copy all", help: "Copy every timestamped line") { [weak self] in
            guard let self = self else { return }
            copyToPasteboard(transcriptText())
            self.note("Copied \(self.entries.count) lines.")
        }

        let copyExcerpt = ActionButton("Copy excerpt", help: "Copy the caption lines around the playhead, with timecodes") { [weak self] in
            guard let self = self else { return }
            let time = self.currentTime?()
            let text = TranscriptIndex.excerpt(around: time ?? 0, in: self.entries)
            guard !text.isEmpty else { self.note("There are no caption lines near the playhead yet."); return }
            copyToPasteboard(text)
            self.note("Copied the \(Int(YouTubePolicy.excerptWindow))-second excerpt around the playhead.")
        }

        let copyRange = ActionButton("Copy range", help: "Option-click two timecodes, then copy everything between them") { [weak self] in
            guard let self = self else { return }
            guard let start = self.rangeAnchor, let end = self.rangeEnd else {
                self.note("Option-click a first timecode, then click a second one to set a range.")
                return
            }
            let lower = min(start, end)
            let upper = max(start, end)
            let selected = self.entries.filter { $0.timestamp >= lower && $0.timestamp <= upper }
            guard !selected.isEmpty else { self.note("No caption lines fall inside that range."); return }
            copyToPasteboard(selected.map { "[\($0.timeString)] \($0.text)" }.joined(separator: "\n"))
            self.note("Copied \(selected.count) lines between \(YouTubeTimecode.format(lower)) and \(YouTubeTimecode.format(upper)).")
        }

        let open = ActionButton("Open transcript", help: "Open this video's own transcript panel in YouTube") { [weak self] in
            self?.onOpenTranscript?()
            self?.note("Asked YouTube to open its transcript panel.")
        }

        let star = ActionButton("★ Moment", help: "Save the line that is playing now as a Moment") { [weak self] in
            self?.onStar?()
        }

        let forget = ActionButton("Forget", help: "Delete the locally stored transcript and Moments for this video") { [weak self] in
            guard let self = self, !self.videoID.isEmpty else { return }
            let alert = NSAlert()
            alert.messageText = "Delete the stored copy of this transcript?"
            alert.informativeText = "This removes RelayBar's local transcript file and its saved Moments for this video. The video on YouTube is not affected, and nothing is sent anywhere."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Delete local copy")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            self.onForget?()
        }

        // Moments are the part of a transcript that is worth keeping, so they get
        // their own copy action rather than being reachable only one at a time.
        let copyMoments = ActionButton("Copy Moments", help: "Copy every Moment saved for this video, newest first") { [weak self] in
            guard let self = self else { return }
            guard !self.moments.isEmpty else { self.note("No Moments have been saved for this video yet."); return }
            let blocks = self.moments
                .sorted { $0.timestamp < $1.timestamp }
                .map { $0.pastedText(title: self.videoTitle) }
            copyToPasteboard(blocks.joined(separator: "\n\n"))
            self.note("Copied \(blocks.count) Moment\(blocks.count == 1 ? "" : "s").")
        }

        let close = ActionButton("Close") { [weak self] in self?.orderOut(nil) }

        func copyPrompt(_ prompt: String, note: String) {
            copyToPasteboard(prompt)
            statusLabel.stringValue = note
        }

        let summarize = ActionButton("Summarize", help: "Copy a summary prompt built from this transcript") { [weak self] in
            guard let self = self else { return }
            copyPrompt("Summarize the main points and key takeaways of this video from this transcript:\n\n" + String(transcriptText().prefix(8000)),
                       note: "Copied a summary prompt. Paste it into your assistant; nothing was sent.")
        }

        let steps = ActionButton("Extract steps", help: "Copy a prompt that pulls ordered steps out of the transcript") { [weak self] in
            guard let self = self else { return }
            copyPrompt("Extract the concrete steps, commands, or decisions from this transcript as an ordered list. Keep timestamps. Do not invent anything that is not present:\n\n" + String(transcriptText().prefix(8000)),
                       note: "Copied a steps prompt. Paste it into your assistant; nothing was sent.")
        }

        let actions = NSStackView(views: [copyAll, copyExcerpt, copyRange, copyMoments, open, star, forget, close])
        actions.orientation = .horizontal
        actions.spacing = 6
        actions.alignment = .centerY
        actions.setViews([copyAll, copyExcerpt, copyRange, copyMoments, open, star, forget, close], in: .leading)

        let prompts = NSStackView(views: [searchField, followButton, summarize, steps])
        prompts.orientation = .horizontal
        prompts.spacing = 6
        prompts.alignment = .centerY
        prompts.setViews([searchField, followButton, summarize, steps], in: .leading)

        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(provenanceLabel)
        container.addArrangedSubview(prompts)
        container.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28).isActive = true
        container.addArrangedSubview(actions)
        actions.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28).isActive = true
        container.addArrangedSubview(statusLabel)
        container.addArrangedSubview(label("Tap a timecode to move playback. Option-click two timecodes to mark a range. RelayBar reads only this video's own caption track.", size: 11, secondary: true))

        followButton.bezelColor = NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.30, alpha: 1.0)
        followButton.handler = { [weak self] in self?.toggleFollow() }

        self.contentView = container
    }

    // MARK: - Presentation

    public func show(videoTitle: String,
                     videoID: String,
                     provenance: String,
                     chapters: YouTubeChapterIndex,
                     entries: [TranscriptEntry],
                     moments: [YouTubeMoment],
                     lastPosition: Double? = nil,
                     currentTime: @escaping () -> Double?,
                     onSeek: @escaping (Double) -> Void,
                     onOpenTranscript: (() -> Void)? = nil,
                     onForget: (() -> Void)? = nil,
                     onStar: (() -> Void)? = nil,
                     onSearch: @escaping (String) -> [TranscriptMatch]) {
        self.videoTitle = videoTitle
        self.videoID = videoID
        self.chapters = chapters
        self.entries = TranscriptIndex.sorted(entries)
        self.moments = moments
        self.lastPosition = lastPosition
        self.currentTime = currentTime
        self.onSeek = onSeek
        self.onOpenTranscript = onOpenTranscript
        self.onForget = onForget
        self.onStar = onStar
        self.onSearch = onSearch
        self.rangeAnchor = nil
        self.rangeEnd = nil
        self.searchField.stringValue = ""
        self.searchMatches = []
        // The follow-along highlight belongs to the previous video's lines.
        self.highlightedEntry = nil

        titleLabel.stringValue = videoTitle.isEmpty ? "YouTube Transcript" : videoTitle
        provenanceLabel.stringValue = transcriptSummary(provenance: provenance)
        statusLabel.stringValue = ""
        rebuildRows()
        reload(keepSelection: false)
        startFollowing()
        makeKeyAndOrderFront(nil)
        YouTubeTranscriptPanel.shared = self
    }

    private func transcriptSummary(provenance: String) -> String {
        let lines = entries.count
        let chapterText = chapters.isEmpty ? "no chapters" : "\(chapters.count) chapters"
        let momentText = moments.isEmpty ? "no Moments" : "\(moments.count) Moment\(moments.count == 1 ? "" : "s")"
        let source = provenance.isEmpty ? "caption source unknown" : provenance
        var parts = ["\(lines) lines", chapterText, momentText, source]
        // Stated as a property of the stored transcript, not as the playhead.
        if let position = lastPosition { parts.append("last watched \(YouTubeTimecode.format(position))") }
        return parts.joined(separator: " · ")
    }

    public override func orderOut(_ sender: Any?) {
        stopFollowing()
        super.orderOut(sender)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    // MARK: - Rows

    private func rebuildRows() {
        var built: [Row] = []
        if !searchMatches.isEmpty {
            for match in searchMatches { built.append(.entry(match.entry)) }
            rows = built
            return
        }
        var chapterQueue = chapters.chapters
        for entry in entries {
            while let next = chapterQueue.first, next.start <= entry.timestamp {
                built.append(.chapter(next))
                chapterQueue.removeFirst()
            }
            built.append(.entry(entry))
        }
        for leftover in chapterQueue { built.append(.chapter(leftover)) }
        rows = built
    }

    private func reload(keepSelection: Bool) {
        let selected = keepSelection ? tableView.selectedRow : -1
        tableView.reloadData()
        if selected >= 0, selected < rows.count { tableView.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false) }
    }

    private func note(_ message: String) { statusLabel.stringValue = message }

    private func toggleFollow() {
        followsPlayback.toggle()
        followButton.title = followsPlayback ? "Follow" : "Follow off"
        followButton.bezelColor = followsPlayback
            ? NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.30, alpha: 1.0)
            : NSColor(calibratedWhite: 0.22, alpha: 1.0)
        if followsPlayback { startFollowing() } else { stopFollowing() }
    }

    // MARK: - Follow-along

    private func startFollowing() {
        stopFollowing()
        guard followsPlayback else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.followTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func stopFollowing() {
        followTimer?.invalidate()
        followTimer = nil
    }

    private func followTick() {
        guard followsPlayback, searchMatches.isEmpty, let time = currentTime?() else { return }
        guard let line = TranscriptIndex.line(at: time, in: entries) else { return }
        guard line != highlightedEntry else { return }
        highlightedEntry = line
        guard let row = rows.firstIndex(where: { if case .entry(let entry) = $0 { return entry == line }; return false }) else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        tableView.scrollRowToVisible(row)
    }

    // MARK: - Search

    @objc private func searchChanged() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            searchMatches = []
            note("")
        } else {
            searchMatches = onSearch?(query) ?? []
            if searchMatches.isEmpty {
                note("Nothing in this transcript matches “\(query)”.")
            } else {
                note("\(searchMatches.count) line\(searchMatches.count == 1 ? "" : "s") mention “\(query)”. Tap a timecode to jump there.")
            }
        }
        rebuildRows()
        reload(keepSelection: false)
    }

    // MARK: - Table delegate

    public func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .chapter = rows[row] { return true }
        return false
    }

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .chapter = rows[row] { return 26 }
        return 30
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .chapter(let chapter):
            let text = label("\(chapter.timecode)   \(chapter.title.uppercased())", size: 11, weight: .semibold)
            text.textColor = .secondaryLabelColor
            let cell = NSView()
            cell.addSubview(text)
            text.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell

        case .entry(let entry):
            let isPlaying = entry == highlightedEntry
            let timeButton = ActionButton(entry.timeString) { [weak self] in
                guard let self = self else { return }
                if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                    self.rangeAnchor = entry.timestamp
                    self.rangeEnd = nil
                    self.note("Range starts at \(entry.timeString). Now click the end timecode.")
                } else {
                    if self.rangeAnchor != nil { self.rangeEnd = entry.timestamp }
                    self.onSeek?(entry.timestamp)
                    self.note("Moved playback to \(entry.timeString).")
                }
            }
            timeButton.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            timeButton.bezelColor = isPlaying
                ? NSColor(calibratedRed: 0.24, green: 0.34, blue: 0.46, alpha: 1.0)
                : NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.26, alpha: 1.0)
            timeButton.widthAnchor.constraint(equalToConstant: 58).isActive = true

            let text = label(entry.text, size: 12)
            text.lineBreakMode = .byWordWrapping
            text.maximumNumberOfLines = 2
            text.font = isPlaying ? .systemFont(ofSize: 12, weight: .semibold) : .systemFont(ofSize: 12)

            let stack = NSStackView(views: [timeButton, text])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8

            let cell = NSView()
            cell.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }
    }
}

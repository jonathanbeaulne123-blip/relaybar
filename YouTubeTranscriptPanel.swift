import Cocoa

public struct TranscriptEntry: Equatable, Codable {
    public let timestamp: Double
    public let timeString: String
    public let text: String
    
    public init(timestamp: Double, timeString: String, text: String) {
        self.timestamp = timestamp
        self.timeString = timeString
        self.text = text
    }
}

@MainActor
public final class YouTubeTranscriptPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView: NSTableView
    private let titleLabel: NSTextField
    private var entries: [TranscriptEntry] = []
    private var onSeek: ((Double) -> Void)?
    private var onOpenTranscript: (() -> Void)?
    
    public static var shared: YouTubeTranscriptPanel?
    
    public init() {
        self.tableView = NSTableView()
        self.titleLabel = label("YouTube Transcript", size: 14, weight: .bold)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Video Transcript"
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.level = .floating
        self.center()
        
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TranscriptCol"))
        col.width = 480
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 32
        tableView.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        scroll.documentView = tableView
        
        func transcriptText() -> String {
            entries.map { "[\($0.timeString)] \($0.text)" }.joined(separator: "\n")
        }
        func copy(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        let copyAllBtn = ActionButton("Copy all", help: "Copy every timestamped line") { [weak self] in
            guard let self = self else { return }
            copy(transcriptText())
        }

        let openBtn = ActionButton("Open transcript", help: "Open this video's own transcript panel in YouTube") { [weak self] in
            self?.onOpenTranscript?()
        }

        let sendBtn = ActionButton("Send to chat", help: "Copy a draft that asks your assistant to work from this transcript") { [weak self] in
            guard let self = self else { return }
            let prompt = "Here is the timestamped transcript of this video. Use only this text as context:\n\n" + String(transcriptText().prefix(8000))
            copy(prompt)
        }

        let summarizeBtn = ActionButton("Summarize", help: "Copy a summary prompt built from the transcript") { [weak self] in
            guard let self = self else { return }
            let prompt = "Summarize the main points and key takeaways of this video from this transcript:\n\n" + String(transcriptText().prefix(8000))
            copy(prompt)
        }

        let stepsBtn = ActionButton("Extract steps", help: "Copy a prompt that pulls ordered steps out of the transcript") { [weak self] in
            guard let self = self else { return }
            let prompt = "Extract the concrete steps, commands, or decisions from this transcript as an ordered list. Keep timestamps. Do not invent anything not present:\n\n" + String(transcriptText().prefix(8000))
            copy(prompt)
        }

        let findBtn = ActionButton("Find…", help: "Copy a prompt template to locate where a topic is discussed") { [weak self] in
            guard let self = self else { return }
            let prompt = "Using this timestamped transcript, find every place that discusses: [TOPIC]. Quote each line with its timestamp. If it is not mentioned, say so.\n\n" + String(transcriptText().prefix(8000))
            copy(prompt)
        }

        let closeBtn = ActionButton("Close") { [weak self] in
            self?.orderOut(nil)
        }

        let toolbar = NSStackView(views: [copyAllBtn, openBtn, sendBtn, summarizeBtn, stepsBtn, findBtn, closeBtn])
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.alignment = .centerY
        toolbar.setViews([copyAllBtn, openBtn, sendBtn, summarizeBtn, stepsBtn, findBtn, closeBtn], in: .leading)

        let hint = label("Tap any timestamp to jump playback. RelayBar reads only this video's own caption track.", size: 11, secondary: true)

        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(hint)
        container.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28).isActive = true
        container.addArrangedSubview(toolbar)
        toolbar.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28).isActive = true
        
        self.contentView = container
    }
    
    public func update(videoTitle: String, entries: [TranscriptEntry], onSeek: @escaping (Double) -> Void, onOpenTranscript: (() -> Void)? = nil) {
        self.titleLabel.stringValue = videoTitle.isEmpty ? "YouTube Transcript" : videoTitle
        self.entries = entries
        self.onSeek = onSeek
        self.onOpenTranscript = onOpenTranscript
        self.tableView.reloadData()
    }
    
    public static func show(videoTitle: String, entries: [TranscriptEntry], onSeek: @escaping (Double) -> Void, onOpenTranscript: (() -> Void)? = nil) {
        let panel = shared ?? YouTubeTranscriptPanel()
        panel.update(videoTitle: videoTitle, entries: entries, onSeek: onSeek, onOpenTranscript: onOpenTranscript)
        panel.makeKeyAndOrderFront(nil)
        shared = panel
    }
    
    // MARK: - NSTableViewDataSource & Delegate
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return entries.count
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let cell = NSView()
        
        let timeBtn = ActionButton(entry.timeString) { [weak self] in
            self?.onSeek?(entry.timestamp)
        }
        timeBtn.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        timeBtn.bezelColor = NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.26, alpha: 1.0)
        timeBtn.widthAnchor.constraint(equalToConstant: 60).isActive = true
        
        let textLabel = label(entry.text, size: 12)
        textLabel.textColor = NSColor(calibratedRed: 0.90, green: 0.90, blue: 0.92, alpha: 1.0)
        textLabel.lineBreakMode = .byTruncatingTail
        
        let stack = NSStackView(views: [timeBtn, textLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        
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

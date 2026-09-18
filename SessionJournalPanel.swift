import Cocoa
#if canImport(RelayCore)
import RelayCore
#endif

@MainActor
public final class SessionJournalPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let tableView: NSTableView
    private let durationLabel: NSTextField
    private let countLabel: NSTextField
    private let addNoteField: NSTextField
    private var entries: [JournalEntry] = []
    
    public static var onClear: (() -> Void)?
    public static var onExportMarkdown: (() -> Void)?
    public static var onExportHandoff: (() -> Void)?
    public static var onAddNote: ((String) -> Void)?
    
    private static var shared: SessionJournalPanel?
    
    public init() {
        self.tableView = NSTableView()
        self.durationLabel = label("Duration: 00:00:00", size: 11, secondary: true)
        self.countLabel = label("0 entries", size: 11, secondary: true)
        
        self.addNoteField = NSTextField()
        self.addNoteField.placeholderString = "Type a note and press Enter..."
        self.addNoteField.isHidden = true
        self.addNoteField.font = .systemFont(ofSize: 12)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Session Journal"
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.level = .floating
        self.center()
        
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        
        let header = NSStackView(views: [durationLabel, countLabel])
        header.orientation = .horizontal
        header.spacing = 16
        header.alignment = .centerY
        
        self.addNoteField.delegate = self
        
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("EntryColumn"))
        column.width = 440
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24
        tableView.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        scroll.documentView = tableView
        
        let clearBtn = ActionButton("Clear") { SessionJournalPanel.onClear?() }
        let mdBtn = ActionButton("Export Markdown") { SessionJournalPanel.onExportMarkdown?() }
        let handoffBtn = ActionButton("Export Handoff") { SessionJournalPanel.onExportHandoff?() }
        let addNoteBtn = ActionButton("Add Note") { [weak self] in
            self?.addNoteField.isHidden = false
            self?.makeFirstResponder(self?.addNoteField)
        }
        
        let toolbarStack = NSStackView(views: [clearBtn, mdBtn, handoffBtn, addNoteBtn])
        toolbarStack.orientation = .horizontal
        toolbarStack.spacing = 8
        toolbarStack.alignment = .centerY
        
        container.addArrangedSubview(header)
        container.addArrangedSubview(addNoteField)
        addNoteField.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28).isActive = true
        
        container.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28).isActive = true
        
        container.addArrangedSubview(toolbarStack)
        toolbarStack.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28).isActive = true
        
        self.contentView = container
    }
    
    public func update(entries: [JournalEntry]) {
        let oldCount = self.entries.count
        self.entries = entries
        tableView.reloadData()
        
        countLabel.stringValue = "\(entries.count) entries"
        
        let now = Date()
        if let startEntry = entries.last(where: { $0.kind == .sessionStart }) {
            let duration = now.timeIntervalSince(startEntry.timestamp)
            let h = Int(duration) / 3600
            let m = (Int(duration) % 3600) / 60
            let s = Int(duration) % 60
            durationLabel.stringValue = String(format: "Duration: %02d:%02d:%02d", h, m, s)
        } else {
            durationLabel.stringValue = "Duration: 00:00:00"
        }
        
        if entries.count > oldCount {
            let lastRow = entries.count - 1
            if lastRow >= 0 {
                tableView.scrollRowToVisible(lastRow)
            }
        }
    }
    
    public static func show(entries: [JournalEntry]) {
        let panel = shared ?? SessionJournalPanel()
        panel.update(entries: entries)
        panel.makeKeyAndOrderFront(nil)
        shared = panel
    }
    
    // MARK: NSTextFieldDelegate
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let text = addNoteField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                SessionJournalPanel.onAddNote?(text)
                addNoteField.stringValue = ""
                addNoteField.isHidden = true
                self.makeFirstResponder(tableView)
            }
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            addNoteField.stringValue = ""
            addNoteField.isHidden = true
            self.makeFirstResponder(tableView)
            return true
        }
        return false
    }
    
    // MARK: NSTableViewDataSource & Delegate
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return entries.count
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let cell = NSView()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: entry.timestamp)
        let iconStr = SessionJournalPolicy.icon(for: entry.kind)
        
        let timeLabel = label(timeStr, size: 12, secondary: true)
        timeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        timeLabel.textColor = NSColor(calibratedRed: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
        
        let iconLabel = label(iconStr, size: 13)
        
        let summaryLabel = label(entry.summary, size: 13)
        summaryLabel.textColor = NSColor(calibratedRed: 0.88, green: 0.88, blue: 0.90, alpha: 1.0)
        summaryLabel.lineBreakMode = .byTruncatingTail
        
        let stack = NSStackView(views: [timeLabel, iconLabel, summaryLabel])
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

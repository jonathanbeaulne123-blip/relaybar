import Cocoa
#if canImport(RelayCore)
import RelayCore
#endif

@MainActor
public final class RealityTimelinePanel: NSPanel {
    public var onRestore: ((RealitySnapshot) -> Void)?
    public var onFork: ((RealitySnapshot) -> Void)?
    public var onSelect: ((RealitySnapshot) -> Void)?
    public var onWhatChanged: ((RealitySnapshot) -> Void)?
    public var onFilesChanged: ((RealitySnapshot) -> Void)?

    private let timelineStack = NSStackView()
    private let detailLabel: NSTextField
    private var realities: [RealitySnapshot] = []
    private var selectedID: UUID?

    public init() {
        detailLabel = label("Select a moment to inspect its saved RelayBar and Git state.", size: 12, secondary: true)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 620, height: 620),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow, .miniaturizable],
                   backing: .buffered, defer: false)
        title = "Fork Reality · Timeline"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        center()

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let heading = label("FORK REALITY", size: 20, weight: .bold)
        let subtitle = label("Saved moments are local, explicit, and Git-backed. Restore never deletes another reality.", size: 12, secondary: true)
        root.addArrangedSubview(heading)
        root.addArrangedSubview(subtitle)
        root.addArrangedSubview(detailLabel)
        detailLabel.widthAnchor.constraint(equalToConstant: 575).isActive = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false
        timelineStack.orientation = .vertical
        timelineStack.alignment = .leading
        timelineStack.spacing = 8
        timelineStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let document = FlippedDocumentView()
        document.addSubview(timelineStack)
        timelineStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            timelineStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            timelineStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            timelineStack.topAnchor.constraint(equalTo: document.topAnchor),
            timelineStack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        scroll.documentView = document
        scroll.widthAnchor.constraint(equalToConstant: 575).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 475).isActive = true
        root.addArrangedSubview(scroll)

        let close = ActionButton("Close") { [weak self] in self?.orderOut(nil) }
        root.addArrangedSubview(close)
        contentView = root
    }

    public func update(realities: [RealitySnapshot]) {
        self.realities = realities
        if selectedID == nil || !realities.contains(where: { $0.id == selectedID }) {
            selectedID = realities.first?.id
        }
        rebuild()
    }

    public func show(realities: [RealitySnapshot]) {
        update(realities: realities)
        makeKeyAndOrderFront(nil)
    }

    public func select(id: UUID, realities: [RealitySnapshot]) {
        update(realities: realities)
        guard realities.contains(where: { $0.id == id }) else { return }
        selectedID = id
        rebuild()
    }

    private func rebuild() {
        for view in timelineStack.arrangedSubviews {
            timelineStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard !realities.isEmpty else {
            timelineStack.addArrangedSubview(label("No saved realities yet. Use Fork Current Reality… from the RB menu after composing a draft.", size: 13, secondary: true))
            detailLabel.stringValue = "Timeline empty"
            return
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        for reality in realities {
            let selected = reality.id == selectedID
            let title = "\(selected ? "● " : "○ ")\(reality.name)"
            let time = formatter.string(from: reality.savedAt)
            let git = reality.gitSnapshot.isDirty ? "dirty" : "clean"
            let summary = "\(time) · \(reality.gitSnapshot.branch) · \(git) · \(reality.gitSnapshot.commit.prefix(8))"
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 10
            row.wantsLayer = true
            row.layer?.cornerRadius = 8
            row.layer?.backgroundColor = (selected ? NSColor.selectedContentBackgroundColor : NSColor.windowBackgroundColor).withAlphaComponent(selected ? 0.22 : 0.08).cgColor
            row.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

            let select = ActionButton(title, help: "Select \(reality.name)") { [weak self] in self?.select(reality) }
            select.alignment = .left
            select.widthAnchor.constraint(equalToConstant: 245).isActive = true
            let info = label(summary, size: 11, secondary: true)
            info.widthAnchor.constraint(equalToConstant: 205).isActive = true
            let restore = ActionButton("Restore") { [weak self] in self?.onRestore?(reality) }
            restore.isEnabled = selected
            let changed = ActionButton("What Changed") { [weak self] in self?.onWhatChanged?(reality) }
            changed.isEnabled = selected
            let files = ActionButton("Files") { [weak self] in self?.onFilesChanged?(reality) }
            files.isEnabled = selected
            let fork = ActionButton("Fork") { [weak self] in self?.onFork?(reality) }
            row.addArrangedSubview(select)
            row.addArrangedSubview(info)
            row.addArrangedSubview(restore)
            row.addArrangedSubview(changed)
            row.addArrangedSubview(files)
            row.addArrangedSubview(fork)
            row.widthAnchor.constraint(equalToConstant: 555).isActive = true
            timelineStack.addArrangedSubview(row)
        }
        if let selected = realities.first(where: { $0.id == selectedID }) {
            detailLabel.stringValue = "Selected: \(selected.name) · project \(selected.project.name) · \(selected.contextClipCount) context clips · \(selected.screenshotCount) screenshots · \(selected.checkpoint.draft.target.rawValue) draft"
        }
    }

    private func select(_ reality: RealitySnapshot) {
        selectedID = reality.id
        onSelect?(reality)
        rebuild()
    }
}

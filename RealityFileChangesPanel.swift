import Cocoa
#if canImport(RelayCore)
import RelayCore
#endif

@MainActor
public final class RealityFileChangesPanel: NSPanel {
    private let heading: NSTextField
    private let list: NSStackView
    private let patchView: NSTextView
    private var selectedPaths = Set<String>()
    private var selectedHunks = Set<String>()
    private var sourceReality: RealitySnapshot?
    private var targetReality: RealitySnapshot?
    public var onApply: ((RealitySnapshot, RealitySnapshot, Set<String>, Set<String>) -> Void)?

    public init() {
        heading = label("No file changes selected.", size: 13, secondary: true)
        list = NSStackView()
        patchView = NSTextView()
        super.init(contentRect: NSRect(x: 0, y: 0, width: 720, height: 680),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow, .miniaturizable],
                   backing: .buffered, defer: false)
        title = "Fork Reality · File Changes"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        center()

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        root.addArrangedSubview(label("FILE-LEVEL CHANGES", size: 20, weight: .bold))
        root.addArrangedSubview(heading)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 5
        list.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let document = FlippedDocumentView()
        document.addSubview(list)
        list.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor), list.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            list.topAnchor.constraint(equalTo: document.topAnchor), list.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        scroll.documentView = document
        scroll.widthAnchor.constraint(equalToConstant: 680).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 300).isActive = true
        root.addArrangedSubview(scroll)

        root.addArrangedSubview(label("READ-ONLY PATCH PREVIEW", size: 11, weight: .semibold))
        patchView.isEditable = false
        patchView.isSelectable = true
        patchView.isRichText = false
        patchView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        patchView.textColor = .labelColor
        let patchScroll = NSScrollView()
        patchScroll.hasVerticalScroller = true
        patchScroll.hasHorizontalScroller = true
        patchScroll.borderType = .bezelBorder
        patchScroll.documentView = patchView
        patchScroll.widthAnchor.constraint(equalToConstant: 680).isActive = true
        patchScroll.heightAnchor.constraint(equalToConstant: 260).isActive = true
        root.addArrangedSubview(patchScroll)
        root.addArrangedSubview(ActionButton("Apply Selected…", help: "Apply the checked complete-file changes to the target worktree") { [weak self] in
            guard let self = self, let source = self.sourceReality, let target = self.targetReality else { return }
            self.onApply?(source, target, self.selectedHunks, self.selectedPaths)
        })
        root.addArrangedSubview(ActionButton("Close") { [weak self] in self?.orderOut(nil) })
        contentView = root
    }

    public func show(from: RealitySnapshot, to: RealitySnapshot) {
        let isNewComparison = sourceReality?.id != from.id || targetReality?.id != to.id
        sourceReality = from
        targetReality = to
        let changes = RealityDiff.compareFiles(from, to)
        if isNewComparison {
            selectedPaths = Set(changes.filter { $0.kind == .added && $0.detail == "untracked" }.map(\.path))
            selectedHunks = Set(RealityDiff.hunks(in: from).map(\.id))
        }
        heading.stringValue = changes.isEmpty ? "No file-level changes between \(from.name) and \(to.name)." : "\(changes.count) file-level change\(changes.count == 1 ? "" : "s") · \(from.name) → \(to.name)"
        for view in list.arrangedSubviews { list.removeArrangedSubview(view); view.removeFromSuperview() }
        if changes.isEmpty {
            list.addArrangedSubview(label("No added, modified, deleted, renamed, binary, or untracked files were recorded.", size: 12, secondary: true))
        } else {
            for change in changes {
                let marker: String
                switch change.kind { case .added: marker = "+"; case .modified: marker = "~"; case .deleted: marker = "−"; case .renamed: marker = "→"; case .binary: marker = "◇" }
                let fileHunks = RealityDiff.hunks(in: from).filter { $0.path == change.path }
                let fileSelected = fileHunks.isEmpty ? selectedPaths.contains(change.path) : fileHunks.allSatisfy { selectedHunks.contains($0.id) }
                let row = ActionButton("\(fileSelected ? "☑" : "☐")  \(marker)  \(change.path)  ·  \(change.kind.rawValue)\(change.detail.isEmpty ? "" : " · \(change.detail)")", help: "Toggle all changes in \(change.path)") { [weak self] in
                    guard let self = self else { return }
                    if fileHunks.isEmpty {
                        if self.selectedPaths.contains(change.path) { self.selectedPaths.remove(change.path) } else { self.selectedPaths.insert(change.path) }
                    } else {
                        let shouldSelect = !fileHunks.allSatisfy { self.selectedHunks.contains($0.id) }
                        for hunk in fileHunks {
                            if shouldSelect { self.selectedHunks.insert(hunk.id) } else { self.selectedHunks.remove(hunk.id) }
                        }
                    }
                    self.show(from: from, to: to)
                }
                row.alignment = .left
                row.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                row.widthAnchor.constraint(equalToConstant: 650).isActive = true
                list.addArrangedSubview(row)
                for hunk in fileHunks {
                    let hunkButton = ActionButton("    \(self.selectedHunks.contains(hunk.id) ? "☑" : "☐") \(hunk.header)", help: "Toggle this hunk only") { [weak self] in
                        guard let self = self else { return }
                        if self.selectedHunks.contains(hunk.id) { self.selectedHunks.remove(hunk.id) } else { self.selectedHunks.insert(hunk.id) }
                        self.show(from: from, to: to)
                    }
                    hunkButton.alignment = .left
                    hunkButton.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                    hunkButton.widthAnchor.constraint(equalToConstant: 630).isActive = true
                    list.addArrangedSubview(hunkButton)
                }
            }
        }
        let selectedPatch = RealityDiff.selectedHunkPatch(selectedHunks, in: from)
        if !selectedPatch.isEmpty, let text = String(data: selectedPatch, encoding: .utf8), !text.isEmpty {
            patchView.string = text
        } else if let patch = to.dirtyWorkingTree?.trackedPatch, let text = String(data: patch, encoding: .utf8), !text.isEmpty {
            patchView.string = text
        } else {
            patchView.string = "No text patch recorded. Binary changes and untracked files are listed above."
        }
        makeKeyAndOrderFront(nil)
    }
}

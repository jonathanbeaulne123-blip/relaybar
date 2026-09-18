import Cocoa

/// YouTube setup and storage.
///
/// Reached from the RB menu. It exists because background control of a video has
/// a real prerequisite — Chrome's own "Allow JavaScript from Apple Events"
/// switch — and because transcripts are written to disk. Both facts are stated
/// here rather than hidden behind a silent failure.
@MainActor
final class YouTubeSettingsPanel: NSPanel {
    private let youTube = YouTubeController.shared
    private let store: YouTubeTranscriptStore?
    private let statusLabel = label("", size: 11, secondary: true)
    private let storageLabel = label("", size: 12)

    init(store: YouTubeTranscriptStore?) {
        self.store = store
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow],
                   backing: .buffered, defer: false)
        self.title = "YouTube Control & Storage"
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.level = .floating
        self.center()
        buildContent()
    }

    private func buildContent() {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let controlHeading = label("CONTROL", size: 11, weight: .semibold)
        let controlBody = label(YouTubeControlAvailability.setupInstructions, size: 12)
        controlBody.isSelectable = true

        var controlRowViews: [NSView] = [
            ActionButton("Retry control", help: "Re-check scripted control now. This changes no Chrome setting.") { [weak self] in
                self?.youTube.retryControl()
                self?.statusLabel.stringValue = self?.youTube.setupStatus ?? ""
            },
            ActionButton("Open Chrome", help: "Bring Google Chrome to the front so the View menu is reachable") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
                    let options = NSWorkspace.OpenConfiguration()
                    options.activates = true
                    NSWorkspace.shared.openApplication(at: url, configuration: options) { _, _ in }
                }
            }
        ]
        controlRowViews.append(ActionButton("Copy instructions", help: "Copy the Chrome setup steps") { [weak self] in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(YouTubeControlAvailability.setupInstructions, forType: .string)
            self?.statusLabel.stringValue = "Copied the setup steps."
        })
        let controlRow = NSStackView(views: controlRowViews)
        controlRow.orientation = .horizontal
        controlRow.spacing = 8
        controlRow.alignment = .centerY

        let storageHeading = label("LOCAL STORAGE", size: 11, weight: .semibold)
        let storageBody = label("Transcripts and Moments are stored in RelayBar's private local folder as one JSON file per video, readable only by you. Nothing is uploaded, and no watched-video history is kept beyond the videos you explicitly transcribed.", size: 12)
        storageBody.isSelectable = false

        var storageRowViews: [NSView] = [
            ActionButton("Reveal folder", help: "Show the Transcripts folder in Finder") { [weak self] in
                guard let url = self?.store?.directory else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            ActionButton("Delete all transcripts…", help: "Delete every stored transcript and Moment") { [weak self] in
                guard let self = self else { return }
                let alert = NSAlert()
                alert.messageText = "Delete every stored transcript?"
                alert.informativeText = "This removes RelayBar's local transcript files and their saved Moments. YouTube itself is untouched, and nothing is sent anywhere."
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Delete all")
                guard alert.runModal() == .alertSecondButtonReturn else { return }
                self.youTube.clearStoredLibrary()
                self.refresh()
            }
        ]
        storageRowViews.append(ActionButton("Refresh", help: "Re-read the stored library") { [weak self] in self?.refresh() })
        let storageRow = NSStackView(views: storageRowViews)
        storageRow.orientation = .horizontal
        storageRow.spacing = 8
        storageRow.alignment = .centerY

        container.addArrangedSubview(label("YouTube", size: 20, weight: .bold))
        container.addArrangedSubview(label("RelayBar controls the tab that is already playing. It does not open videos, change your account, or read anything except the video's own player state and the caption track you ask for.", size: 12, secondary: true))
        container.addArrangedSubview(controlHeading)
        container.addArrangedSubview(controlBody)
        container.addArrangedSubview(controlRow)
        container.addArrangedSubview(storageHeading)
        container.addArrangedSubview(storageBody)
        container.addArrangedSubview(storageLabel)
        container.addArrangedSubview(storageRow)
        container.addArrangedSubview(statusLabel)

        for view in [controlBody, storageBody] {
            view.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true
        }
        self.contentView = container
        refresh()
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        refresh()
    }

    private func refresh() {
        statusLabel.stringValue = youTube.setupStatus
        guard let store = store, let library = try? store.loadLibrary() else {
            storageLabel.stringValue = "Local transcript storage is unavailable. Nothing was changed."
            return
        }
        if library.count == 0 {
            storageLabel.stringValue = "No transcripts stored yet."
        } else {
            let moments = library.totalMoments
            storageLabel.stringValue = "\(library.count) video\(library.count == 1 ? "" : "s") · \(library.totalCharacters.formatted()) transcript characters · \(moments) Moment\(moments == 1 ? "" : "s") stored."
        }
    }
}

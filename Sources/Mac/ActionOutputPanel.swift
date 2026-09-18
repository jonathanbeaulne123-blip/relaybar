import Cocoa

@MainActor
public final class ActionOutputPanel: NSPanel {
    private let textView: NSTextView
    private let statusLabel: NSTextField
    private let spinner: NSProgressIndicator
    private let titleLabel: NSTextField
    private var isTaskRunning = false
    
    public init() {
        let (scroll, text) = textEditor(height: 320, mono: true)
        self.textView = text
        self.statusLabel = label("Ready", size: 11, secondary: true)
        self.titleLabel = label("Action Output", size: 13, weight: .bold)
        self.spinner = NSProgressIndicator()
        self.spinner.style = .spinning
        self.spinner.controlSize = .small
        self.spinner.isDisplayedWhenStopped = false
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 440),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        self.title = "RelayBar · Command Output"
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.center()
        
        // Terminal styling for text view
        self.textView.isEditable = false
        self.textView.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        self.textView.textColor = NSColor(calibratedRed: 0.88, green: 0.88, blue: 0.90, alpha: 1.0)
        self.textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        
        // Header
        let header = NSStackView(views: [titleLabel, spinner, statusLabel])
        header.orientation = .horizontal
        header.spacing = 8
        header.alignment = .centerY
        
        // Footer buttons
        let clearBtn = ActionButton("Clear") { [weak self] in
            self?.clear()
        }
        let copyBtn = ActionButton("Copy Output") { [weak self] in
            self?.copyOutput()
        }
        let closeBtn = ActionButton("Close") { [weak self] in
            self?.orderOut(nil)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [clearBtn, copyBtn, spacer, closeBtn])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.alignment = .centerY
        
        container.addArrangedSubview(header)
        container.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28).isActive = true
        container.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28).isActive = true
        
        self.contentView = container
    }
    
    public func start(actionName: String, command: String) {
        titleLabel.stringValue = "\(actionName) — \(command)"
        statusLabel.stringValue = "Running…"
        statusLabel.textColor = .systemYellow
        spinner.startAnimation(nil)
        isTaskRunning = true
        textView.string = "$ \(command)\n"
        makeKeyAndOrderFront(nil)
    }
    
    public func appendOutput(_ text: String) {
        let prev = textView.string
        textView.string = prev + text
        textView.scrollToEndOfDocument(nil)
    }
    
    public func finish(result: ActionResult) {
        spinner.stopAnimation(nil)
        isTaskRunning = false
        if result.succeeded {
            statusLabel.stringValue = "✓ Succeeded in \(String(format: "%.2fs", result.duration))"
            statusLabel.textColor = .systemGreen
        } else {
            statusLabel.stringValue = "✗ Failed (exit code \(result.exitCode)) in \(String(format: "%.2fs", result.duration))"
            statusLabel.textColor = .systemRed
        }
        textView.string = textView.string + "\n[Process exited with code \(result.exitCode)]\n"
        textView.scrollToEndOfDocument(nil)
    }
    
    public func clear() {
        textView.string = ""
        statusLabel.stringValue = "Cleared"
        statusLabel.textColor = .secondaryLabelColor
    }
    
    public func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
        statusLabel.stringValue = "Copied to clipboard"
    }
}

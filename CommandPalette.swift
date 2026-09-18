import Cocoa

@MainActor
public final class CommandPalette: NSPanel, NSTextFieldDelegate {
    private let searchField = NSTextField()
    private let resultsStack = NSStackView()
    private let commandIndex: CommandIndex
    private var currentResults: [CommandEntry] = []
    private var selectedIndex: Int = 0
    
    public var onExecuteCommand: ((CommandEntry) -> Void)?
    
    public init(commandIndex: CommandIndex) {
        self.commandIndex = commandIndex
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = true
        self.center()
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        
        searchField.placeholderString = "Type a command, quick action, or git shortcut…"
        searchField.font = .systemFont(ofSize: 16, weight: .regular)
        searchField.focusRingType = .none
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.delegate = self
        
        let separator = NSBox()
        separator.boxType = .separator
        
        resultsStack.orientation = .vertical
        resultsStack.alignment = .leading
        resultsStack.spacing = 4
        
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = resultsStack
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 280).isActive = true
        
        container.addArrangedSubview(searchField)
        searchField.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true
        container.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true
        container.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true
        
        visualEffect.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            container.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            container.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])
        
        self.contentView = visualEffect
    }
    
    public func present() {
        searchField.stringValue = ""
        updateSearch("")
        makeKeyAndOrderFront(nil)
        searchField.selectText(nil)
    }
    
    public func controlTextDidChange(_ obj: Notification) {
        updateSearch(searchField.stringValue)
    }
    
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            selectNext()
            return true
        } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
            selectPrevious()
            return true
        } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            executeSelected()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            orderOut(nil)
            return true
        }
        return false
    }
    
    private func updateSearch(_ query: String) {
        currentResults = commandIndex.search(query)
        selectedIndex = 0
        renderResults()
    }
    
    private func renderResults() {
        for v in resultsStack.arrangedSubviews {
            resultsStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        
        if currentResults.isEmpty {
            let empty = label("No matching commands found.", size: 12, secondary: true)
            resultsStack.addArrangedSubview(empty)
            return
        }
        
        for (index, entry) in currentResults.enumerated() {
            let item = NSStackView()
            item.orientation = .horizontal
            item.alignment = .centerY
            item.spacing = 10
            item.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
            item.wantsLayer = true
            item.layer?.cornerRadius = 6
            
            let isSelected = index == selectedIndex
            if isSelected {
                item.layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.3).cgColor
            } else {
                item.layer?.backgroundColor = NSColor.clear.cgColor
            }
            
            let icon = label(entry.icon.isEmpty ? "•" : entry.icon, size: 14)
            let textStack = NSStackView()
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 2
            
            let title = label(entry.title, size: 13, weight: isSelected ? .semibold : .regular)
            let subtitle = label(entry.subtitle, size: 11, secondary: true)
            textStack.addArrangedSubview(title)
            if !entry.subtitle.isEmpty {
                textStack.addArrangedSubview(subtitle)
            }
            
            let tag = label(entry.kind.rawValue, size: 10, secondary: true)
            tag.setContentHuggingPriority(.required, for: .horizontal)
            
            item.addArrangedSubview(icon)
            item.addArrangedSubview(textStack)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            item.addArrangedSubview(spacer)
            item.addArrangedSubview(tag)
            
            resultsStack.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: resultsStack.widthAnchor).isActive = true
        }
    }
    
    private func selectNext() {
        guard !currentResults.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, currentResults.count - 1)
        renderResults()
    }
    
    private func selectPrevious() {
        guard !currentResults.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
        renderResults()
    }
    
    private func executeSelected() {
        guard currentResults.indices.contains(selectedIndex) else { return }
        let entry = currentResults[selectedIndex]
        commandIndex.recordUsage(entry.id)
        orderOut(nil)
        onExecuteCommand?(entry)
    }
}

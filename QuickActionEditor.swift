import Cocoa

@MainActor
public final class QuickActionEditor: NSPanel {
    private let nameField = NSTextField()
    private let iconField = NSTextField()
    private let commandField: NSTextView
    private let workDirPicker = NSPopUpButton()
    private let hotkeyField = NSTextField()
    private let showOutputCheckbox = NSButton(checkboxWithTitle: "Show Output Panel", target: nil, action: nil)
    
    public var onSave: ((QuickAction) -> Void)?
    private var editingActionID: UUID?
    
    public init() {
        let (scroll, commandText) = textEditor(height: 90, mono: true)
        self.commandField = commandText
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Quick Action Editor"
        self.isReleasedWhenClosed = false
        self.center()
        
        workDirPicker.addItems(withTitles: ["Project Root", "Home Directory", "Custom Directory…"])
        
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        
        func addRow(_ title: String, _ view: NSView) {
            let lbl = label(title, size: 12, weight: .medium)
            lbl.widthAnchor.constraint(equalToConstant: 120).isActive = true
            let r = NSStackView(views: [lbl, view])
            r.orientation = .horizontal
            r.spacing = 8
            r.alignment = .centerY
            container.addArrangedSubview(r)
            r.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true
        }
        
        nameField.placeholderString = "e.g. Build Project"
        addRow("Name:", nameField)
        
        iconField.placeholderString = "e.g. ⚡, 🔨, 🚀"
        iconField.stringValue = "⚡"
        addRow("Icon / Emoji:", iconField)
        
        addRow("Working Dir:", workDirPicker)
        
        let cmdLabel = label("Shell Command:", size: 12, weight: .medium)
        container.addArrangedSubview(cmdLabel)
        container.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true
        
        hotkeyField.placeholderString = "Optional (e.g. ⌘B)"
        addRow("Shortcut:", hotkeyField)
        
        showOutputCheckbox.state = .on
        container.addArrangedSubview(showOutputCheckbox)
        
        // Buttons
        let cancelBtn = ActionButton("Cancel") { [weak self] in
            self?.orderOut(nil)
        }
        let saveBtn = ActionButton("Save Action") { [weak self] in
            self?.save()
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [spacer, cancelBtn, saveBtn])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        container.addArrangedSubview(buttonRow)
        buttonRow.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true
        
        self.contentView = container
    }
    
    public func loadAction(_ action: QuickAction?) {
        if let a = action {
            editingActionID = a.id
            nameField.stringValue = a.name
            iconField.stringValue = a.icon
            commandField.string = a.command
            showOutputCheckbox.state = a.showOutput ? .on : .off
            hotkeyField.stringValue = a.hotkey ?? ""
            switch a.workingDirectory {
            case .projectRoot: workDirPicker.selectItem(at: 0)
            case .home: workDirPicker.selectItem(at: 1)
            case .custom: workDirPicker.selectItem(at: 2)
            }
        } else {
            editingActionID = nil
            nameField.stringValue = ""
            iconField.stringValue = "⚡"
            commandField.string = ""
            showOutputCheckbox.state = .on
            hotkeyField.stringValue = ""
            workDirPicker.selectItem(at: 0)
        }
        makeKeyAndOrderFront(nil)
    }
    
    private func save() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = commandField.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = iconField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !name.isEmpty, !command.isEmpty else {
            NSSound.beep()
            return
        }
        
        let workDir: ActionWorkingDirectory
        switch workDirPicker.indexOfSelectedItem {
        case 1: workDir = .home
        default: workDir = .projectRoot
        }
        
        let hotkey = hotkeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let action = QuickAction(
            id: editingActionID ?? UUID(),
            name: name,
            icon: icon.isEmpty ? "⚡" : icon,
            command: command,
            workingDirectory: workDir,
            showOutput: showOutputCheckbox.state == .on,
            hotkey: hotkey.isEmpty ? nil : hotkey
        )
        
        onSave?(action)
        orderOut(nil)
    }
}

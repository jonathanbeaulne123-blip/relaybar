import Cocoa

/// Editor for Your Sites rules.
///
/// The editor is a normal AppKit window. It validates every rule with the same
/// validator the matcher uses, so a rule that cannot run also cannot be saved
/// into the configuration. Nothing here executes a button; running is a
/// separate, confirmed action on the Touch Bar.
@MainActor
public final class SiteRulesEditor: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    private var rules: [SiteRule] = []
    private var quickActions: [QuickAction] = []
    private var plugins: [Plugin] = []
    private var currentTarget: () -> SiteTarget = { SiteTarget() }

    public var onSave: (([SiteRule]) -> Void)?

    private let rulesTable = NSTableView(frame: .zero)
    private let buttonsTable = NSTableView(frame: .zero)
    private let nameField = NSTextField()
    private let enabledCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let scopePicker = NSPopUpButton()
    private let hostsField = NSTextField()
    private let bundlesField = NSTextField()
    private let pathField = NSTextField()
    private let titleField = NSTextField()
    private let matchLabel = label("No rule selected.", size: 11, secondary: true)
    private let detailBox = NSStackView()
    private let buttonEditor = SiteButtonEditorPanel()
    private var suppress = false

    private static let ruleColumn = NSUserInterfaceItemIdentifier("rule")
    private static let buttonColumn = NSUserInterfaceItemIdentifier("button")

    public init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow],
                   backing: .buffered, defer: false)
        title = "RelayBar · Your Sites"
        isReleasedWhenClosed = false
        center()

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        container.addArrangedSubview(label("YOUR SITES", size: 15, weight: .bold))
        container.addArrangedSubview(label("Rules are matched against the frontmost page or application. The most specific rule wins; two equally specific rules are refused rather than guessed. Nothing runs until you tap a button on the Touch Bar.", size: 11, secondary: true))

        let columns = NSStackView()
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 14

        rulesTable.headerView = nil
        rulesTable.dataSource = self
        rulesTable.delegate = self
        rulesTable.allowsEmptySelection = true
        let ruleColumnView = NSTableColumn(identifier: Self.ruleColumn)
        ruleColumnView.width = 220
        rulesTable.addTableColumn(ruleColumnView)
        let rulesScroll = NSScrollView()
        rulesScroll.documentView = rulesTable
        rulesScroll.hasVerticalScroller = true
        rulesScroll.borderType = .bezelBorder
        rulesScroll.translatesAutoresizingMaskIntoConstraints = false
        rulesScroll.widthAnchor.constraint(equalToConstant: 230).isActive = true
        rulesScroll.heightAnchor.constraint(equalToConstant: 290).isActive = true

        let ruleButtons = NSStackView(views: [
            ActionButton("Add") { [weak self] in self?.addRule() },
            ActionButton("Duplicate") { [weak self] in self?.duplicateRule() },
            ActionButton("Up") { [weak self] in self?.moveRule(-1) },
            ActionButton("Down") { [weak self] in self?.moveRule(1) },
            ActionButton("Delete") { [weak self] in self?.deleteRule() }
        ])
        ruleButtons.orientation = .horizontal
        ruleButtons.spacing = 6

        let left = NSStackView(views: [rulesScroll, ruleButtons])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 8

        detailBox.orientation = .vertical
        detailBox.alignment = .leading
        detailBox.spacing = 8
        detailBox.translatesAutoresizingMaskIntoConstraints = false
        detailBox.widthAnchor.constraint(equalToConstant: 520).isActive = true

        func field(_ title: String, _ view: NSView, help: String? = nil) -> NSStackView {
            let caption = label(title, size: 11, weight: .medium)
            caption.widthAnchor.constraint(equalToConstant: 96).isActive = true
            let stack = NSStackView(views: [caption, view])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            stack.toolTip = help
            return stack
        }

        scopePicker.addItems(withTitles: ["Browser page", "Desktop application"])
        scopePicker.target = self
        scopePicker.action = #selector(detailChanged)
        hostsField.placeholderString = "mail.google.com, *.example.com"
        hostsField.target = self
        hostsField.action = #selector(detailChanged)
        hostsField.delegate = self
        hostsField.toolTip = "Comma-separated. Use an exact host, or one leading *. for a whole domain."
        bundlesField.placeholderString = "com.anthropic.claudefordesktop"
        bundlesField.toolTip = "Comma-separated bundle identifiers for desktop applications."
        bundlesField.delegate = self
        pathField.placeholderString = "/optional/path/prefix"
        pathField.toolTip = "Only match pages whose path starts with this prefix. Leave empty to match the whole host."
        pathField.delegate = self
        titleField.placeholderString = "optional window-title text"
        titleField.toolTip = "Only match when the window title contains this text."
        titleField.delegate = self
        nameField.placeholderString = "Rule name"
        nameField.delegate = self

        detailBox.addArrangedSubview(field("Name", nameField))
        detailBox.addArrangedSubview(field("Scope", scopePicker))
        detailBox.addArrangedSubview(field("Hosts", hostsField))
        detailBox.addArrangedSubview(field("Bundles", bundlesField))
        detailBox.addArrangedSubview(field("Path prefix", pathField))
        detailBox.addArrangedSubview(field("Title match", titleField))
        enabledCheckbox.target = self
        enabledCheckbox.action = #selector(detailChanged)
        detailBox.addArrangedSubview(enabledCheckbox)
        detailBox.addArrangedSubview(label("BUTTONS", size: 11, weight: .semibold))

        buttonsTable.headerView = nil
        buttonsTable.dataSource = self
        buttonsTable.delegate = self
        let buttonColumnView = NSTableColumn(identifier: Self.buttonColumn)
        buttonColumnView.width = 380
        buttonsTable.addTableColumn(buttonColumnView)
        let buttonsScroll = NSScrollView()
        buttonsScroll.documentView = buttonsTable
        buttonsScroll.hasVerticalScroller = true
        buttonsScroll.borderType = .bezelBorder
        buttonsScroll.translatesAutoresizingMaskIntoConstraints = false
        buttonsScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        detailBox.addArrangedSubview(buttonsScroll)
        buttonsScroll.widthAnchor.constraint(equalTo: detailBox.widthAnchor).isActive = true

        let buttonButtons = NSStackView(views: [
            ActionButton("Add button") { [weak self] in self?.addButton() },
            ActionButton("Edit button") { [weak self] in self?.editButton() },
            ActionButton("Remove") { [weak self] in self?.removeButton() }
        ])
        buttonButtons.orientation = .horizontal
        buttonButtons.spacing = 6
        detailBox.addArrangedSubview(buttonButtons)
        detailBox.addArrangedSubview(matchLabel)

        columns.addArrangedSubview(left)
        columns.addArrangedSubview(detailBox)
        container.addArrangedSubview(columns)

        let saveButton = ActionButton("Save rules") { [weak self] in self?.save() }
        let closeButton = ActionButton("Close") { [weak self] in self?.orderOut(nil) }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [label("Rules are stored in your local RelayBar configuration.", size: 11, secondary: true), spacer, closeButton, saveButton])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.alignment = .centerY
        container.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true

        contentView = container
        setDetailEnabled(false)
    }

    public func load(rules: [SiteRule], quickActions: [QuickAction], plugins: [Plugin],
                     currentTarget: @escaping () -> SiteTarget) {
        self.rules = rules
        self.quickActions = quickActions
        self.plugins = plugins
        self.currentTarget = currentTarget
        rulesTable.reloadData()
        if !rules.isEmpty { rulesTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        else { selectRule(at: nil) }
        refreshMatchLabel()
        makeKeyAndOrderFront(nil)
    }

    // MARK: - Table plumbing

    public func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === rulesTable ? rules.count : (selectedRule?.buttons.count ?? 0)
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text: String
        if tableView === rulesTable {
            guard row < rules.count else { return nil }
            let rule = rules[row]
            let mark = rule.enabled ? "✓" : "—"
            text = "\(mark) \(rule.name)"
        } else {
            guard let rule = selectedRule, row < rule.buttons.count else { return nil }
            let button = rule.buttons[row]
            let confirm = button.requiresConfirmation ? " · confirms" : ""
            text = "\(SiteControlsPolicy.displayTitle(button)) · \(button.effect.kindName)\(confirm)"
        }
        let cell = NSTableCellView()
        let field = label(text, size: 12)
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        cell.textField = field
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        if notification.object as? NSTableView === rulesTable {
            loadSelectedRuleIntoForm()
        } else {
            refreshMatchLabel()
        }
    }

    private var selectedRuleIndex: Int? {
        let index = rulesTable.selectedRow
        return index >= 0 && index < rules.count ? index : nil
    }

    private var selectedRule: SiteRule? {
        guard let index = selectedRuleIndex else { return nil }
        return rules[index]
    }

    private func selectRule(at index: Int?) {
        if let index = index, index >= 0, index < rules.count {
            rulesTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            rulesTable.deselectAll(nil)
        }
        loadSelectedRuleIntoForm()
    }

    // MARK: - Form

    private func setDetailEnabled(_ enabled: Bool) {
        for view in [nameField, hostsField, bundlesField, pathField, titleField] { view.isEnabled = enabled }
        scopePicker.isEnabled = enabled
        enabledCheckbox.isEnabled = enabled
    }

    private func loadSelectedRuleIntoForm() {
        guard let rule = selectedRule else {
            suppress = true
            nameField.stringValue = ""; hostsField.stringValue = ""; bundlesField.stringValue = ""
            pathField.stringValue = ""; titleField.stringValue = ""; enabledCheckbox.state = .off
            suppress = false
            setDetailEnabled(false)
            buttonsTable.reloadData()
            refreshMatchLabel()
            return
        }
        suppress = true
        setDetailEnabled(true)
        nameField.stringValue = rule.name
        hostsField.stringValue = rule.hosts.joined(separator: ", ")
        bundlesField.stringValue = rule.scope.bundles.joined(separator: ", ")
        pathField.stringValue = rule.pathPrefix ?? ""
        titleField.stringValue = rule.titleContains ?? ""
        enabledCheckbox.state = rule.enabled ? .on : .off
        scopePicker.selectItem(at: rule.scope.kind == .browser ? 0 : 1)
        suppress = false
        buttonsTable.reloadData()
        refreshMatchLabel()
    }

    @objc private func detailChanged() {
        guard !suppress, let index = selectedRuleIndex else { return }
        var rule = rules[index]
        rule.name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.enabled = enabledCheckbox.state == .on
        rule.hosts = hostsField.stringValue.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        rule.scope = SiteScope(kind: scopePicker.indexOfSelectedItem == 1 ? .apps : .browser,
                               bundles: bundlesField.stringValue.split(separator: ",")
                                   .map { $0.trimmingCharacters(in: .whitespaces) }
                                   .filter { !$0.isEmpty })
        let path = pathField.stringValue.trimmingCharacters(in: .whitespaces)
        rule.pathPrefix = path.isEmpty ? nil : path
        let needle = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        rule.titleContains = needle.isEmpty ? nil : needle
        rules[index] = rule
        rulesTable.reloadData()
        rulesTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        refreshMatchLabel()
    }

    private func refreshMatchLabel() {
        guard !rules.isEmpty else {
            matchLabel.stringValue = "No rules yet. Add one to see it on the Touch Bar."
            return
        }
        let detection = SiteRuleMatcher.detect(target: currentTarget(), rules: rules)
        matchLabel.stringValue = detection.status
    }

    // MARK: - Rule editing

    private func addRule() {
        let rule = SiteRule(id: "site-\(UUID().uuidString.prefix(8).lowercased())", name: "New site",
                            scope: SiteScope(kind: .browser), hosts: [""],
                            buttons: [SiteButton(id: "ask", title: "Ask", icon: "💬", effect: .prompt(.explain))])
        rules.append(rule)
        rulesTable.reloadData()
        selectRule(at: rules.count - 1)
    }

    private func duplicateRule() {
        guard let index = selectedRuleIndex else { return }
        var copy = rules[index]
        copy.id = "\(copy.id)-\(UUID().uuidString.prefix(4).lowercased())"
        copy.name = copy.name + " copy"
        copy.enabled = false
        rules.insert(copy, at: index + 1)
        rulesTable.reloadData()
        selectRule(at: index + 1)
    }

    private func moveRule(_ offset: Int) {
        guard let index = selectedRuleIndex else { return }
        let destination = index + offset
        guard destination >= 0, destination < rules.count else { return }
        rules.swapAt(index, destination)
        rulesTable.reloadData()
        selectRule(at: destination)
    }

    private func deleteRule() {
        guard let index = selectedRuleIndex else { return }
        rules.remove(at: index)
        rulesTable.reloadData()
        selectRule(at: min(index, rules.count - 1))
    }

    // MARK: - Button editing

    private func addButton() {
        guard let index = selectedRuleIndex else { return }
        buttonEditor.load(nil, quickActions: quickActions, plugins: plugins) { [weak self] button in
            guard let self = self, index < self.rules.count else { return }
            self.rules[index].buttons.append(button)
            self.buttonsTable.reloadData()
            self.refreshMatchLabel()
        }
    }

    private func editButton() {
        guard let index = selectedRuleIndex else { return }
        let row = buttonsTable.selectedRow
        guard row >= 0, row < rules[index].buttons.count else { return }
        buttonEditor.load(rules[index].buttons[row], quickActions: quickActions, plugins: plugins) { [weak self] button in
            guard let self = self, index < self.rules.count, row < self.rules[index].buttons.count else { return }
            self.rules[index].buttons[row] = button
            self.buttonsTable.reloadData()
            self.refreshMatchLabel()
        }
    }

    private func removeButton() {
        guard let index = selectedRuleIndex else { return }
        let row = buttonsTable.selectedRow
        guard row >= 0, row < rules[index].buttons.count else { return }
        rules[index].buttons.remove(at: row)
        buttonsTable.reloadData()
        refreshMatchLabel()
    }

    // MARK: - Save

    private func save() {
        // A rule with no buttons cannot run, so it is not written.
        let cleaned = rules.map { rule -> SiteRule in
            var value = rule
            value.hosts = value.hosts.filter { !$0.isEmpty }
            return value
        }
        for rule in cleaned {
            do { try rule.validate() }
            catch {
                let alert = NSAlert()
                alert.messageText = "That rule cannot be saved"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "Fix it")
                alert.runModal()
                return
            }
        }
        rules = cleaned
        onSave?(cleaned)
        rulesTable.reloadData()
        refreshMatchLabel()
    }
}

extension SiteRulesEditor: NSTextFieldDelegate {
    public func controlTextDidEndEditing(_ obj: Notification) { detailChanged() }
}

/// Editor for one button inside a rule. Every kind is bounded: a key from the
/// allowlist, an https template, clipboard text, or an existing local command.
@MainActor
public final class SiteButtonEditorPanel: NSPanel {
    private let titleField = NSTextField()
    private let iconField = NSTextField()
    private let kindPicker = NSPopUpButton()
    private let keyField = NSTextField()
    private let modifierBoxes = ["command", "shift", "option", "control"].map {
        NSButton(checkboxWithTitle: $0, target: nil, action: nil)
    }
    private let templateField = NSTextField()
    private let clipboardField = NSTextField()
    private let promptPicker = NSPopUpButton()
    private let pagePicker = NSPopUpButton()
    private let quickActionPicker = NSPopUpButton()
    private let pluginPicker = NSPopUpButton()
    private let commandField = NSTextField()
    private let confirmationBox = NSButton(checkboxWithTitle: "Ask for confirmation before running", target: nil, action: nil)
    private let hintLabel = label("", size: 11, secondary: true)
    private let kindRows = NSStackView()

    private var quickActions: [QuickAction] = []
    private var plugins: [Plugin] = []
    private var editingID: String?
    private var onSave: ((SiteButton) -> Void)?
    private static let kinds: [SiteButtonEffect.KindTag] = SiteButtonEffect.KindTag.allCases

    public init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                   styleMask: [.titled, .closable, .utilityWindow],
                   backing: .buffered, defer: false)
        title = "RelayBar · Site button"
        isReleasedWhenClosed = false
        center()

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 9
        container.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        func field(_ caption: String, _ view: NSView) -> NSStackView {
            let captionLabel = label(caption, size: 11, weight: .medium)
            captionLabel.widthAnchor.constraint(equalToConstant: 96).isActive = true
            let stack = NSStackView(views: [captionLabel, view])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            return stack
        }

        kindPicker.addItems(withTitles: Self.kinds.map { $0.title })
        kindPicker.target = self
        kindPicker.action = #selector(kindChanged)
        promptPicker.addItems(withTitles: PromptAction.allCases.map { $0.title })
        pagePicker.addItems(withTitles: SiteControlsPolicy.relayablePages.sorted { $0.title < $1.title }.map { $0.title })
        for box in modifierBoxes { box.target = self; box.action = #selector(kindChanged) }

        container.addArrangedSubview(label("SITE BUTTON", size: 15, weight: .bold))
        container.addArrangedSubview(field("Title", titleField))
        container.addArrangedSubview(field("Icon", iconField))
        container.addArrangedSubview(field("Effect", kindPicker))

        kindRows.orientation = .vertical
        kindRows.alignment = .leading
        kindRows.spacing = 8
        kindRows.addArrangedSubview(field("Key", keyField))
        let modifiers = NSStackView(views: modifierBoxes)
        modifiers.orientation = .horizontal
        modifiers.spacing = 10
        kindRows.addArrangedSubview(field("Modifiers", modifiers))
        kindRows.addArrangedSubview(field("URL", templateField))
        kindRows.addArrangedSubview(field("Clipboard", clipboardField))
        kindRows.addArrangedSubview(field("Prompt", promptPicker))
        kindRows.addArrangedSubview(field("Page", pagePicker))
        kindRows.addArrangedSubview(field("Quick Action", quickActionPicker))
        kindRows.addArrangedSubview(field("Plugin", pluginPicker))
        kindRows.addArrangedSubview(field("Command", commandField))
        container.addArrangedSubview(kindRows)
        container.addArrangedSubview(hintLabel)
        container.addArrangedSubview(confirmationBox)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [spacer,
            ActionButton("Cancel") { [weak self] in self?.orderOut(nil) },
            ActionButton("Save button") { [weak self] in self?.save() }])
        footer.orientation = .horizontal
        footer.spacing = 8
        container.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true

        contentView = container
        kindChanged()
    }

    public func load(_ button: SiteButton?, quickActions: [QuickAction], plugins: [Plugin],
                     onSave: @escaping (SiteButton) -> Void) {
        self.quickActions = quickActions
        self.plugins = plugins
        self.onSave = onSave
        editingID = button?.id
        quickActionPicker.removeAllItems()
        quickActionPicker.addItems(withTitles: quickActions.map { "\($0.icon) \($0.name)" })
        pluginPicker.removeAllItems()
        pluginPicker.addItems(withTitles: plugins.map { $0.manifest.name })

        titleField.stringValue = button?.title ?? "Ask"
        iconField.stringValue = button?.icon ?? ""
        let kind = button?.effect.kindTag ?? .prompt
        kindPicker.selectItem(at: Self.kinds.firstIndex(of: kind) ?? 0)
        confirmationBox.state = (button?.confirmation ?? true) ? .on : .off
        keyField.stringValue = ""
        for box in modifierBoxes { box.state = .off }
        templateField.stringValue = ""
        clipboardField.stringValue = ""
        commandField.stringValue = ""
        if let effect = button?.effect {
            switch effect {
            case .keystroke(let key, let modifiers):
                keyField.stringValue = key
                for box in modifierBoxes where modifiers.contains(box.title) { box.state = .on }
            case .openURL(let template): templateField.stringValue = template
            case .copyTemplate(let text): clipboardField.stringValue = text
            case .prompt(let action): promptPicker.selectItem(withTitle: action.title)
            case .relay(let page): pagePicker.selectItem(withTitle: page.title)
            case .quickAction(let id):
                if let index = quickActions.firstIndex(where: { $0.id == id }) { quickActionPicker.selectItem(at: index) }
            case .pluginCommand(let plugin, let command):
                if let index = plugins.firstIndex(where: { $0.id == plugin }) { pluginPicker.selectItem(at: index) }
                commandField.stringValue = command
            }
        }
        kindChanged()
        makeKeyAndOrderFront(nil)
    }

    @objc private func kindChanged() {
        let kind = Self.kinds[max(0, min(kindPicker.indexOfSelectedItem, Self.kinds.count - 1))]
        let visible = kindChildren(kind)
        for index in 0..<kindRows.arrangedSubviews.count {
            let row = kindRows.arrangedSubviews[index]
            let show = visible.contains(index)
            row.isHidden = !show
            row.subviews.forEach { $0.isHidden = !show }
        }
        hintLabel.stringValue = kind.hint
        confirmationBox.isEnabled = kind.requiresConfirmation
        if !kind.requiresConfirmation {
            hintLabel.stringValue = kind.hint + " This effect cannot change another application's data, so no confirmation is required."
        }
    }

    /// Row indices (see `load`) that belong to each effect kind.
    private func kindChildren(_ kind: SiteButtonEffect.KindTag) -> Set<Int> {
        switch kind {
        case .keystroke: return [0, 1]
        case .openURL: return [2]
        case .copyTemplate: return [3]
        case .prompt: return [4]
        case .relay: return [5]
        case .quickAction: return [6]
        case .pluginCommand: return [7, 8]
        }
    }

    private func save() {
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = iconField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = Self.kinds[max(0, min(kindPicker.indexOfSelectedItem, Self.kinds.count - 1))]
        let modifiers = modifierBoxes.filter { $0.state == .on }.map { $0.title }
        let pages = SiteControlsPolicy.relayablePages.sorted { $0.title < $1.title }
        let effect: SiteButtonEffect
        switch kind {
        case .keystroke: effect = .keystroke(key: keyField.stringValue, modifiers: modifiers)
        case .openURL: effect = .openURL(template: templateField.stringValue)
        case .copyTemplate: effect = .copyTemplate(text: clipboardField.stringValue)
        case .prompt: effect = .prompt(PromptAction.allCases[max(0, min(promptPicker.indexOfSelectedItem, PromptAction.allCases.count - 1))])
        case .relay:
            effect = .relay(page: pages[max(0, min(pagePicker.indexOfSelectedItem, pages.count - 1))])
        case .quickAction:
            guard let action = quickActions[safe: quickActionPicker.indexOfSelectedItem] else {
                present("Add a Quick Action in RelayBar first, or choose another effect.")
                return
            }
            effect = .quickAction(id: action.id)
        case .pluginCommand:
            guard let plugin = plugins[safe: pluginPicker.indexOfSelectedItem] else {
                present("Add a plugin in RelayBar first, or choose another effect.")
                return
            }
            effect = .pluginCommand(plugin: plugin.id, command: commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let button = SiteButton(id: editingID ?? "button-\(UUID().uuidString.prefix(6).lowercased())",
                                title: title, icon: icon.isEmpty ? nil : icon,
                                width: nil, confirmation: confirmationBox.state == .on, effect: effect)
        do {
            try SiteControlsPolicy.validate(button: button, ruleID: "button editor")
        } catch {
            present(error.localizedDescription)
            return
        }
        onSave?(button)
        orderOut(nil)
    }

    private func present(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "That button cannot be saved"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}

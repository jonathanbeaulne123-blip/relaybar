import Cocoa

@MainActor
public final class PluginSettingsView: NSPanel {
    private let pluginManager: PluginManager
    private let stackView = NSStackView()
    private let emptyLabel = label("No plugins installed in ~/Library/Application Support/RelayBar/plugins/", secondary: true)
    
    public init(pluginManager: PluginManager) {
        self.pluginManager = pluginManager
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        
        self.title = "RelayBar · Installed Plugins"
        self.isReleasedWhenClosed = false
        self.center()
        
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 12
        container.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        
        let header = label("PLUGINS & EXTENSIONS", size: 14, weight: .bold)
        let subheader = label("Drop plugin folders with a manifest.json and executable scripts into the plugins folder.", size: 12, secondary: true)
        
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8
        
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = stackView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
        
        let openFolderBtn = ActionButton("Open Plugins Folder") {
            let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            if let pluginsDir = support?.appendingPathComponent("RelayBar/plugins", isDirectory: true) {
                NSWorkspace.shared.open(pluginsDir)
            }
        }
        
        let reloadBtn = ActionButton("Rescan Plugins") { [weak self] in
            self?.pluginManager.scan()
            self?.reload()
        }
        
        let closeBtn = ActionButton("Done") { [weak self] in
            self?.orderOut(nil)
        }
        
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [openFolderBtn, reloadBtn, spacer, closeBtn])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        
        container.addArrangedSubview(header)
        container.addArrangedSubview(subheader)
        container.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true
        container.addArrangedSubview(buttonRow)
        buttonRow.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true
        
        self.contentView = container
        reload()
    }
    
    public func reload() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        let plugins = pluginManager.plugins
        if plugins.isEmpty {
            stackView.addArrangedSubview(emptyLabel)
            return
        }
        
        for plugin in plugins {
            let card = NSStackView()
            card.orientation = .horizontal
            card.alignment = .centerY
            card.spacing = 10
            card.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
            card.wantsLayer = true
            card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            card.layer?.cornerRadius = 6
            
            let toggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            toggle.state = plugin.isEnabled ? .on : .off
            let pluginID = plugin.id
            toggle.target = self
            toggle.action = #selector(pluginToggled(_:))
            toggle.identifier = NSUserInterfaceItemIdentifier(pluginID)
            
            let info = NSStackView()
            info.orientation = .vertical
            info.alignment = .leading
            info.spacing = 2
            
            let title = label("\(plugin.manifest.name) v\(plugin.manifest.version)", size: 12, weight: .semibold)
            let desc = label(plugin.manifest.description, size: 11, secondary: true)
            let cmds = label("\(plugin.manifest.commands.count) commands · by \(plugin.manifest.author ?? "Community")", size: 10, secondary: true)
            
            info.addArrangedSubview(title)
            info.addArrangedSubview(desc)
            info.addArrangedSubview(cmds)
            
            card.addArrangedSubview(toggle)
            card.addArrangedSubview(info)
            stackView.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }
    }
    
    @objc private func pluginToggled(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        pluginManager.setEnabled(id, enabled: sender.state == .on)
    }
}

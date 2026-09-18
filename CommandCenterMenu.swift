import Cocoa

@MainActor
public final class CommandCenterMenu: NSObject {
    public let menu = NSMenu()
    public var onOpenPalette: (() -> Void)?
    public var onOpenOutput: (() -> Void)?
    public var onOpenPlugins: (() -> Void)?
    public var onAddQuickAction: (() -> Void)?
    public var onRunQuickAction: ((QuickAction) -> Void)?
    public var onRunWorkflow: ((Workflow) -> Void)?
    public var onRefreshGit: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    
    private let workspaceState: WorkspaceStateController
    private let pluginManager: PluginManager
    private var quickActions: [QuickAction] = []
    private var workflows: [Workflow] = []
    
    public init(workspaceState: WorkspaceStateController, pluginManager: PluginManager) {
        self.workspaceState = workspaceState
        self.pluginManager = pluginManager
        super.init()
    }
    
    public func update(quickActions: [QuickAction], workflows: [Workflow]) {
        self.quickActions = quickActions
        self.workflows = workflows
        rebuild()
    }
    
    public func rebuild() {
        menu.removeAllItems()
        
        // 1. Header: Project & Git State
        let state = workspaceState.state
        let projectName = state.detectedProject.name.isEmpty ? "No Active Project" : state.detectedProject.name
        let projectType = state.detectedProject.type != .unknown ? " (\(state.detectedProject.type.displayName))" : ""
        
        let headerItem = NSMenuItem(title: "⚡ RelayBar — \(projectName)\(projectType)", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        
        if !state.gitSnapshot.branch.isEmpty {
            let gitSummary = "\(state.gitSnapshot.statusIndicator) \(state.gitSnapshot.statusSummary)"
            let gitItem = NSMenuItem(title: "   \(gitSummary)", action: #selector(refreshGitClicked), keyEquivalent: "r")
            gitItem.target = self
            gitItem.toolTip = "Click to refresh git status"
            menu.addItem(gitItem)
        } else if !state.detectedProject.root.isEmpty {
            let noGit = NSMenuItem(title: "   ○ Not a git repository", action: nil, keyEquivalent: "")
            noGit.isEnabled = false
            menu.addItem(noGit)
        }
        
        menu.addItem(.separator())
        
        // 2. Command Palette Entry
        let paletteItem = NSMenuItem(title: "Command Palette…", action: #selector(paletteClicked), keyEquivalent: "p")
        paletteItem.keyEquivalentModifierMask = [.control, .option, .command]
        paletteItem.target = self
        menu.addItem(paletteItem)
        
        menu.addItem(.separator())
        
        // 3. Quick Actions Section
        let qaHeader = NSMenuItem(title: "⚡ QUICK ACTIONS", action: nil, keyEquivalent: "")
        qaHeader.isEnabled = false
        menu.addItem(qaHeader)
        
        for action in quickActions {
            let item = NSMenuItem(title: "  \(action.icon) \(action.name)", action: #selector(quickActionClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            item.toolTip = action.command
            menu.addItem(item)
        }
        
        let addActionItem = NSMenuItem(title: "  + Add Quick Action…", action: #selector(addQuickActionClicked), keyEquivalent: "")
        addActionItem.target = self
        menu.addItem(addActionItem)
        
        menu.addItem(.separator())
        
        // 4. Workflows Section
        if !workflows.isEmpty {
            let wfHeader = NSMenuItem(title: "🔗 WORKFLOWS", action: nil, keyEquivalent: "")
            wfHeader.isEnabled = false
            menu.addItem(wfHeader)
            
            for workflow in workflows {
                let item = NSMenuItem(title: "  \(workflow.icon) \(workflow.name) (\(workflow.steps.count) steps)", action: #selector(workflowClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = workflow
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        
        // 5. Plugins Section
        let plugins = pluginManager.plugins.filter(\.isEnabled)
        if !plugins.isEmpty {
            let pluginMenu = NSMenuItem(title: "🔌 Plugins (\(plugins.count) active)", action: nil, keyEquivalent: "")
            let sub = NSMenu(title: "Plugins")
            for plugin in plugins {
                let pHeader = NSMenuItem(title: "\(plugin.manifest.name) v\(plugin.manifest.version)", action: nil, keyEquivalent: "")
                pHeader.isEnabled = false
                sub.addItem(pHeader)
                for cmd in plugin.manifest.commands {
                    let cItem = NSMenuItem(title: "  \(cmd.icon ?? "•") \(cmd.name)", action: #selector(pluginCommandClicked(_:)), keyEquivalent: "")
                    cItem.target = self
                    cItem.representedObject = (plugin, cmd)
                    sub.addItem(cItem)
                }
            }
            sub.addItem(.separator())
            let managePlugins = NSMenuItem(title: "Manage Plugins…", action: #selector(pluginsClicked), keyEquivalent: "")
            managePlugins.target = self
            sub.addItem(managePlugins)
            pluginMenu.submenu = sub
            menu.addItem(pluginMenu)
        } else {
            let pluginItem = NSMenuItem(title: "🔌 Plugins…", action: #selector(pluginsClicked), keyEquivalent: "")
            pluginItem.target = self
            menu.addItem(pluginItem)
        }
    }
    
    @objc private func paletteClicked() { onOpenPalette?() }
    @objc private func refreshGitClicked() { onRefreshGit?() }
    @objc private func addQuickActionClicked() { onAddQuickAction?() }
    @objc private func pluginsClicked() { onOpenPlugins?() }
    
    @objc private func quickActionClicked(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? QuickAction else { return }
        onRunQuickAction?(action)
    }
    
    @objc private func workflowClicked(_ sender: NSMenuItem) {
        guard let workflow = sender.representedObject as? Workflow else { return }
        onRunWorkflow?(workflow)
    }
    
    public var onPluginOutput: ((String, String, Int32) -> Void)?
    
    @objc private func pluginCommandClicked(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? (Plugin, PluginCommand) else { return }
        let (plugin, cmd) = pair
        pluginManager.execute(plugin: plugin, command: cmd, projectRoot: workspaceState.state.detectedProject.root) { [weak self] output, code in
            self?.onPluginOutput?(cmd.name, output, code)
        }
    }
}

# RelayBar 1.0.0 — Workspace Command Center

Release 1.0.0 (Build 20) — September 17, 2026.

RelayBar expands from an AI assistant Touch Bar shell into a complete, native macOS **Workspace Command Center**.

---

## What’s New in 1.0.0

### 1. Workspace Awareness & Context Detection
* **Project Boundary Detection (`ProjectDetector.swift`):** Walks directory trees upward to automatically detect working project roots and languages (`Package.swift`, `Cargo.toml`, `package.json`, `pyproject.toml`, `go.mod`, etc.).
* **Live Git Monitor (`GitMonitor.swift`):** Pure-Foundation git parser tracking branch status, dirty count, staged/unstaged changes, and ahead/behind counts with compact status indicators.
* **Workspace Observer (`WorkspaceObserver.swift`, `WorkspaceState.swift`):** Live synchronization with active development tools (Terminal, iTerm2, Xcode, VS Code) without polling or keyloggers.

### 2. Quick Actions & Sequential Workflows
* **Quick Actions (`QuickAction.swift`, `ActionRunner.swift`):** Configurable shell commands with working directory resolution, hotkeys, and output capture. Includes default dev actions (`Git Pull`, `Git Status`, `Swift Build`, `Swift Test`, `NPM Dev`, etc.).
* **Multi-Step Workflows (`Workflow.swift`):** Chain multiple actions with step conditions (`always`, `previousSucceeded`, `previousFailed`), configurable delays, and failure recovery.
* **Quick Action Editor (`QuickActionEditor.swift`):** Native modal panel to configure, test, and save custom commands.

### 3. Command Palette & Floating Terminal
* **Command Palette (`CommandPalette.swift`):** Spotlight-style floating search bar (`⌃⌥⌘P`) featuring fuzzy search and smart usage ranking across git shortcuts, quick actions, workflows, and settings.
* **Action Output Panel (`ActionOutputPanel.swift`):** Monospaced floating utility window with real-time output streaming, duration timer, exit-code status, and clipboard export.
* **Command Center Menu (`CommandCenterMenu.swift`):** Rich status bar menu integrating the active project header, git indicator, one-tap actions, workflows, and plugins.

### 4. One Step Further: Plugin Architecture
* **Extensible Plugin System (`Plugin.swift`, `PluginManager.swift`):** Discovers plugins dynamically from `~/Library/Application Support/RelayBar/plugins/`.
* **Safe Manifest Schema:** Declares names, versions, commands, and executable scripts with path-traversal prevention.
* **Plugin Settings Panel (`PluginSettingsView.swift`):** Enable/disable individual extensions, rescan folders, or jump directly to the plugins folder in Finder.
* **Included Example Plugin (`Examples/plugins/git-shortcuts/`):** Shipped with ready-to-use git tools: `Quick Commit`, `Stash Pop`, `Branch Cleanup`, and `Undo Last Commit`.

### 5. Architectural De-Godding & Modern Tooling
* **Refactored Controllers:** Split the monolithic AppKit delegate into dedicated controllers: `StatusBarController`, `PanelController`, `HotkeyController`, `WorkspaceObserver`, and `SessionCoordinator`.
* **Consolidated Self-Test Runner:** Single entry point `Run_Self_Test.command` supporting `all`, `smoke`, `button-families`, `context-stack`, `pinned-chats`, and `screenshot`.
* **Diagnostics & Recovery:** `Doctor.command` now auto-builds missing binaries; `Fix_Access.command` dynamically inspects bundle versions; `Uninstall.command` supports `--force`.

---

## Unchanged & Preserved

All existing RelayBar capabilities remain 100% operational with their strict privacy guarantees:
* Native Touch Bar Persistent Shell & Apple Touch Bar handoff (``).
* Native Sheets Verified Click and menu cascade (extension-free, Accessibility-based).
* Pinned Chats navigation for ChatGPT & Claude.
* In-memory Context Stack with sensitive secret filtering.
* Screenshot Shelf with 5-image rolling window.
* Local file storage (0600/0700 POSIX permissions, no network calls, zero telemetry).

> Current update: **RelayBar 0.2 Screenshot Shelf**. Read `../START_HERE.md`, `SCREENSHOT_SHELF_DESIGN.md` and `VALIDATION_0.2.md`. The original text-workflow documentation below is retained for reference.

# RelayBar 0.1 — native Mac Touch Bar tools

A free, dependency-free, locally built Swift/AppKit prototype for ChatGPT and Claude. No BetterTouchTool, subscription to this helper, API key, API calls, telemetry, or cloud backend. Ordinary use of the assistants still follows your existing account's limits.

**Delivery status:** the full macOS source and installer are included. This package was produced in Linux, not on a Mac. The portable Swift engine passes 46 tests. macOS compilation, Accessibility capture, app routing, native window layout, and physical Touch Bar rendering have **not** been verified on hardware. This is not a notarized, ready-made Mac binary.

## Start here

Unzip the package into an ordinary local folder, such as Downloads. Review the source/scripts, then double-click **Install.command**. It compiles the included source with Apple's Command Line Tools, creates a locally ad-hoc-signed app, and installs it into **~/Applications/RelayBar.app**. No administrator password or paid Apple Developer membership is needed for this local build.

When Apple's free Command Line Tools are missing, the installer offers to launch Apple's installer. Complete that installation and run Install.command again. A full Xcode project and third-party package manager are not required. Target: macOS 12+ for RelayBar itself; the assistants may require newer macOS releases. Default build is for the machine's current architecture. `bash Scripts/build.sh --universal` requests both arm64 and x86_64.

The helper has **not** been installed remotely on your Mac. The included script performs the build there.

When Finder refuses to launch a downloaded script, inspect it and invoke it from Terminal with `bash ` followed by dragging **Install.command** onto the Terminal window. Do not disable Gatekeeper or System Integrity Protection. The installer does not run `sudo`, `curl`, Homebrew, or hidden download commands. A local ad-hoc signature is not notarization.

## First useful workflow

1. Open RelayBar from its **RB** menu icon, or press **Control–Option–Command–Space**.
2. Select **Hearth**, **Mandevilla**, **Bindery**, or **General**. Edit the starter brief before using it for real work. These are contextual starters, not imported source files or live repository snapshots.
3. Copy a passage from an assistant or editor, then click **Use clipboard**. Alternatively, grant optional Accessibility permission and use **Capture selection** to read just the selected passage. Whole conversations are never silently scraped.
4. Choose an action. The two contextual Touch Bar slots suggest **Diagnose / Add tests** for recognizable errors, **Explain / Add tests** for code, or **Tighten / Challenge** for prose. Auto is a local heuristic, not an AI service; Build, Review, and Writing override it.
5. Review and edit the draft. **Copy + Open** copies it and opens the chosen app or website. Click the desired chat's composer and paste with **⌘V**. It does not auto-paste or press Send.

The Touch Bar uses stable slots:

`[Assistant] [Project] [Capture] [Context action 1] [Context action 2] [Handoff] [×]`

The visible panel mirrors the same controls. Tap the assistant to cycle the destination. Tap the project to cycle briefs. **Switching projects clears the in-memory reference, task, and draft**, rather than accidentally carrying one project's material into another. Save a checkpoint first when needed.

**Handoff** switches the destination to the other assistant and composes an explicit packet. It does not transfer chat history or pretend the assistants share memory. The Action dropdown can also compose a handoff for the destination already selected.

## Two Touch Bar modes

**Standard mode (default):** public AppKit Touch Bar controls while RelayBar's own panel is active, with an onscreen mirror. When you return to another app, that app normally regains its own Touch Bar. The global shortcut brings RelayBar back.

**Experimental cross-app mode:** RB menu → Experimental cross-app Touch Bar → Enable for this session. This uses runtime-checked undocumented Apple APIs to request our bar while an identified ChatGPT/Claude desktop app or supported browser is frontmost. It is not an official ChatGPT or Claude Touch Bar extension.

The overlay is **off at every app launch**, is not persisted across crashes, and is never installed as a system patch. It is hidden for other apps. It can conflict with other Touch Bar utilities or fail on a macOS release. Runtime selector availability does not prove physical rendering.

Browser mode does not inspect tabs or URLs; choose the assistant destination manually. The bar can appear across all tabs of an allowlisted browser while this mode is enabled. Supported bundle identities are Safari, Chrome, Firefox, Edge, Arc, and Brave; this is not a claim of browser-specific content integration.

Recovery: use **RB → Hide cross-app Touch Bar**, the bar's **×**, or **Control–Option–Command–Space** to return to the panel. Quit RelayBar to remove its own session overlay. The code does not change Control Strip preferences, kill system UI processes, or synthesize Escape.

## Desktop app routing

The helper discovers known installed or running assistant apps and permits an explicit override through **RB → Choose ChatGPT application… / Choose Claude application…**. Use that override for renamed apps or newer unified ChatGPT/Codex bundles. It does not assume every app called Codex is ChatGPT. The picker controls launch destination only; no app internals are modified.

**Follow active desktop assistant** updates the destination for recognized apps only while no draft is prepared. It will not silently reroute an existing draft. Browser tabs are never used for assistant detection.

**Prefer desktop apps over browser** chooses desktop launch when a matching app is found; otherwise the public website is opened. Turn it off for browser-only use. Standard copy/open does not depend on undocumented chat app URL schemes.

**Prefill Claude…** is an optional, separately confirmed route using Claude's documented new-chat deep link. It opens a NEW chat with the prompt field prefilled for review; it never issues Send. RelayBar rejects drafts above its conservative 10,000-character limit instead of letting the documented approximate 14,000-character service limit truncate them. Text is passed through the operating system's `claude://` URL handler; use ordinary Copy + Open for sensitive or long packets. This does not verify who owns the URL handler on a modified system.

## Project briefs and checkpoints

Settings and briefs: `~/Library/Application Support/RelayBar/projects.json`.

Checkpoints: `~/Library/Application Support/RelayBar/Checkpoints/`.

Briefs are user-maintained local context. No source repositories, Downloads folders, conversations, ledgers, or models are scanned. Edit them through the panel or add a project from the RB menu.

Captures and drafts remain in memory until **Save checkpoint…** is explicitly confirmed. A checkpoint stores the exact brief, constraints, reference, task, destination, and reviewed draft as **unencrypted JSON**. It labels its contents as user-supplied and unverified. **Load checkpoint…** restores that packet after a confirmation; it does not verify its claims. Existing checkpoint files are not edited. Restoring a checkpoint restores its saved project brief, replacing the current brief for that project after the confirmation.

Files are written with owner-only permissions (0600), directories with 0700, and saved through an atomic rename. These permissions are not encryption and do not stop apps already running as you or your own backup/sync software from accessing them. No password, API key, OAuth token, or Keychain access is requested. Corrupt settings are left untouched and disable configuration writes for that session.

**Clear** clears this session's text from RelayBar, not previously saved checkpoints or the system clipboard.

## Verification and troubleshooting

- **Test.command** reruns the portable Swift tests locally and saves output to BuildLogs.
- **Doctor.command** reports the macOS/toolchain, local code-signing validity, Accessibility authorization, and presence of overlay selectors. It then constructs native controls as a smoke test. It does not capture any text, open an assistant, or certify Touch Bar hardware rendering.
- **Docs/MAC_ACCEPTANCE.md** is the required on-device checklist.
- Installation errors are preserved in **BuildLogs/install-….log**. Build failures must be resolved before claiming a successful installation.

Grant Accessibility to the **installed** RelayBar app only when using selection capture. Browser/Electron selections may not be exposed; the explicit clipboard route remains available. A rebuild may require re-granting Accessibility because the local ad-hoc binary changes. Do not grant Full Disk Access or Screen Recording for this version; it has no use for them.

Other Touch Bar customizers may compete with the experimental overlay. Disable RelayBar's overlay first. The normal panel remains the primary recovery path. If the shortcut conflicts, the RB menu remains accessible; there is no global key logger or event tap.

**Uninstall.command** removes the installed app only after confirmation. It preserves local project/checkpoint data unless you separately type DELETE. Source/build folders and backed-up older apps are left in place. The installer makes no login item or daemon.

## What 0.1 does not do

No live assistant usage meter, model-setting control, background reasoning, code execution, agent approval, automatic screenshot attachment, chat-history sync, filesystem search, or autonomous sending. The UI review action reviews supplied text and explicitly notes when no screenshot is attached. Real Claude Code/Codex lifecycle hooks can be a later, separately scoped integration; no fictional progress or status is shown here.

## Package map

- `Sources/Core/`: project models, prompt assembly, heuristics, local storage.
- `Sources/Mac/`: native panel, menu, Touch Bar slots, app routing.
- `Sources/Bridge/`: hotkey/selected-text access and isolated experimental overlay adapter.
- `Scripts/`: local compiler and geometric icon builder.
- `Tests/RelayCoreTests/`: portable engine tests.
- `RelayBar_Preview.html`: offline browser workbench, not a Mac app or Touch Bar controller.
- `Docs/`: validation, privacy, acceptance checks, and reference sources.

MIT licensed. No third-party runtime dependency or vendored Touch Bar project. Not affiliated with Apple, OpenAI, or Anthropic.

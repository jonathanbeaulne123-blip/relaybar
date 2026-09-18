# RelayBar 0.9.1 — Persistent Shell Build Fix

**One RelayBar product, always available after login. No browser extension and no per-spreadsheet setup.**

Native version **0.9.1, build 17**. This release keeps the working 0.8.2 unified product—including Verified Click for Google Sheets/Hearth Tools, adaptive menu scanning, Menu Cascade, Screenshot Shelf, Button Families, Context Stack and Pinned Chats—and adds a persistent Touch Bar shell around it.

## 0.9.1 build fix

The first 0.9.0 package stopped during Mac compilation because a Boolean parameter named `showPanel` shadowed the `showPanel()` method in `AppMain.swift`. 0.9.1 renames only the local parameter binding (`showPanel shouldShowPanel`) and preserves the external call label and Persistent Shell behavior. The failed 0.9.0 installer stopped before replacing the installed app.

## The new Touch Bar shell

While RelayBar mode is active the bar is:

**`[ contextual RelayBar controls ……………………… ]   [ Chrome ] [ Claude ] [ ChatGPT ] [  ]`**

The right side is fixed:

- **Chrome** — icon-only when Chrome is installed. Activates the running app or launches it. Once Chrome is foreground, RelayBar follows the live context: a Google Sheet gets the native Sheet/Hearth controls; an ordinary tab gets RelayBar’s browser/app context.
- **Claude** — activates or launches the configured/installed Claude desktop app and switches RelayBar to its associated controls.
- **ChatGPT** — activates or launches the configured/installed ChatGPT desktop app and switches RelayBar to its associated controls.
- **** — far-right escape hatch. It dismisses RelayBar’s cross-app Touch Bar and hands the strip back to macOS. Ordinary app switches **do not** steal the bar back. Use **RB → Return RelayBar Touch Bar** when you deliberately want RelayBar again.

If an app cannot be found, its shell button is disabled instead of silently failing. The three app buttons and  remain visible on every RelayBar page, including the screenshot viewer. They disappear only when you deliberately choose the default macOS Touch Bar or pause the persistent shell.

## Install once

1. Quit the running RelayBar from the **RB** menu.
2. Extract this ZIP into its own `RelayBar_0.9_Persistent_Shell` folder. Do not merge source folders in Finder.
3. Run **`Install.command`**. It compiles locally, verifies the staged app, backs up the previous `~/Applications/RelayBar.app`, installs 0.9 there, and enables a user-only login item unless you had previously disabled RelayBar login launch.
4. Open RelayBar. Persistent RelayBar mode is on by default. Your screenshot settings, project data and existing native-control preferences remain local and are not deleted.
5. For Google Sheets/Pinned Chats, keep **RB → Settings → Native controls** enabled. If macOS loses RelayBar’s Accessibility approval after the locally rebuilt app is installed, use the included **`Fix_Access.command`** and re-approve the exact `~/Applications/RelayBar.app` copy.

There is no Chrome extension, Apps Script file, sidebar, API key or per-workbook setup.

## “Always on” behavior

`Install.command` creates this user LaunchAgent by default:

`~/Library/LaunchAgents/local.relaybar.login.plist`

It opens the installed `~/Applications/RelayBar.app` at login without intentionally stealing foreground focus. RelayBar is a normal menu-bar app and remains running after its panel closes.

You can change this later from **RB → Launch RelayBar at Login**. This preference is respected by later 0.9 installs.

### Pause vs macOS mode

- ** Mac button / RB → Use macOS Touch Bar**: relinquishes the whole strip to the normal Mac Touch Bar and stays there across ordinary focus changes.
- **RB → Pause Persistent Touch Bar**: pauses RelayBar’s cross-app shell. Choosing it again (or **Return RelayBar Touch Bar**) resumes.
- **RB → Return RelayBar Touch Bar**: explicitly restores the persistent shell.
- Quitting RelayBar still quits it for the current login session. The login item starts it again on your next login unless disabled.

Context Stack collection and native menu interactions are paused when RelayBar’s persistent bar is paused or handed back to macOS. RelayBar does not keep collecting in the background while its shell is intentionally unavailable.

## Fork Reality MVP

RelayBar now has a portable first slice of Fork Reality for Git-backed projects. A reality snapshot stores the reviewed RelayBar checkpoint together with the observed project/Git state and bounded context metadata in the private `Realities` directory. `RealityForker` can create a separate Git worktree and branch from a clean recorded commit, leaving the current worktree untouched.

Forking now captures a bounded dirty state: tracked changes are stored as a binary Git patch and ignored-excluded untracked regular files are copied into the private reality record. The fork materializes both into a new worktree and rolls the worktree back if patch application or file verification fails. It never resets, stashes, or overwrites the source project. Oversized, symlinked, ignored, or unsafe files are refused rather than guessed.

It still does not overwrite the clipboard, scrape AI conversations, or claim to restore arbitrary app windows. The timeline’s **Files** action lists added/modified/deleted/renamed/binary/untracked paths and shows a read-only tracked patch preview. Users can select complete files or individual text hunks and apply them to an existing fork worktree only after Git preflight and confirmation; failed materialization attempts roll back the tracked patch. Binary changes remain file-level only. Supported Chrome-family tab metadata is now captured in realities, and an explicit restore requests safe HTTP(S) tabs through the existing AppleScript bridge; unsupported browsers, unsafe URLs, and unavailable browser automation are reported without changing tabs.

Use **RB → Show Reality Timeline** to review saved moments. After a reviewed draft is composed, RelayBar makes a best-effort local semantic checkpoint when it can identify the active Git project; screenshot milestones also create checkpoints. The timeline can restore RelayBar’s project/reference/task/draft state, show **What Changed?**, or fork a saved clean Git reality into another worktree. Touch Bar `‹` / `◉ time` / `›` controls scrub saved moments; `FORK` opens the full native timeline before any state-changing action.

Reality files use the same local-only atomic JSON storage and `0700`/`0600` permissions as checkpoints. A failed or invalid snapshot is rejected without changing existing data.

## Existing working features retained

| Area | Behavior in 0.9 |
|---|---|
| **Google Sheets / Hearth Tools** | Same 0.8.2 path: native macOS Accessibility, adaptive large-tree scan, Menu Cascade, and one verified physical click for Chrome-family Sheet controls after fresh target/frame/hit-test validation. No AXPress-then-click fallback and no automatic retry. Leaf actions keep confirmation on by default. |
| **App-aware routing** | Focusing a detected Google Sheet enters Sheet controls. Leaving it returns to the normal RelayBar hierarchy. The new global shell can remain visible over other foreground apps instead of disappearing outside the old allowlist. |
| **Screenshots** | New screenshots still auto-open the five-image shelf. Only the contextual region changes; Chrome, Claude, ChatGPT and  stay on the right. Tapping an image copies the full-resolution image for manual ⌘V; RelayBar never auto-pastes or sends it. |
| **Button Families** | Prompting · Context · Chats · Workspace · Settings, with the same Back/Home hierarchy and generation guards. |
| **Context Stack** | Explicit collection/review/pack flow remains local/in-memory unless you explicitly save elsewhere. |
| **Pinned Chats** | Reads exposed pinned/starred metadata only while that feature is active, with stale-target checks and explicit navigation. |
| **Prompt/project tools** | Existing prompt composition, project choices, checkpoint, destination and review controls remain explicit. |

## App discovery

The shell identifies apps by installed application bundle rather than hard-coded executable paths.

- Chrome: `com.google.Chrome`
- Claude: `com.anthropic.claudefordesktop` (or the Claude app path you selected in RelayBar)
- ChatGPT: `com.openai.chat` (or the ChatGPT app path you selected in RelayBar)

RelayBar checks the configured app first where applicable, then standard `/Applications` and `~/Applications` locations. Pressing an app pin is the only thing that launches/activates that app; ordinary polling never launches software.

## Privacy and safety boundaries

Accessibility is a broad macOS permission. RelayBar’s native Sheet scanner keeps the existing bounded/read-only discovery model and excludes cell contents, page URLs, workbook titles and script source from its diagnostic report. Existing Verified Click sends at most one pointer click after a fresh target check and does not retry uncertain execution.

The persistent shell itself does not add browser JavaScript, network calls, screen recording, OCR, key injection or a browser extension. The login item is a local user LaunchAgent, not a privileged daemon.

## Validation boundary

The complete portable/unified regression suite was run after this merge. Notable results include:

- **427 Swift tests** passed, zero failures.
- **176** production Button Families adapter checks passed with explicit AppKit/feature doubles, including fixed shell placement, Mac handoff/return and Chrome-pin activation path.
- **24** Native Sheets controller checks and **30** native adapter/scan checks passed; Verified Click remains the same production path that was working in 0.8.2.
- **21** Button Families wiring checks, **43** hierarchy-map checks, **22** Context Stack checks, **23 + 41** Pinned Chats controller/wiring checks, **14** screenshot auto-open contracts, **16** build-repair checks, **13** unified-product checks and **10** persistent-shell source contracts passed.
- Browser preview: **21 checks**, zero observed runtime network requests or JavaScript exceptions.
- Swift source parsing and shell-script syntax checks passed.

**Still unverified here:** macOS SDK compile/link/signing of 0.9, running the 0.9 installer on your Mac, LaunchAgent behavior on your actual login session, installed-app icon rendering, physical Touch Bar spacing, and real app-launch/focus behavior. The existing 0.8.2 Sheets click path was user-confirmed working before this shell merge; that does not automatically prove every new 0.9 shell behavior on hardware.

See `Docs/VALIDATION_0.9.md` for the exact boundary and `CHANGELOG_0.9.md` for the source-level changes.

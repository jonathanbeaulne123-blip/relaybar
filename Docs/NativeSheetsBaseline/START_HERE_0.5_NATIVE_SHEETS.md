# RelayBar 0.5 — Native Sheets

**An extension-free native app update. No Google Sheet or Apps Script setup.**

## Install once

1. Quit the running RelayBar from **RB → Quit RelayBar**. Open **Install.command** in this folder. It builds this source on your Mac, backs up the previous RelayBar app and installs into `~/Applications/RelayBar.app`.
2. In RelayBar, choose **Enable native app controls**. Turn on **RelayBar** in **System Settings → Privacy & Security → Accessibility** if macOS asks. Return to your spreadsheet.

The first launch offers that same Enable button. If macOS retains RelayBar’s existing permission, no new grant is needed; otherwise approve the updated app. No browser extension, API key, Google Cloud project, Apps Script files, sidebar, function registration or per-workbook connection is involved. Do not run the older Sheets setup packages.

The original cross-app Touch Bar remains experimental and starts **OFF on each app launch**. The Enable command starts it for the current session; use **RB → Enable native app controls** after a later restart. There is no setup to repeat when changing spreadsheets.

## Use it

With a supported browser foreground, RelayBar reads the current page identity through native macOS Accessibility. On a Google Sheet, it mirrors exposed top-level menus. Recognized custom menu names are sorted before the standard English menu names; other languages are not excluded. Four controls fit on a page; the page button cycles through the rest.

Tap a menu to open that actual menu in Sheets. Its exposed actions appear on the Touch Bar. Nested open menu items appear before their parents. **Menus** returns the Touch Bar to its top-level list without sending a keyboard shortcut or closing the page menu.

Leaf actions ask for confirmation **on the Touch Bar**, without activating a RelayBar window. A confirmation expires after eight seconds. Menu navigation is immediate. **RB → Ask before activating menu actions** is one global setting; turning it off requires an explicit acknowledgement that actions may change data or send messages.

No script runs on an app switch or during menu discovery. RelayBar requests the existing UI action; it does not call arbitrary function names or infer what a script does. A reported successful AX request is not evidence that an Apps Script finished successfully. Unknown/failed requests are not automatically retried.

## What is included — and what is not

The native browser adapter is allowlisted for **Chrome, Edge, Brave, Chromium and Safari**. These are implementation targets, not certified live-browser results. Firefox, Arc and embedded in-app browsers do not have native Sheets support in this build. Desktop ChatGPT/Claude controls remain available. Other native apps retain their own Touch Bar.

This is a **menu mirror**, not an Apps Script source inventory. It needs an exact exposed page URL and usable accessible menu controls. Canvas-only drawing buttons, inaccessible objects and functions that exist only in the script editor cannot be discovered by this adapter. Controls are not invented when a browser does not expose them. A menu must be opened before lazily created submenu entries can be read.

If a Sheet is detected but its menus are not available, the Touch Bar reports that state. **RB → Native connection report** shows permission state, browser identity, page kind and control counts. Its Copy button explicitly copies a report with **no page URL, workbook title, cell contents, script source or screenshots**. No additional extension or per-sheet workaround is installed.

## Screenshot viewer and existing data

The screenshot watcher, five-image cache, full-image clipboard copy engine, auto-open state machine, Touch Bar renderer, original Objective-C cross-app bridge, build script and compiler-compatibility helper are unchanged from the actual v0.3 native foundation. The selected screenshot folder, cache and existing project data are retained.

A newly collected screenshot still opens the screenshot page and cancels pending native-menu confirmation. Tap a thumbnail to copy its full image; use Command–V yourself. No automatic paste or send is added. **Sheets/Tools** returns to the current contextual controls. Collection still waits for a file to finish saving in the selected folder; clipboard-only captures use the existing explicit import.

## Privacy and pause

This is a broad macOS permission; grant it only to software you trust. The new adapter reads roles, menu labels, geometry, focus/element identity and the current web-area URL. It stops before traversing cell grids and text-content nodes; there is no AXValue or selected-text accessor in the menu engine. Metadata stays in memory, not a browsing-history file. The original user-triggered selected-text Capture feature remains separate. Accessibility does not reliably identify private/incognito mode: an active private Sheets window may also be mirrored while enabled. Pause detection for private work; background windows are not scanned.

No key injection, coordinate click, AppleScript, web JavaScript, remote-debugging port, HTTP server, cookie access, screen recording, OCR or external service was added. Screen Recording and Automation permissions are not requested by this feature. Executing an existing menu action still has that action's normal effects and Google authorization requirements.

Scanning uses a serial worker, per-call timeouts and bounded traversal. For Chromium-family browsers it may request an accessibility tree through a supported runtime attribute. That can increase the browser's resource use. RelayBar does not change browser preference files or turn accessibility flags off underneath another assistive tool; the browser may retain its tree until it exits.

Pause with **RB → Native Google Sheets menu detection**, hide cross-app controls, or revoke Accessibility in System Settings. Pending/queued requests are cancelled where possible; an action already delivered to a browser cannot be undone by closing RelayBar. Target validation is a best-effort check, not an atomic lock on a remotely rendered page.

## Validation and rollback

See **Docs/VALIDATION_0.5.md** for actual results and the remaining Mac acceptance checks. This package is source, not a precompiled or notarized application. Linux tests and explicit service doubles do **not** prove Mac SDK compilation, live browser compatibility or physical Touch Bar behavior.

The installer prints the previous app's backup path. Quit the new app before restoring that backup. It does not delete your existing projects or screenshots. Advanced checks are in **Diagnostics/**; they are not installation steps. The browser preview and old reports under the package/history are historical and do not simulate this native feature.

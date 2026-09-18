# RelayBar 0.5 — Context Stack

**Copy pieces once. Hand them over together.**

Context Stack is a native addition to your actual RelayBar source, not a replacement app or a browser mock. It builds on the native 0.3 release and includes the newer automatic 0.4 Sheets adapter. The native app reports **0.5.0**; the unchanged browser adapter reports **0.4.0**.

## The useful bit

Tap **Stack → Collect**, then copy your requirements, a code fragment, an error, and an earlier answer with Command–C. Each new eligible copy becomes a separate excerpt. Tap **Pack 4** to put those four excerpts on the clipboard as one ordered handoff, ready for Command–V in your chosen assistant. Copying the handoff pauses collection. Nothing is pasted, sent, run, or opened by the copy action.

The last three excerpts appear on the Touch Bar. Tapping one copies its full original text, not its shortened label. **Review** reaches the entire stack: inspect the full text, exclude a passage from the handoff, move it earlier/later, remove it, or preview the complete packet. Original indentation, Unicode, and line endings are preserved inside each excerpt. No model call is involved in assembling the packet.

## Install this update

1. **Copy out any Context Stack content or save unfinished draft/checkpoints first.** Disable the RelayBar browser extension temporarily if installed, then choose **RB → Quit RelayBar**. The extension can otherwise keep a native host process running.
2. Extract this ZIP to its own **RelayBar_0.5_Context_Stack** folder. Do not merge source folders. Double-click **Install.command** inside this new folder. It builds locally with the existing compiler repair helper, preserves the previous app as a backup, and installs to `~/Applications/RelayBar.app`.
3. Re-enable the existing browser extension. The native installer does **not** replace the managed extension, reset its ID, or register it again. Existing automatic Sheets users need no browser or workbook setup for this feature.
4. In RB, re-enable **Experimental cross-app Touch Bar → Enable for this session** to use the physical bar while an assistant or supported browser is active. This remains OFF at every launch. Choose **Stack** on the Touch Bar, or **RB → Context Stack → Show Context Stack on Touch Bar**. The regular RelayBar panel and its onscreen buttons remain available without cross-app mode.
5. Tap **Collect** and approve the feature's explanation. It starts with FUTURE copies only. The system may separately request clipboard access. RelayBar does not bypass or change the OS permission.

This is a **source update**, not a precompiled or notarized app. It has not been installed or physically tested on your Mac here. The inherited installer backs up the old app and retains screenshot data, app preferences, project briefs, and saved checkpoints.

## A first useful test

Open your assistant. Tap **Stack → Collect**. Copy a requirement, then a short code excerpt, then an error. Check that **RB ●3** appears in the menu bar and **Pack 3** on the stack page. Tap Review: all three should be present in copy order, with full text available. Exclude one; the handoff count becomes two. Copy the handoff, then manually paste into an unsent draft. Collection should now be paused and both excerpts should be intact.

Use synthetic/non-private text for this test. The local native self-test is **Context_Stack_Test.command**; it builds and uses a separate named pasteboard, not your current clipboard, and does not replace the app. It does not replace a physical Touch Bar acceptance check.

## How it behaves

- **Collect is explicit, not permanent clipboard history.** It runs for up to 15 minutes per start/resume. Pause, Copy handoff, a project switch, sleep/display sleep/session change, an interruption longer than five seconds, hiding the cross-app bar, or quitting stops it. Starting/resuming does not import what was already on the clipboard.
- **Up to 20 clips per project.** The text limit is 64 KiB per clip and 256 KiB total per project. A full stack stops collecting instead of throwing away earlier excerpts. Oversized copies are rejected whole, never silently truncated. Exact byte duplicates keep their original position and inclusion state. At the app's 100-project limit, the maximum retained clip text is 25 MiB; the optional manual-input drafts add up to 6.25 MiB.
- **Projects stay separate.** Changing the selected RelayBar project pauses collection and opens that project's own in-memory stack. Return to the earlier project to recover its clips during the same app session. App/browser switches do not switch the project. Nothing mixes merely because you moved between assistants.
- **Memory only.** Stack text and manual-input drafts are not saved to RelayBar's disk storage and do not survive Quit, a crash, or restart. Clear removes the current project's in-app stack and draft only. Copying a clip/handoff deliberately writes to the system clipboard, which is a separate system facility: OS synchronization and other clipboard apps are outside RelayBar's control. Clear/Quit does not erase copies already pasted or copied elsewhere. No claim of forensic secure erasure is made.

## Privacy and limitations

While Collect is on, eligible copied text from any app can be collected, including text you did not intend to hand off. The polling interval is 0.2 seconds while the main run loop is running. It is not a lossless copy-event log: multiple copies between polls can be missed. Check the count and preview; **Paste clip** explicitly imports the current clipboard once, and the Review panel has a normal manual-paste input as a fallback.

Known confidential/transient/automatic/restored/remote clipboard markers are rejected before reading their text. Password-manager and password-system foreground apps are excluded; some obvious key/token patterns are also filtered. **These checks cannot reliably identify every unmarked password, secret, private browser page, or sensitive document. Do not copy secrets while collecting.** Labels and full excerpts can appear on the Touch Bar and in Review.

App labels say **Observed in…**. They describe the frontmost app at observation time, not a verified source, author, browser tab, repository, or transcript. Manual imports are labelled source unknown. No screen capture, OCR, keystroke monitoring, browser scraping, model API, or credential setup is added by Context Stack.

Only single-item plain text (including compatible copied URLs) is collected. Images, file drags/file URLs, multi-item pasteboards, and rich-text-only items are not silently converted. The screenshot shelf remains the place for images. New screenshots retain their existing auto-open priority; tap Stack to return to the text stack. Clipboard writes and new arrivals do not automatically paste, press Enter, switch assistants, or execute code.

The original overlay allowlist is unchanged. Collection can observe a copy made in an editor/Terminal, but those apps still keep their native Touch Bars; use the RB menu or return to an assistant/browser for the RelayBar strip.

## Sheets compatibility

**Already on automatic Sheets (extension 0.4):** just re-enable your existing extension after the native update. No workbook edits, sidebars, or new extension install.

**Have the older 0.3 browser link:** run `Automatic_Sheets_0.4/Make_Sheets_Automatic.command`, reload RelayBar on the browser extensions page, and refresh already-open Sheets tabs. This included updater now explicitly accepts native versions 0.3.0 and 0.5.0. It preserves the extension's existing managed path and ID. Rollback is provided alongside it.

**No browser link installed:** `Set_Up_Sheets.command` is optional first-time setup. It installs the included automatic adapter once. No per-spreadsheet scripts, `onOpen` changes, function registry, or RelayBar sidebar are needed. Context Stack itself does not require the browser extension.

The automatic adapter mirrors compatible exposed menus and accessible controls. It is not a crawler of hidden Apps Script functions and cannot guarantee arbitrary canvas-only controls. Action confirmation remains enabled by default. Historical AppsScript files and v0.3 documentation are preserved for provenance only; do not follow their old setup steps for this release.

## Verification and rollback

See **Docs/ContextStack/VALIDATION.md** for results actually obtained and explicit untested areas. The current portable suite runs with `Test.command` (or `swift test`). The Mac-only check is `Context_Stack_Test.command`; the original `Screenshot_Test.command` remains included.

To roll back the native app, quit RelayBar and disable its extension temporarily. In `~/Applications`, keep the new app separately and restore the prior **RelayBar Previous … .app** backup as `RelayBar.app`. Do not delete Application Support. The 0.4 browser adapter is compatible with both the prior 0.3 native app and this 0.5 source. The native installer did not alter the managed extension.

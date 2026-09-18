# Screenshot Shelf — implementation map

## Baseline

Work starts from the actual supplied `RelayBar_v0.1.1_Compiler_Repair.zip`, not a recreated Touch Bar app. The original Bridge files and `Scripts/toolchain.sh` remain byte-identical. App identity remains `local.relaybar`; version is now 0.2.0. The existing LocalStore / Models / PromptEngine are unchanged, so existing briefs, project IDs, app overrides and checkpoints use the same storage format. App update installation backs up the previous app only after the replacement has built and passed local signature validation.

## Files

`Sources/Core/ScreenshotShelf.swift` contains the recognition policy, bounded manifest, quiet-file gate and private cache. It is genuinely compiled/tested without AppKit. Its byte storage intentionally does not pretend to decode images.

`Sources/Mac/ScreenshotShelfMac.swift` contains the serial file worker, folder event source, 3-second fallback scan, ImageIO preparation, clipboard payload generation and main-thread controller. The input folder is read-only. No child directories are traversed. At most 32 recent eligible candidates are considered for decoding; only five committed images are retained. A stable file must be seen twice, at least 0.5 seconds apart and 0.5 seconds after its modification time. Directory events debounce at 0.25 seconds; unsettled files are rechecked. The reader uses O_NOFOLLOW and validates descriptor state before and after a bounded read. Complete single-image decoding and dimensions are checked before insertion. A failed version is retried up to three times; a changed version is eligible again. No filesystem-notification mechanism is claimed infallible.

`Sources/Mac/AppMain.swift` adds a screenshot page, an RB submenu, onscreen controls, and startup/shutdown wiring. New captures switch to the screenshot page without opening/activating the panel. Full image copying has no call to showPanel, activate, synthetic key events or Send. Existing assistant matching and cross-app permission/session rules are unchanged. The original tools remain on a separate page.

`Sources/Mac/Components.swift` extends real NSCustomTouchBarItem buttons to include images, enabled states and narrow widths. Each live screenshot uses its stable UUID as the Touch Bar item key. A removed item is disabled and its thumbnail discarded; it cannot silently copy a different screenshot that took its former position. Current actions are looked up by key. New copy requests supersede older asynchronous requests, so a slow old request does not overwrite a newer tap's clipboard result.

`Sources/Mac/ScreenshotNativeChecks.swift` implements `--screenshot-self-test`: real ImageIO encoding/decoding, full PNG and TIFF pasteboard representation, native image-button construction/update, a real watched temporary directory, rolling retention, clear/watermark and a new-file event. It uses only synthetic files and a named private test pasteboard, never NSPasteboard.general. This test must be run on a Mac; its source is not evidence it passed.

## Retention transaction

1. Validate a decoded candidate's entry and normalized PNG size.
2. Reject duplicate source versions, captures at/before the clear watermark and arrivals too old to enter a full shelf.
3. Form a new top-five manifest sorted by capture time, with deterministic tie-breaks. Updating a stable source replaces its existing entry, not an extra slot.
4. Create a private temporary data file and atomically rename it into the cache.
5. Atomically commit the new index. On failure, remove the new cache entry and retain the previous in-memory manifest/data.
6. Prune only unreferenced UUID-named PNGs and recognizable temporary files in this tool's own cache. No source path is deleted. A cleanup failure is surfaced; no secure-erasure claim is made.

`Clear` first commits an empty manifest plus a time watermark, then removes managed cache entries. Later scans/relaunches ignore older files. Unreferenced files left by an interrupted transaction are pruned after a valid index is loaded. A corrupt index is preserved and reported, not silently reset. Corrupt/missing cache images fail explicitly when copied. The existing OS/file owner is a trust boundary; this is not protection from a malicious process with the same user privileges.

## Clipboard semantics

Image arrival never changes the clipboard. A user tap requests the selected UUID's PNG from the serial worker and builds a full-size TIFF compatibility representation. Only after payload preparation succeeds does the main thread replace the General pasteboard with one image item. PNG is mandatory; TIFF is included when successfully encoded. The item includes a RelayBar image-ID marker but no file URL or text path. User presses Command–V separately. Explicit `Add clipboard image` can import clipboard-only captures; it is not background clipboard monitoring.

## Known limits

This feature observes completed screenshot files, not the act of pressing a capture shortcut. Floating-thumbnail editing delays ingestion. Clipboard-only captures require explicit import. Third-party naming or missing metadata can defeat automatic recognition; screenshots larger than the documented safety limits are not collected. Existing native PNG bytes are kept, while normalized non-PNG formats may not preserve every HDR/metadata property. The screenshot collection folder is explicit and remembered; changing the OS save location does not silently change our consent scope. Stop/resume catches up with recent eligible files.

The underlying private cross-app overlay remains opt-in/off at each launch and may be affected by OS/app changes. Displaying thumbnails in the screenshot page, switching pages during an active overlay, and pasting into the actual assistants are native acceptance tests, not proven by the Linux test suite. No new system/private API was added to the bridge.

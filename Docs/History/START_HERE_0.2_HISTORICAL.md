# RelayBar 0.2 — Screenshot Shelf

A native update to the working RelayBar 0.1.1 foundation. No BetterTouchTool, paid libraries, AI API calls or account credentials.

## Install this update

1. Save any unfinished text draft/checkpoint, then choose **RB → Quit RelayBar**.
2. Unzip this package into its own **RelayBar_0.2_Screenshot_Shelf** folder. Do not merge it into an older source folder.
3. Run **Install.command from this new folder**. The 0.1.1 compiler compatibility check is included unchanged. Existing project briefs, assistant application overrides and checkpoints are retained. A successfully built app replaces `~/Applications/RelayBar.app`; the previous app is backed up first and its path is printed.
4. Open **RB → Screenshot Shelf → Choose screenshot save folder…**. Pick the same folder selected in macOS Screenshot's **Options → Save to**. Desktop is the usual starting suggestion. Confirm only the folder you want RelayBar to read.
5. Re-enable **RB → Experimental cross-app Touch Bar → Enable for this session**, as in the working version. This still resets off whenever RelayBar launches. Selecting a screenshot folder is remembered separately.
6. Return to ChatGPT or Claude. Do not tap the strip's **×** during this test: it intentionally disables cross-app mode.

The HTML preview from 0.1 is still included as a historical text-workflow demo. It does not install this native feature or change the physical Touch Bar.

## Everyday use

Take a screenshot normally with Shift–Command–3, Shift–Command–4, or the Screenshot app opened with Shift–Command–5, configured to save an image file in the selected folder. Once macOS has actually saved it, RelayBar waits for a stable, readable image and adds it automatically. A floating thumbnail/editor can delay that save; the shelf does not read a not-yet-saved capture.

The Touch Bar has a **Tools** button, **five image slots**, and **×**. Slot 1 is newest. The sixth capture removes the oldest RelayBar cache entry; it does not remove the original file. A new collected image switches the strip to its screenshot page. **Tools** returns to the AI controls; **Shots** returns to the shelf.

**Tap a thumbnail to copy the full-resolution image.** A brief checkmark confirms copying. Then press **Command–V** in your intended image-capable app. RelayBar does not activate another app, paste, send, or overwrite your clipboard merely because a screenshot arrived. Clipboard data is PNG plus TIFF when encoding is available, never a file path or tiny thumbnail. Tapping an older capture does not reorder the shelf.

## Clipboard-only screenshots

Automatic collection in this release is **file-based**. A screenshot taken with Control added to the shortcut, or Save to Clipboard selected, is not saved into the watched directory. Use **RB → Screenshot Shelf → Add clipboard image** immediately after that capture to add it explicitly. This action can add another deliberately copied image too. No background clipboard history or key monitoring is enabled.

## Persistence and privacy

After folder selection, collection is remembered for later launches. Only that folder's immediate children are considered; there is no recursive disk or photo-library scan. Current native screenshot names, selected localized variants, a configured screenshot-name prefix, and macOS's screenshot metadata are recognized. Supported single-image formats: PNG, JPEG, TIFF, HEIC and HEIF. Third-party capture tools with unrelated names/metadata may need explicit clipboard import. Video recordings and PDF screenshots are not supported here.

Up to five full-resolution PNG cache files and an index are saved under:

`~/Library/Application Support/RelayBar/ScreenshotShelf/`

Existing PNG bytes are retained exactly. Other supported formats are normalized to full-resolution PNG; this is not a promise to preserve every HDR/color feature of a non-PNG original. Thumbnail images are generated separately. Images exceeding 80 MiB input/normalized size or 50 million pixels are rejected rather than silently downscaled. Cloud placeholders not downloaded locally are skipped.

The cache directory is created with owner-only permissions, and its files are owner-readable/writable only. This is **not encryption**. The cache persists when original screenshots are moved or deleted, until it is evicted or cleared. Screenshots can contain private information; choose the folder deliberately. The normal system clipboard's access/synchronization behavior applies after you explicitly copy an image.

**Clear screenshot shelf…** removes RelayBar's managed cached images only, with confirmation. It does not delete originals or clear the system clipboard. Screenshots older than that clear do not silently refill the shelf. **Stop screenshot collection** stops the folder watcher but retains the shelf. Starting again catches up with eligible recent files, including files created while collection was stopped. Pick a new folder explicitly after changing macOS's screenshot save location.

Folder access may be requested by macOS. This feature never calls screen-capture APIs and does not require Screen Recording or Accessibility to collect existing screenshot files. Accessibility remains optional for the separate original text-selection tool. The existing experimental cross-app adapter and its app allowlist are unchanged; this is not an always-on global overlay in every Mac application.

## Test the update on your Mac

Take **six harmless, visibly different screenshots**, waiting for each to appear. Confirm exactly five thumbnails remain, newest on the left. Tap an older thumbnail, press Command–V in the desired chat composer, and confirm the correct full-sized image appears without automatic submission. Repeat in the other assistant. Originals should still be present in the screenshot folder.

Then quit/relaunch RelayBar: the shelf should restore; turn cross-app mode on again. Test **Clear shelf**, wait several seconds, and confirm old files do not return. Take a new screenshot and confirm it appears.

- **Test.command** runs 77 portable Swift tests, including the five-image retention, persistence, stable-file gating and cache safeguards.
- **Screenshot_Test.command** builds this source without installing it, then runs native synthetic checks for ImageIO, thumbnail controls, the actual directory watcher, and a separate named pasteboard. It does **not** inspect your screenshots or General clipboard. It takes roughly several seconds after compilation; timing varies by Mac. Send its `BuildLogs/screenshot-test-…log` after reviewing personal paths if it fails.
- **Doctor.command** retains the existing compiler/bridge diagnostics. It does not replace a physical Touch Bar/paste test.

## Build and validation status

The previous native launch/physical bar/cross-app visibility were user-confirmed. That is not a test of this new screenshot adapter. The current source passed 77 portable Swift tests, all 16 compiler-repair regression checks and Swift/shell syntax checks in Linux. **macOS SDK typechecking/compilation and the new native image/watcher/clipboard/physical-thumbnail tests have not run in this build environment.** `Install.command` and `Screenshot_Test.command` are the on-Mac path to verify them.

Keep the working prior app backup. To revert, quit RelayBar and open the previous app at the backup path printed by the installer. That version ignores the screenshot feature's separate preferences/cache. Nothing is remotely installed on your Mac by opening this package.

See `Docs/SCREENSHOT_SHELF_DESIGN.md`, `Docs/VALIDATION_0.2.md`, and `Docs/SOURCES_0.2.md`. Older version documentation/receipts are historical, not current Mac validation.

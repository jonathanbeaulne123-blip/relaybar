# RelayBar 0.3 — App-aware buttons + Google Sheets

This is the complete source update to RelayBar 0.2.1, not a precompiled app or a browser-only mock. It has not been installed on your Mac or connected to your real spreadsheet here. Start with a harmless test workbook or a copy when validating script actions.

## What changes

RelayBar follows the foreground Mac app. In supported browsers it also follows the active tab and exact workbook, rather than treating every browser tab as an AI conversation.

| Where you work | Contextual Touch Bar |
|---|---|
| ChatGPT or Claude desktop app | Existing AI tools |
| ChatGPT or Claude website, with browser link enabled | Existing AI tools |
| Linked Google Sheet | That workbook’s registered script actions, four per page; arrows reach the rest |
| Google Sheet without its sidebar link | Connect Sheet / setup help, not made-up script names |
| Other browser tab, with browser link enabled | Back, Forward, Reload, Shots and manual AI tools |
| Other native application | Its native Touch Bar is left alone |

A saved screenshot still automatically opens the five-image viewer in the supported assistant/browser apps. The return button takes you back to Sheets or the current app’s tools. Taking a screenshot does not copy, paste or send it. Tap a thumbnail to copy the full image, then use Command–V. A temporary browser-link outage disables script buttons without dismissing the screenshot viewer. A real app/tab switch returns to the new context.

**Included browser adapters:** Google Chrome, Microsoft Edge, Brave and Chromium. These adapters are implemented but not yet live-browser/Mac validated. Safari, Firefox and Arc do not have the Sheets bridge in this release. Unsupported sites retain generic browser controls; private/incognito windows are not linked.

## Install the native update

1. Finish any earlier installer. Save unfinished drafts/checkpoints. Disable the RelayBar browser extension if already installed, then choose **RB → Quit RelayBar**. The extension can otherwise keep a native RelayBar host process running.
2. Unzip into its own **RelayBar_0.3_App_Aware** folder. Do not merge source folders. Run **Install.command**. It uses the existing compiler-compatibility preflight, compiles locally, backs up the prior app, and installs into `~/Applications/RelayBar.app`.
3. In RB, leave **App-aware button layouts** checked. Re-enable **Experimental cross-app Touch Bar → Enable for this session**. Cross-app mode intentionally starts OFF on every launch. Your screenshot save-folder choice, five cached images, project briefs and saved settings are retained.

The working Objective-C cross-app bridge, build/toolchain scripts, screenshot watcher/cache/copy implementation and screenshot auto-open engine are byte-identical to 0.2.1. Only Chromium was added to the explicit browser allowlist. The existing private cross-app overlay remains experimental; no claim of compatibility with every macOS version is made.

## Google Sheets — one-time browser setup

Run **Set_Up_Sheets.command** from this new package. It asks which supported browser you use, copies the extension to a stable private Application Support folder, opens your browser’s extensions page, and walks you through **Developer mode → Load unpacked**. This means the browser’s extension developer mode, not macOS Developer Mode.

Choose the folder it opens: `~/Library/Application Support/RelayBar/BrowserExtension`. Copy the extension’s 32-letter ID into the setup prompt. The setup registers only that ID with the local native host. Then open the extension’s popup and enable the link. Its status distinguishes a missing native host from a linked one. This is a local unpacked extension, not a Chrome Web Store-reviewed release.

The same browser can have more than one profile, but ambiguous simultaneously focused link sessions fail closed. Start with one browser profile during acceptance testing. To use another supported browser, rerun setup and choose that browser; register its own extension ID.

## Google Sheets — connect each workbook

In the desired workbook, open **Extensions → Apps Script**. This must be that workbook’s existing bound project, not a new standalone project or a web-app deployment.

1. Add a NEW script file named **RelayBar** and paste `AppsScript/RelayBar.gs` into it. Add a NEW HTML file named **RelayBarSidebar** and paste `AppsScript/RelayBarSidebar.html` into it. Do not overwrite any existing files, existing functions or `appsscript.json`. Stop and rename/reconcile if those file/function names already exist.
2. Add this single line inside your existing `onOpen` function, keeping its existing contents:
   ```javascript
   RelayBarAddMenu_();
   ```
   If there is no `onOpen`, create `function onOpen() { RelayBarAddMenu_(); }`. Do not create a second `onOpen`. Alternatively, run `RelayBarOpen` once from the script editor without changing any open trigger.
3. Save, return to the Sheet and reload. Choose **RelayBar → Open Touch Bar link**, then **Connect Touch Bar** in its sidebar. Complete Google’s authorization only after reviewing your project’s permissions. This uses your existing signed-in account and bound script; there is no new API key, public endpoint or RelayBar cloud account.
4. Keep the sidebar open. With the browser extension and cross-app Touch Bar enabled, RelayBar displays the actions published by that workbook. Reconnect after closing/replacing the sidebar or reopening the document. Click **Refresh buttons** after changing assignments or registry entries.

### Which buttons are discovered automatically?

Scripts assigned to drawings and over-grid images are discovered across the workbook. Google exposes the assigned function name, not the caption inside a drawing. RelayBar uses a readable function name plus worksheet name; image alt-text titles are used when present. Repeated assignments of the same function on the same worksheet are deduplicated. Buttons from another worksheet are listed, but execution asks you to switch there first rather than silently changing your selection.

Custom menu actions and unassigned macros need their verified function names added once to `RELAYBAR_MENU_ACTIONS` near the top of `RelayBar.gs`. Existing custom menus cannot be enumerated through the documented Menu API. No actual function names from your private project have been guessed or pre-enabled in this package.

Example only—replace the name with an EXISTING no-argument function from your script:

```javascript
var RELAYBAR_MENU_ACTIONS = [
  {label: 'Your existing menu action', functionName: 'yourExistingFunction', confirm: true}
];
```

Use the strings passed to your existing `addItem(label, functionName)` calls. Registering a function does not create it. Dotted library function names are supported where they resolve in the bound runtime. Unsupported functions produce warnings instead of fake buttons. Lifecycle triggers and RelayBar’s own internal functions are not eligible. Functions requiring arguments need a deliberate no-argument wrapper that supplies those arguments; RelayBar does not guess them.

The first release supports up to 120 distinct actions, four per Touch Bar page. All registered eligible actions are reachable with the page arrows. Larger inventories fail with a clear error, not silent truncation. The default registry is empty until you enter your real custom-menu functions; drawings/images can populate it without manual entries.

### One-tap versus confirmation

Automatically discovered actions ask for confirmation in the Sheet’s sidebar because their effects are unknown. The confirmation names the action and warns that it may change data. Cancel does not run it. For a reviewed, non-destructive custom-menu action, setting `confirm: false` makes a Touch Bar tap execute directly. Leave confirmation on for deletions, bulk writes, sending messages, purchases or other consequential operations.

Scripts execute in the bound Sheet using `google.script.run`, not a public web-app request. This preserves the intended container UI context for existing dialogs, but your specific dialog functions remain untested. A script that opens another sidebar replaces the RelayBar sidebar and disconnects the link; reopen RelayBar afterward. Any function’s own external writes or messages still have their existing effects—RelayBar does not sandbox your code.

No script runs just because you switch apps or connect a workbook. A timed-out or failed request is never automatically retried; a script might already have partially succeeded. Check the Sheet before deliberately tapping again. Closing the sidebar cannot cancel a script already dispatched to Google.

## Privacy, pause and removal

The extension is OFF until explicitly enabled. When enabled it sends only local routing metadata: browser/tab/window identifiers, supported-site kind, and a connected workbook’s name/ID, link token, button labels and function-derived action identifiers. No cells, cookies, page text, script source, clipboard contents or script return values are sent through the bridge. It is a native-messaging pipe, not an HTTP server. Running your existing Apps Script still communicates with Google as normal.

Private routing files live under `~/Library/Application Support/RelayBar/BrowserSessions`; directories are owner-only and files are owner-readable/writable. This is not encryption. A fresh native connection gets a new session; normal disconnect removes its files, and valid stale crash sessions are pruned on host startup. Disabling **App-aware button layouts** changes layouts and cancels queued taps; disable the extension to stop metadata collection entirely.

To remove the browser integration, disable/remove the extension in your browser, quit RelayBar, then remove only `local.relaybar.sheets.json` from that browser’s `NativeMessagingHosts` directory under your user’s Application Support. Browser paths are `Google/Chrome`, `Microsoft Edge`, `BraveSoftware/Brave-Browser`, or `Chromium`. The generated wrapper lives in `RelayBar/NativeHosts/launch-<browser>.sh`. Removing these dedicated bridge files does not require deleting your screenshot shelf or projects. The supplied **Uninstall.command** removes the app only after confirmation; data deletion is a separate explicit confirmation. It does not remove browser extensions or host manifests for you.

## What is actually tested

Read **Docs/VALIDATION_0.3.md**. Portable Swift policies/storage, JavaScript validation and script-dispatch logic, and the actual sidebar DOM with explicitly mocked Google/Chrome services were exercised. Native macOS compilation, installer execution, browser native messaging, Google authorization, your live functions and the physical Touch Bar were not available for this build.

Use **Docs/MAC_ACCEPTANCE_0.3.md** for the real-device checks. Start with harmless functions and a copied workbook. The old `RelayBar_Preview.html` remains a historical text-workflow demo, not evidence that this native update is installed or working on hardware.

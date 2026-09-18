# App-aware architecture — RelayBar 0.3

## Routing and execution

`AppMain.swift` uses NSWorkspace activation notifications plus a 0.45-second context refresh. Explicit native assistant identities keep their original tool layout. Browser extension heartbeats (0.7 seconds) publish minimal typed context. Other native apps keep their own Touch Bar. The native host is another invocation of the installed executable in `--browser-native` mode; that branch runs before normal app initialization.

The native app selects exactly one fresh focused receipt for the foreground browser bundle. Receipts older than 2.5 seconds, future-dated receipts and ambiguous sessions are ineligible. A script button binds the exact native session, tab, browser window, workbook and sidebar token at render time. A tap checks a fresh receipt and the current foreground app before queuing a command. Commands expire after three seconds.

The host consumes a command before checking current context and forwarding it, so dropped messages cannot be retried from the mailbox. The extension rechecks the focused window and active tab, then targets only the exact linked iframe. The content script rechecks the token, workbook, deadline and visibility; duplicate request IDs are refused. Multiple concurrently publishing sidebar frames fail closed until only one remains live.

The Sheet sidebar performs the explicit confirmation when required. The server rechecks workbook, current assignment, registry entry, confirmation setting and source worksheet. The user cache stores the link’s accepted request IDs in the same object as its allowed actions; eviction invalidates the whole link. A short per-user lock protects request acceptance, but is released before calling a user function so modal UI does not retain the lock. Sessions last at most six hours and 256 requests. No eval, arbitrary code string or automatic retry is used. Script results are not transported to RelayBar.

A confirmation is a new explicit user action and can be completed after the three-second native-delivery deadline. It is cancelled when the sidebar becomes hidden; the workbook/token and current server assignment are still rechecked. This is a best-effort interactive control, not transactional execution or a guarantee that arbitrary user scripts cannot fail after making a change.

## Screenshot coexistence

The prior screenshot engine is retained byte-for-byte. A new image selects and reopens the screenshot page; four-script paging is not a replacement for the five-image shelf. `ContextLayoutState` remembers the last confirmed browser identity so a temporary lost heartbeat does not behave like a new app. Real app/tab changes reset to the new context. Known macOS screenshot helper identities do not reset the remembered app context. User navigation still cancels screenshot reveal recovery. Physical timing and overlay behavior must be tested on the Mac.

## Trust boundaries and limitations

The user deliberately installs the local extension, registers its exact ID, and adds the sidebar to the bound project. Google authorization remains that project’s authorization. The extension never inspects the account’s Apps Script source or infers the user’s private functions from unrelated sheets. Functions assigned to drawings/images are discoverable; existing custom-menu/macros require an explicit allowlist. Discovery itself makes no cell writes.

The browser extension sees authorized site URLs locally to classify tabs; full URLs and unrelated tab titles are not written to the native mailbox. Script iframe matching is restricted to Google Apps Script frame origins, and only the unique RelayBar DOM marker can publish a manifest. Host manifests allow exactly the extension ID selected at setup. There is no local HTTP listener or external RelayBar service.

This is not protection against another malicious process already running as the same OS user, an authorized malicious extension, or malicious code in the same bound Apps Script project. Existing script functions can use all permissions already granted to that project. Default confirmation is a UX guard, not a security sandbox. Native IPC enforces owner-only directories/files, regular-file/no-follow checks, message bounds and typed validation. Directory permissions are not encryption.

Source mailboxes are bounded to 64 sessions and 64 KiB messages. Crashed valid sessions older than 120 seconds are pruned when a native host starts. Invalid/unrelated files are not silently removed. Browser service worker/native-link suspension can temporarily remove buttons; reconnecting must never replay a command. Desktop assistant destination following does not silently redirect an already-composed draft.

## Source map

- `Sources/Core/AppContext.swift`: wire types, route selection, authorization, paging and screenshot-compatible context transitions.
- `Sources/Core/BrowserMailbox.swift`: local private session IPC.
- `Sources/Mac/BrowserNativeHost.swift`: explicit host registration and native message framing.
- `Sources/Mac/AppMain.swift`: menu preferences, profile layout, guarded tap dispatch.
- `BrowserExtension/protocol.js`: URL/origin/manifest validation shared by service worker and content script.
- `BrowserExtension/background.js`: opt-in native connection, active tab selection, frame binding, guarded navigation/dispatch.
- `BrowserExtension/sidebar.js`: only the RelayBar sidebar’s typed DOM bridge.
- `AppsScript/RelayBar.gs`: registered actions, drawing/image discovery, scoped server dispatch and replay state.
- `AppsScript/RelayBarSidebar.html`: explicit connection, confirmation and progress.
- `Set_Up_Sheets.command`: user-driven unpacked extension and host setup.

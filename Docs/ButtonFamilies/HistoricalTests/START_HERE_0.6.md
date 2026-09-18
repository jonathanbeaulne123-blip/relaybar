# RelayBar 0.6 — Pinned Chats

**Your pinned ChatGPT and Claude conversations, on the Touch Bar.**

This is a complete native source update, not a browser mock or a precompiled Mac app. It merges the actual **0.5 Context Stack** and the newer **0.5 Native Sheets** branches, preserving both features. The installed app will report **0.6.0, build 9**. No browser extension is used or shipped.

## Install

1. Copy out any Context Stack excerpts you need and save unfinished drafts/checkpoints. **Quit RelayBar** from the RB menu. Stacks are memory-only and are lost on Quit. Keep any old RelayBar browser extension disabled; it is not used by this version.
2. Extract this archive into its own **RelayBar_0.6_Pinned_Chats** folder. Double-click **Install.command** inside it. Do not merge source folders. The installer builds locally using Apple's Command Line Tools, retains the existing compiler-compatibility helper, backs up the previous app, and installs to `~/Applications/RelayBar.app`. It leaves your projects, preferences and screenshot cache in place.
3. In the RB menu choose **Enable native app controls…**. Enable RelayBar in **System Settings → Privacy & Security → Accessibility** when asked. This also enables the existing experimental cross-app Touch Bar for the current session. It still starts OFF on each subsequent app launch.
4. Bring **ChatGPT or Claude** to the front, open its sidebar and expand **Pinned / Starred**, then tap **Pins**. The RB → Pinned Chats menu offers the same entry point.

No extension installation, Google authorization, per-spreadsheet setup, API key, chat export or shared-chat link is required. The installer does not modify ChatGPT, Claude, Google files or browser preferences. No remote change has been made to your Mac by preparing this package.

## Use Pins

The page contains **Tools**, a **GPT ⇄ / Claude ⇄** assistant switch, a previous-page arrow, **three chat titles**, a next-page indicator, **Refresh**, and **Hide**.

Tap a title to request navigation to that actual sidebar conversation. It does not copy, paste, type or send a message. The arrows page through the detected list in sidebar order; the page counter wraps. The active conversation receives a checkmark when the app exposes selection. Full titles are retained in button help/accessibility descriptions even when the physical button label is shortened.

The provider button opens the other configured **desktop app**. It does not manufacture a deep link or move you into another browser profile. To use a browser, focus the intended ChatGPT or Claude tab yourself. Pins then follows that active tab's exposed sidebar. Choose the correct desktop app using RelayBar's existing **Choose ChatGPT / Claude application** menu items when its bundle identity differs from the built-in adapters.

The list refreshes while Pins is active, approximately every two seconds when the run loop and app respond. Before a tap is dispatched, RelayBar rescans and checks the app, focused window, document identity, sidebar, current pin inventory and exact accessible element. A changed, expired, duplicate or ambiguous target is rejected. One Accessibility press is requested; uncertain results are never automatically retried. A successful request is not proof the conversation finished loading.

**Tools**, **Stack**, screenshot viewing and **Hide** leave Pins. New screenshots retain their existing automatic-viewer priority; tap Pins to return. Opening Pins or Stack cancels pending native Sheets menu interactions. Context Stack contents are not cleared merely by opening Pins.

## Detection limits — important

This adapter can use **only what the active app exposes through macOS Accessibility**. It is not an account API, hidden-history scraper or bookmark database. Your pinned conversations were not accessed while developing this package.

Open the sidebar and expand its Pinned / Starred section for the first test. If headings, pin markers, private conversation links or identifiable chat rows are missing, the page reports a detection/status message. It does not replace pins with recent chats or claim your account has no pins. Use **↻** after opening the sidebar. Hidden, virtualized or unexpanded items may not be exposed. Ambiguous targets and partial results after a scan limit are disabled.

Pinned projects and public share links are not chat shortcuts. In a mixed Pinned/Starred section, native rows need a private conversation URL or chat/conversation-specific identity. Title-only native rows are allowed only inside a section explicitly labelled for chats, not a mixed Pins group. Duplicate identities are disabled.

The initial semantic labels cover English Pinned/Starred/Favorites variants. Other languages or changed layouts may require adapter work. At most **60 exposed chats**, three per page, fit the bounded inventory. This is RelayBar's limit, not a claim about either service's pin allowance. Long labels over 240 characters, unreadable controls and unsupported page paths are skipped rather than guessed.

Native desktop ChatGPT/Claude are the primary targets. Pins also contains adapters for Safari, Chrome, Edge, Brave, Chromium, Firefox and Arc, **conditional on an official assistant page URL and one accessible sidebar**. None of these live app/browser paths has been verified here. The preserved Native Sheets adapter has its separate, narrower browser support; adding Pins does not expand Sheets compatibility.

## Privacy and coexistence

Pins reads foreground UI metadata: roles, pin/star labels, chat titles, private conversation URLs, selected/enabled states and element/focus identity. It prunes editable/secure fields, dialogs and main-content landmarks. Static text is read only after identifying a sidebar. It does not request conversation bodies, selected message text, cookies, account credentials, the clipboard or screenshots. Pin lists and element references are kept in memory only and are cleared when leaving the page or quitting; there is no pin-list file, telemetry or external service.

Where supported, entering Pins requests the app's accessibility tree with its runtime AXManualAccessibility attribute. That may increase app resource use until it exits. RelayBar does not edit browser preferences or disable accessibility beneath another assistive tool. Accessibility is a broad OS permission; the app's other explicitly selected tools retain their own permissions and behavior.

Private/incognito windows cannot be reliably distinguished through this route. **Leave Pins or hide RelayBar before private work.** Titles can be visible on the Touch Bar. Revalidation is a best-effort safeguard, not an atomic lock on another app's UI or a guarantee against an account switch that exposes indistinguishable controls.

Context Stack remains a separate, explicitly started copied-text collector; stop Collect before copying secrets. Its contents disappear on Quit. The screenshot shelf retains its five-image local cache. Native Sheets remains extension-free and asks for confirmation before leaf actions by default. Those features have not been replaced with a new app.

## Checks and rollback

See **Docs/PinnedChats/VALIDATION.md** for the actual test receipt and the remaining Mac acceptance checklist. `Pinned_Chats_Test.command` builds and constructs real native Touch Bar components on a Mac without reading other apps or using the General clipboard. It is not a live sidebar test. The existing Context Stack and screenshot native self-tests remain included.

For rollback, quit RelayBar and restore the previous **RelayBar Previous … .app** backup printed by the installer as `~/Applications/RelayBar.app`. Do not delete Application Support. The source package has not been Mac-SDK compiled, signed, installed or physical-Touch-Bar tested in this environment.

# Real-Mac acceptance — NOT executed here

Use a harmless workbook or a copy. No spreadsheet code is installed by RelayBar.

1. Quit the older RelayBar; run Install.command. Verify the printed installed app path, backup path and `RB → About` version 0.5.0. Preserve the BuildLogs file on failure. Mac compilation, ad-hoc signing and installer execution are pending checks, not completed results.
2. Choose Enable native app controls and approve Accessibility for RelayBar if asked. Return to an existing Sheet. Verify no extension, per-Sheet code, sidebar, Google API key or new cloud deployment is involved.
3. Confirm the native connection report identifies the browser/page kind and actual menus. Check Chrome, Edge, Brave, Chromium and Safari separately before claiming them supported. Missing URL or menu exposure must show an unavailable state, not fake controls.
4. Open a known custom menu. Verify its current actual items, four-button paging and nested menus. Confirm opening a menu does not run a leaf script. Exercise a harmless existing action with inline confirmation, then cancel another. Watch the browser and verify the action actually executes; RelayBar itself only reports an AX request.
5. Switch windows, tabs, workbooks and worksheets while a confirmation is pending; old buttons must not activate a different target. Close a menu, open a dialog or cover a target before confirming. Observe refusal where identity, accessibility state or hit testing cannot validate the target. Check rapid double taps.
6. Take a saved screenshot while a confirmation is pending. The existing five-image viewer should open; pending confirmation should clear. Tap a thumbnail and manually paste. Verify originals remain and the copied image is full size. Return to Sheets controls. Repeat screenshots while a browser accessibility read is slow.
7. Pause native detection, hide the overlay and revoke Accessibility separately; menu inspection and queued requests must stop. Check no automatic retry after an uncertain native action. Existing actions already delivered to Google cannot be undone by pausing.
8. Quit/relaunch: screenshot folder/cache/settings persist, and the experimental cross-app mode starts OFF. Resume with the single Enable native app controls command; change spreadsheets without any connection setup.
9. Use a slow/large Sheet, multiple browser windows, private windows, fullscreen and a second display. Check performance and hit-test coordinates. Private/incognito mode cannot reliably be identified through this adapter: an active private Sheet can be mirrored when you have enabled native inspection; there is no background tab/history enumeration. Pause detection when private work should not be inspected.
10. Check that the local connection report omits URLs, document titles, cell text, scripts and screenshots. The original selected-text Capture and screenshot clipboard operations remain separate explicit actions.

Google Sheets keyboard/screen-reader support is not proof that every browser exposes custom menus through AX or accepts AXPress. Do not record success until observed on the actual target device/browser/version.

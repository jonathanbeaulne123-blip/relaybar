# RelayBar 0.8.2 — Verified Click validation

Prepared September 17, 2026. Current metadata: **0.8.2 build 15**, bundle ID `local.relaybar`. This is a source/package validation receipt, not a claim that the final build has been compiled or exercised on the user's Mac.

## User-reported state that triggered this repair

The prior unified build was successfully detecting the active Google Sheet and exposing the intended controls on the Touch Bar, but tapping those controls did not activate the corresponding Google Sheets UI. Discovery and permission were therefore no longer the blocker; dispatch was.

## Runtime change

For Chrome, Edge, Brave and Chromium only, the Native Sheets engine now keeps the existing fresh route/window/URL/focus/frame/action/hit-test checks and then posts **one** primary-button mouse down/up pair at the verified control center. It does not first send AXPress and does not retry after posting the click. Safari continues to use the native Accessibility action path. Leaf tools still use RelayBar's existing Touch Bar confirmation by default.

The purpose is to make a Touch Bar tap behave like an actual click on the already-verified visible Sheets menu/action, rather than relying on Chromium's abstract accessibility action callback.

## Results actually executed

| Check | Result | Boundary |
|---|---:|---|
| Portable Swift XCTest | **422 passed, 0 failures** | Core policies/state engines on Linux |
| Exact Native Sheets controller + service doubles | **24 passed** | Includes lazy Hearth-style menu expansion and confirmed child-action dispatch through verified-click policy |
| Actual NativeAXSource/NativeMenuEngine bodies + C/API doubles | **30 passed** | Includes one click pair, no discovery click, stale/covered/permission failures, scan budgets |
| Native Sheets source contracts | **18 passed** | Verified click is present; no keyboard, JS, extension, web server or permission bypass |
| Scan/package contracts | **12 passed** | Adaptive bounds, installer lineage, packaging contracts |
| Unified integration checks | **13 passed** | All unified feature engines remain wired |
| Screenshot auto-open regression | **14 passed** | Screenshot viewer behavior retained |
| Context Stack integration | **22 passed** | Context Stack retained |
| Pinned Chats wiring + controller | **41 + 23 passed** | Pins retained |
| Button Families wiring + map + adapter | **21 + 43 + 145 passed** | Five-family UI retained |
| Permission recovery helper | **24 passed** | Retargeted to 0.8.2 build 15 using command doubles |
| Compiler-repair regressions | **16 passed** | Existing compiler workaround retained |
| Swift syntax parse | **passed** | Core/Mac Swift 5 syntax only, not macOS SDK linkage |
| Shell syntax | **passed** | Installer/diagnostic/recovery scripts |

Receipts are in `Docs/VerifiedClick_0.8.2/`.

## Safety properties retained

- No click occurs during discovery or app switching.
- Before dispatch, the foreground PID, focused window, Sheet URL, focused element, exact control binding, enabled/action state, frame and on-screen hit target must still match.
- A covered, moved, stale, changed or ambiguous target is refused.
- One user request produces at most one pointer-click pair on Chromium-family Sheets; there is no automatic AX fallback or retry.
- Leaf actions still require confirmation by default.
- Screenshot interruptions, navigation changes and retired Touch Bar buttons invalidate pending native interactions.
- No browser extension, Apps Script injection, keyboard injection, JavaScript execution, OCR, screen recording, network request or per-workbook setup is added.

## Not verified here

**macOS SDK compilation/link/signing of 0.8.2; actual CGEvent delivery on the user's Mac; Chrome's live Google Sheets behavior; Hearth Tools and the user's real Apps Script functions; cursor behavior on multi-display setups; physical Touch Bar rendering/clicks; Accessibility approval continuity after the rebuild.**

The on-device acceptance test is therefore simple: after installing, the connection report should show `Dispatch transport: verified pointer click`; tapping `Hearth Tools` should visibly open that menu in Sheets, and tapping a confirmed leaf should invoke the same action as clicking it with the mouse.

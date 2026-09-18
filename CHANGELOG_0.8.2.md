# RelayBar 0.8.2 (build 15) — Verified Click

## Fix
- Chrome/Edge/Brave/Chromium Google Sheets controls now use one literal left-click at the exact accessibility-verified control center instead of relying on Chromium's abstract asynchronous `AXPress`/`AXShowMenu` dispatch.
- The pre-click safety gate is unchanged: current foreground PID, focused window, exact Sheet URL, focused element, fresh menu snapshot, enabled state, action exposure, frame and final AX hit-test must all still match.
- There is no retry and no AX-action fallback after the pointer click is posted. A failed or uncertain delivery must be checked in Sheets before tapping again.
- Top-level/nested menu navigation remains immediate. Leaf tools still use RelayBar's Touch Bar confirmation by default.
- Safari retains the native Accessibility action path.
- Connection report identifies `Dispatch transport: verified pointer click` for supported Chromium-family browsers.

## Retained
Adaptive menu bounds (1,600 menu nodes / 5,000 AX queries), Menu Cascade, Screenshot Shelf + auto-open, Button Families, Context Stack, Pinned Chats, prompt/project tools, stale-target invalidation and permission recovery remain present.

## Validation boundary
Portable/service-double tests passed. The final source has not been Mac-SDK compiled or live-tested against the user's Chrome/Google Sheets/physical Touch Bar in this environment.

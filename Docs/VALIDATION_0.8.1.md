# RelayBar 0.8.1 — Adaptive menu-bounds validation

Prepared September 17, 2026. Current metadata: **0.8.1 build 14**, bundle ID `local.relaybar`.

This is a targeted source repair on the exact user-supplied/previously delivered unified 0.8.0 archive (SHA-256 `5c86ef9d970226a4fdcb1b605c3c9b9b941b6534361168b38d9542c8b3a12309`). The live failure report was supplied by the user from Chrome/Google Sheets; it is not claimed as remotely measured by this environment.

## Live failure this repair targets

The 0.8.0 report reached the correct foreground Chrome Sheet with Accessibility granted, found one menu container and 11 candidates, and stopped during **Sheet menu discovery** at the 900-node phase bound. It had used **2,236 / 3,500 queries** and **127 / 850 ms**, so the concrete failure was the node cap rather than permission, browser identity, time budget or query budget.

## Repair

- Browser/document identity traversal remains capped at **900 nodes**.
- Only Sheet menu discovery is increased to **1,600 nodes**.
- Total scan query cap is increased to **5,000**, while the **850 ms** deadline, depth **24**, child-list bound **4,096**, child page size **64**, complete-or-disabled publication and pre-tap revalidation remain.
- No partial menu is published if any active bound or AX read fails.
- No automatic script execution or retry was added.

## Failure reproduction

A new fixture places a lazy Hearth-style menu behind **1,200 generic Sheet UI nodes**. Against the exact 0.8.0 `NativeMenus.swift`, the test fails with `.nodes`, no ready snapshot and no actions. Against 0.8.1 it passes and returns both simulated Hearth tool items. A separate >1,600-node fixture still fails closed, proving the hard menu bound remains.

Receipts: `Docs/LiveScanRepair_0.8.1/OLD_BOUND_REPRO.txt` and `NEW_BOUND_REPRO.txt`.

## Executed results

| Area | Result | Boundary |
|---|---:|---|
| Portable Swift XCTest | **421 passed, 0 failed** | Unified core plus new live-sized menu-bound regression; Linux Swift 6.2.1 |
| Native Sheets controller harness | **24 passed** | Exact controller against explicit AX/workspace doubles, including lazy Hearth menu cascade |
| Native Sheets source contracts | **18 passed** | No extension/JS/coordinate-click path, privacy/report and revision guards |
| AX adapter/engine harness | **30 passed** | Batched headers, paged children, 5,000-query cap, 850 ms deadline, hard node/child limits and single dispatch |
| Scan/installer contracts | **12 passed** | Version gate, diagnostics, no permission bypass, complete paging |
| Unified product contracts | **12 passed** | All integrated engines present, no extension/Apps Script runtime, permission helper packaged |
| Button Families adapter | **145 passed** | Production family adapter against explicit UI/feature doubles |
| Button Families guide/browser | **43 passed** | Offline Chromium guide, zero observed runtime requests/JS exceptions |
| Button Families wiring | **21 passed** | Families/navigation/native Sheets transition/screenshot priority |
| Context Stack wiring | **22 passed** | Explicit in-memory collection and coexistence |
| Pinned Chats controller | **23 passed** | Paging/provider/stale-target/cancellation/no retry |
| Pinned Chats wiring | **41 passed** | Bounded metadata reads and no extension path |
| Screenshot auto-open | **14 passed** | Viewer/recovery/focus/copy behavior preserved |
| Build/toolchain repair | **16 passed** | Existing duplicate-module repair/refusal cases |
| Permission recovery helper | **24 passed** | Retargeted 0.8.1 helper against explicit command doubles; not a real TCC run |
| Browser preview | **21 passed** | Historical prompt preview via `/usr/bin/chromium`; not native Touch Bar |
| Swift syntax parse | **passed** | All current Core/Mac Swift sources parse in Swift 5 mode |
| Shell syntax | **passed** | Installer, helpers and shell scripts pass `bash -n` |

## Source continuity

A byte comparison against the exact 0.8.0 archive shows only three production Swift files changed:

- `Sources/Core/NativeMenus.swift` — query/menu-node bounds only.
- `Sources/Mac/NativeMenuController.swift` — version/report text and menu-budget diagnostic.
- `Sources/Mac/AppMain.swift` — version metadata only.

`Sources/Mac/NativeAXSource.swift`, Button Families, Context Stack, Pinned Chats, Screenshot Shelf/presentation and other production feature source files are byte-identical to 0.8.0.

## Still unverified here

- macOS SDK compile/link/sign of the final 0.8.1 source.
- Running `Install.command` on the user’s Mac or Accessibility approval continuity across this ad-hoc rebuild.
- Live Chrome accessibility traversal completing within the new bounds on the user’s exact workbook.
- The real Hearth Tools menu and all exposed child actions appearing on the physical Touch Bar.
- Actual Apps Script completion after an action request.

After installation, the useful acceptance report should begin `RelayBar 0.8.1 · Native Sheets engine 0.5.3 · Menu Cascade + Lean Scan + Adaptive Bounds` and should show a nonzero **Menu node budget: 1600** line. If it stops again, the exact new stop reason/query/node counts should be used rather than widening another bound blindly.

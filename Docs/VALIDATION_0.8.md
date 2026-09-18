# RelayBar 0.8 — Unified validation receipt

Prepared September 17, 2026. Current metadata: **0.8.0 build 13**, bundle ID `local.relaybar`.

This is a consolidated source release. The tests below were executed in the provided Linux environment against the delivered source. They do **not** substitute for Mac SDK compilation, Accessibility authorization, live Google Sheets/Hearth Tools behavior or a physical Touch Bar test.

## Executed results

| Area | Result | What it covers |
|---|---:|---|
| Portable Swift XCTest | **420 passed, 0 failed** | Prompting, storage, screenshots, app-context policies, Context Stack, Pinned Chats, Button Families, Lean Scan and Menu Cascade core logic |
| Unified product contracts | **12 passed** | All feature engines present; no runtime extension/Apps Script dependency; app-aware Sheets transition; cascade markers; recovery helper and installer lineage |
| Button Families wiring | **21 passed** | Five-family catalog, navigation, retired-control guards, dynamic engines, direct Sheet-context transition and screenshot priority guard |
| Button Families adapter harness | **145 passed** | Exact production family adapter compiled against explicit UI/feature doubles; page widths, leaves, dynamic pins/stack/screenshots/native controls |
| Button Families guide/browser | **43 passed** | Generated catalog UI, all pages reachable, desktop/phone layout, zero observed runtime requests/JS errors |
| Context Stack wiring | **22 passed** | Explicit collection, session-only clips, project separation, screenshot coexistence and no automatic send/paste |
| Pinned Chats wiring | **41 passed** | Native/sidebar guards, bounded reads, exact target checks, no message-body/network/extension path |
| Pinned Chats controller harness | **23 passed** | Paging, provider switch, stale generations, dispatch cancellation and no retry |
| Native Sheets source contracts | **18 passed** | Accessibility-only architecture, privacy report, no extension/setup, revision-bound controls |
| Native Sheets controller harness | **24 passed** | Includes missing-`AXEnabled` menu trigger, lazy generic popup expansion and confirmed Hearth child dispatch |
| Lean Scan native-adapter harness | **30 passed** | Batched metadata, paged children, 800-node/300-child regression fixtures, budgets, no discovery actions |
| Scan/installer contracts | **12 passed** | Version gate, no permission bypass, complete child paging and diagnostics |
| Screenshot auto-open contracts | **14 passed** | Auto-open/recovery bounds, fresh bar responders, no focus/paste/send side effects |
| Build/toolchain repair tests | **16 passed** | Existing compiler duplicate-module repair path and refusal cases |
| Permission recovery helper | **24 passed** | Exact bundle/build targeting, one app-specific reset, no retries/bypass, hash/signature/change checks using command doubles |
| Browser preview | **21 passed** | Historical prompt-workflow preview only; Chromium `/usr/bin/chromium`; no JS exceptions |
| Swift syntax parse | **passed** | All current Core/Mac Swift sources parse in Swift 5 mode; not macOS SDK typechecking |
| Shell syntax | **passed** | Installer, recovery helpers, tests/build scripts; `bash -n`, not Mac execution |

The current Swift suite increased from the 0.7 baseline’s 417 tests to **420** because the Menu Cascade regression cases were added.

## Critical integrated paths verified in source/tests

- **Screenshots:** watcher/cache/copy and auto-open remain present. A screenshot-viewer page is excluded from automatic Sheet-page takeover.
- **Native Sheets:** 0.5.1 Lean Scan budgets/AX adapter are retained; 0.5.2 Menu Cascade adds the short post-menu expansion scan and tolerant menu-navigation enabled check.
- **Hearth Tools:** a custom menu may be opened without explicit `AXEnabled` only when a supported native action exists and it is not explicitly disabled. Expanded leaf actions still require explicit enabled state and use the existing confirmation gate.
- **Context Stack:** supplied standalone branch core/Mac engine matches the integrated 0.7 source byte-for-byte before unified modifications.
- **Pinned Chats:** supplied 0.6 feature files match the integrated 0.7 source byte-for-byte before unified modifications.
- **Button Families:** 0.7 hierarchy/presentation foundation is retained. In 0.8, an actual Sheet/profile or Sheet-route transition automatically enters `.appControls`; manual Back/Home is not overridden by routine refreshes.
- **No extension:** current runtime root has no BrowserExtension or AppsScript directory. Historical documentation may still describe old experiments, but those are not on the runtime path.
- **Accessibility recovery:** `Fix_Access.command` is bundled because local ad-hoc rebuilds can lose TCC continuity. It cannot grant permission and does not weaken the in-process `AXIsProcessTrusted()` check.

## Still unverified here

- Apple macOS SDK compile/link/sign of the final 0.8 source.
- Running `Install.command` on the user’s Mac and whether Accessibility approval carries across that rebuild.
- Live Chrome/Safari/Edge/Brave/Chromium accessibility-tree behavior for the user’s actual workbook.
- The real **Hearth Tools** menu opening and all of its dynamically exposed actions appearing on the physical Touch Bar.
- Actual Apps Script action completion; RelayBar can only report that it requested the exposed UI action.
- Physical Touch Bar rendering, latency and coexistence with other Touch Bar utilities.

Use the in-app **Native connection report** for live troubleshooting. It now identifies `RelayBar 0.8.0 · Native Sheets engine 0.5.2 · Menu Cascade + Lean Scan` and includes the last menu-expansion outcome without document URL, title, cells or script source.

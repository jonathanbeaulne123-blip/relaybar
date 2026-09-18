# RelayBar 0.9 — Persistent Shell validation receipt

Prepared September 17, 2026. Version **0.9.0, build 16**, bundle ID `local.relaybar`.

**Foundation:** exact supplied `RelayBar_v0.8.2_Verified_Click.zip`, SHA-256 `91b5d097ae01bd596fef6d860d230689d8d6e02b9f655502efe7517e833577ee`. The user had confirmed the 0.8.2 Google Sheets verified-click flow works on their Mac before requesting this persistent-shell merge.

## Results actually executed

| Check | Result | Boundary |
|---|---:|---|
| Swift XCTest | **427 passed, 0 failures** | Portable Core policy/engine tests on Linux; includes 5 new PersistentShell state tests. |
| Production Button Families adapter | **176 checks passed** | Exact adapter compiled against explicit AppKit/feature doubles. Covers fixed shell placement on every page, Mac-mode handoff/return and explicit Chrome-pin activation path. Not AppKit SDK/hardware. |
| Button hierarchy guide | **43 passed** | Offline Chromium rendering of the guide HTML; zero observed network requests/JS exceptions. |
| Button Families wiring | **21 passed** | Static/source integration contracts. |
| Native Sheets controller | **24 passed** | Exact controller with explicit workspace/AX doubles; includes lazy Hearth menu cascade + verified dispatch policy. |
| Native Sheets contracts | **18 passed** | Source contracts including one verified pointer-click path for Chromium-family Sheets. |
| Lean Scan/native adapter | **30 passed** | Exact engine/adapter bodies with explicit AX service doubles; bounded scan and click checks. |
| Context Stack integration | **22 passed** | Source/integration contracts. |
| Pinned Chats controller | **23 passed** | Controller with explicit doubles. |
| Pinned Chats wiring | **41 passed** | Source/integration contracts. |
| Screenshot auto-open contracts | **14 passed** | Includes persistent presentation and no auto-paste/send behavior. |
| Build/compiler-repair regression | **16 passed** | Existing synthetic Swift/Clang duplicate-module repair cases. |
| Persistent shell contracts | **10 passed** | Source-level startup, menu, login, app-pin, mac-mode and persistence checks. |
| Unified product contracts | **13 passed** | Confirms one product keeps all major feature engines and no extension/App Script runtime. |
| Permission recovery helper | **24 passed** | Explicit macOS-command doubles; targets only 0.9.0 build 16 and never grants permission itself. |
| Browser preview | **21 passed** | Offline Chromium; zero observed runtime requests or JS exceptions. |
| Swift source parse | **Passed** | Swift 5 parser across production Core/Mac sources; not macOS SDK typing/linking. |
| Shell syntax | **Passed** | `bash -n` for installer/diagnostic/helper command scripts; not execution on macOS. |

Receipts for this run are under `Docs/PersistentShell_0.9/`. `Docs/ButtonFamilies/ADAPTER_RESULTS.json` is also regenerated from the current production adapter.

## Persistent-shell behaviors covered by tests

- Default state is RelayBar-visible and persistent.
- **** enters macOS mode and suppresses RelayBar presentation.
- Ordinary app focus changes do not call the return-to-RelayBar path while macOS mode is active.
- Explicit return restores RelayBar.
- Chrome, Claude and ChatGPT shell pins are fixed after a flexible spacer; macOS button is last.
- Unavailable apps can be represented as disabled controls.
- App pins use explicit user action to activate/launch; ordinary context scanning does not launch apps.
- Screenshot interruption retains the fixed shell region.
- Login-item enable/disable is explicit and uses the user LaunchAgents directory.
- Installer respects a previous login-item opt-out.
- Existing native Sheet scanner/verified click, Context Stack, Pins, screenshots and family engines remain present.

## Existing feature foundation preserved

The Google Sheets Verified Click implementation in `NativeAXSource.swift` / `NativeMenuController.swift` is not replaced with an extension or Apps Script route. It still revalidates the foreground target and uses at most one physical pointer click on Chromium-family Sheets controls; no AXPress-then-click fallback/retry is added.

The package contains no BrowserExtension or AppsScript runtime folders.

## Still untested / not inferred

- Apple macOS SDK typechecking/linking of all new AppKit/NSWorkspace calls.
- Running `Install.command` on the user's Mac and ad-hoc signing of the final 0.9 build.
- Actual LaunchAgent registration/startup across logout/login.
- Real installed-app discovery for the user's exact Claude/ChatGPT installations.
- Physical Touch Bar icon sizing, flexible-space placement and persistent overlay handoff.
- Actual `NSWorkspace` app activation/launch completion behavior on the user's Mac.
- Real stock Touch Bar restoration after the private cross-app bridge dismisses.
- Live macOS Accessibility approval continuity after rebuilding 0.9.

The user-confirmed 0.8.2 Sheets behavior is useful baseline evidence but is not represented here as a fresh 0.9 hardware test.

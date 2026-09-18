# RelayBar 0.7 — validation receipt

Prepared September 17, 2026. **0.7.0 build 11**, `local.relaybar`. Complete source update; no remote Mac or persistent Library changes.

## Actual source used

The exact 0.6 Pinned Chats archive supplied the combined Pins, Context Stack, Screenshot Shelf, local prompting and extension-free Native Sheets baseline. During this task, the newer **RelayBar_v0.5.1_Lean_Scan.zip** became available and was retrieved. Its three changed scanner/AX/controller files were compared with the exact 0.5 Native Sheets ancestor, confirmed unchanged in the 0.6 base, and incorporated. The older branch's AppMain changes were only version strings; its AppMain was NOT substituted for the combined implementation.

`PROVENANCE.json` has input hashes, changed/new source inventory, and preserved-file hashes. **19 production files** are byte-identical to 0.6. The new native scan engine and AX adapter are byte-identical to the 0.5.1 repair; its controller differs only in the release / scan-engine label. The original Objective-C bridge, component renderer, build script and compiler-repair helper remain unchanged.

## Checks executed here

Environment: Linux x86_64, Swift 6.2.1; portable core checked in Swift 5 language mode where applicable. Service doubles are explicitly labeled in the harnesses.

| Check | Actual result | Boundary / receipt |
| --- | ---: | --- |
| Portable Swift XCTest | **417 passed, 0 failures** | Original 344 + 54 hierarchy + 19 Lean Scan tests. `CORE_TEST_RESULTS.txt` |
| Actual family presentation/menu adapter | **145 checks passed** | Production extension compiled with explicit AppKit/feature doubles. `ADAPTER_RESULTS.json`, `FAMILY_ADAPTER_RUN.txt` |
| Actual Pins controller | **23 checks passed** | Cocoa/workspace/AX doubles, not live providers. `PIN_CONTROLLER_RESULTS.txt` |
| Actual native Sheets controller | **20 checks passed** | Workspace/permission/AX doubles. `NATIVE_CONTROLLER_RESULTS.txt` |
| Actual Lean Scan adapter/engine | **30 checks passed** | Exact method bodies with explicit Foundation/AX C API doubles, plus baseline failure reproductions. `SCAN_ADAPTER_RESULTS.txt` |
| New hierarchy wiring | **20 passed** | Static source contracts. `FAMILY_WIRING_RESULTS.txt` |
| Pins wiring/safety | **41 passed** | Static source contracts, only hierarchy/version expectations adapted. `PinnedChats_REGRESSION_RESULTS.txt` |
| Stack wiring/privacy | **22 passed** | Existing data/privacy checks retained. `ContextStack_REGRESSION_RESULTS.txt` |
| Screenshot auto-open wiring | **14 passed** | Retained byte-level engine/bridge/build pins. `AutoOpen_REGRESSION_RESULTS.txt` |
| Native Sheets integration | **18 passed** | Repair's safety contracts plus combined hierarchy/version expectations. `NativeSheets_REGRESSION_RESULTS.txt` |
| Lean Scan / installer contracts | **12 passed** | Includes executing the known-version/no-downgrade gate in isolation, not the Mac installer. `SCAN_PACKAGE_RESULTS.txt` |
| Compiler-repair regressions | **16 passed** | Original synthetic compiler/repair cases. `BuildRepair_REGRESSION_RESULTS.txt` |
| Safe-copy merge | **19 passed** | Actual Python merger on temporary source fixtures. `MERGE_TEST_RESULTS.txt` |
| Interactive guide | **43 checks passed** | Offline Chromium at 1280×920 and 390×844; zero observed requests or JS exceptions. `MAP_TEST_RESULTS.json` |

Syntax, executable modes, metadata, input-preservation and package-inventory checks are recorded separately in `SYNTAX_RESULTS.json` and the package verification receipt. Syntax parsing is not an Apple SDK typecheck. Counts above intentionally separate XCTest, assertions, source contracts, and browser-guide checks rather than labeling their sum “native tests.”

## What the navigation checks cover

All five root families; all 26 pages and canonical parent paths; every original prompt; fixed suggestion positions; Back versus Home versus Hide; group clicks without child execution; actual revision-bound clip/Pack/Pins/Sheets slot reuse; all five screenshot slots; four-project paging reaching all 100 supported projects; breadcrumb state; retired navigation tickets; burst screenshots; options opened inside a screenshot interruption; returning to the interrupted page; auto-open off; unsupported Pins; and native Back's cancel → roots → parent behavior.

The adapter fixture also checks declared slot widths plus spacing against a 650-point budget, including populated dynamic pages. This is not a physical measurement or proof that macOS reserves exactly that area on the user's hardware.

The safe-copy merger checks clean and dry-run paths, preserved unrelated engine edits/extra files, nonoverlapping AppMain changes, overlapping edits, added-file collisions, removed files, symlinks, incomplete branches, existing destinations, newer releases, extra plist metadata, already-repaired scan files, output inventories, corrupt release payloads and already-updated source. The input tree remains unchanged in successful and rejected cases. It cannot infer arbitrary unshared local changes from the installed binary.

The scan fixture re-executes the repair's baseline-versus-new tests, including the 300-child wrapper and generic-group budget reproduction. It is not a reconstruction of the user's private workbook or measurement of native IPC performance. No guessed action names or chat titles were added.

## Native Mac command — included, NOT run

`Button_Families_Test.command` builds this package with the existing Mac toolchain helper and invokes `--button-families-self-test`. It constructs the real native family items and menus, with a separate named clipboard, without showing an overlay, starting Pins scans or Stack collection, reading the general clipboard, or saving panel frame state. The code is supplied but was not executed in this environment. Older screenshot, Stack and Pins native self-tests are retained and likewise not run here.

## Still unverified

**Apple SDK typechecking and C/Objective-C bridging; Mac compilation/linking/signing; actual installation and approval continuity; physical Touch Bar layout/touch targets; real UI focus and app switching; live ChatGPT/Claude pin discovery/navigation; live Chrome/Sheets scan latency/menu behavior/script actions; Safari/other browser adapters; hardware or screen-reader accessibility; and compatibility with extra source edits never supplied here.**

The displayed PNGs are screenshots of the interactive GUIDE, prominently labeled as such. They are not screenshots of an installed native app, the user's Touch Bar or the user's conversations. The guide was loaded with offline `set_content`; direct-file opening on the user's Mac is not a result of that test.

Original tests were preserved under `HistoricalTests/` before adapting old flat-layout and release assertions. Feature-engine safety expectations were retained. Other versioned receipts in the package are historical and do not supersede this receipt.

## Mac acceptance checklist

1. Run `Test.command`, then `Button_Families_Test.command`. Capture any compile/runtime error before installing. Confirm `--diagnostics` identifies 0.7.0 and the UI report names scan engine 0.5.1.
2. On the actual bar, Home shows exactly Prompting, Context, Chats, Workspace, Settings and ×. Open Prompting: Next slice, Challenge, Handoff stay together. More → Build / review → Back returns to More; Home always reaches the five families.
3. Use harmless reference text. Compose a prompt: Draft opens, full text remains editable, and no clipboard write or send happens merely from opening a group or composing. Exercise explicit Copy separately in an unsent draft.
4. Start Stack with synthetic text only; capture clips, visit Clips, take a saved screenshot, then Back to Clips. Repeat with two screenshots in a burst and Screenshot options. Verify no clipboard content changes merely from a saved screenshot or Back/Home.
5. Open Chats → Pins with the assistant's sidebar visible. Verify real titles, current marker, paging, refresh and provider switch. Check that leaving Pins for Home/Context stops its scanning. Hidden/ambiguous controls must remain unavailable, not guessed.
6. Open Workspace → Sheets in a harmless test workbook. Check the new scan report, native menu inventory, explicit confirmation and Back/Cancel. No script should run from opening a family, discovery, Home or Back. Verify actual script results in Sheets after any deliberate action; RelayBar cannot certify completion.
7. Test project paging and switching; each project's Stack remains separate, while the prior reference/draft clears as before. Review/clear dialogs and checkpoints must retain their original scope.
8. Disable auto-open, switch apps, use ×, sleep and relaunch. Confirm screenshot preference behavior, collection pause, permitted overlay apps, cross-app OFF at relaunch, remembered screenshot cache/settings and memory-only Stack loss on Quit.

## Reproduce portable checks

```sh
swift test
python3 Tests/ButtonFamilies/adapter_harness.py
python3 Tests/ButtonFamilies/test_wiring.py
python3 Tests/ButtonFamilies/test_merge.py
python3 Tests/PinnedChats/controller_harness.py
python3 Tests/PinnedChats/test_wiring.py
python3 Tests/ContextStack/test_integration.py
python3 Tests/AutoOpen/test_integration_contract.py
python3 Tests/NativeSheets/controller_harness.py
python3 Tests/NativeSheets/test_contracts.py
python3 Tests/ScanRepair/native_adapter_harness.py
python3 Tests/ScanRepair/test_package_contracts.py
python3 Tests/BuildRepair/test_toolchain.py
python3 Scripts/build_family_map.py
python3 Tests/ButtonFamilies/test_map.py
```

The guide check requires Python Playwright and an available Chromium executable; it is a development check, not a runtime dependency for RelayBar. Run the merger tests from the original release package, not an edited merged copy. Exact receipt paths are relative to `Docs/ButtonFamilies/`.

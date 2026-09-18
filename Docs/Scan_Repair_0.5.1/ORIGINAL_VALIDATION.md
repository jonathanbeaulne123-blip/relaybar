# RelayBar 0.5.1 — Lean Scan validation

Prepared September 17, 2026. Version **0.5.1, build 10**, bundle ID `local.relaybar`. **Source repair package, not a verified installed Mac release.**

## User-reported blocker

The supplied live report identifies RelayBar 0.5.0, Accessibility granted, `com.google.Chrome`, page kind `sheets`, zero top-level/open-menu controls, 796 visited nodes, and `Accessibility scan limit reached; actions disabled.` This is the user's report, not a remotely captured measurement.

The old status collapses deadline, query budget, wide/failed child reads and structural bounds. It does not identify which specific condition fired on that Mac. This repair targets verified inefficiencies that reproduce that status and adds distinct diagnostics; it does not claim an exact live root cause has been measured.

## Exact source foundation

Input: `RelayBar_v0.5_Native_Sheets.zip`, **300480 bytes**.
SHA-256: `874077179fee63697d580a2313a2e36075a69fb75f08be7b2810add3df40b6ba`.
The input archive was not modified. The repair is not built from the extension-only 0.4 package, the separate Context Stack variant, or the 0.6 Pins branch.

## Results actually executed

| Check | Result | Boundary |
|---|---:|---|
| Swift XCTest | **223 passed, 0 failures** | 204 inherited plus 19 new policy/scan/budget tests on Linux |
| Actual adapter and engine bodies | **30 checks passed** | Only framework import lines changed; Foundation and AX C API service doubles supplied explicitly |
| Actual controller | **20 checks passed** | Workspace, permission and AX source service doubles |
| Native integration contracts | **18 passed** | Static source checks; budget/version expectations updated |
| Screenshot integration contracts | **14 passed** | Existing byte-level foundation pins retained |
| Repair/installer contracts | **12 passed** | Includes execution of extracted version gate, not execution of the Mac installer |
| Compiler-repair regressions | **16 passed** | Inherited actual synthetic compiler/repair cases |
| Swift source parsing | **14 production files passed** | Not macOS SDK typechecking/linking |
| Shell syntax | **8 files passed** | `bash -n`, not installing/signing an app |
| Info.plist | **Parsed** | 0.5.1 build 10, same bundle ID |

Actual receipts are in `Docs/Scan_Repair_0.5.1/`. The test harness retains byte-identical baseline engine/adapter files under `Tests/ScanRepair/Baseline/`, so the same synthetic trees can be run against both implementations.

## Failure reproductions against the actual baseline

**Synthetic tree with 800 generic groups:** the old engine/adapter exhausts its 3,500-query budget, reports 806 visited nodes and publishes zero actions with the same scan-limit status. The new engine/adapter completes at **1,926 query tokens**, 810 visited nodes and 809 metadata batches, finding two top-level menus and two open-menu items. These are fixture menus, not the user's real actions. Query counts represent adapter API calls under doubles, not a measurement of live IPC latency or internal browser work. The fixture is not a reconstruction of the user's 796-node tree.

**Synthetic 300-child wrapper:** the old adapter stops at its 256-child ceiling and publishes zero actions. The repair fetches the full child list in five bounded pages and reaches the menu controls. Short pages, changed child counts and duplicate handles are tested to fail closed.

**Large formatting-toolbar fixture:** a 4,097-child toolbar outside a menu is skipped before its children are fetched. Actual menu descendants are not skipped solely because they have a toolbar wrapper. Cell/text-bearing roles remain pruned before child/value reads.

## Safety retained and improved diagnostics

The 850ms deadline, 3,500-query limit, 900 nodes per traversal phase and depth 24 remain unchanged. Only the direct-child ceiling changes, to 4,096 with page size 64 and complete-list verification. Shape caching is cleared before each scan and pre-tap rescan. No partial action list is enabled after an incomplete or expired scan.

The actual adapter fixture checks batched reads, missing optional attributes, scalar fallback, cache invalidation, pagination, cancellation, deadline/query/node bounds, modal rejection, target changes, covered controls and last-moment permission revocation. The original action path still issues at most one AX action and does not retry uncertain delivery. Foreground switches and discovery execute nothing.

The report adds counts and fixed diagnostic phrases only; it does not log or export a workbook URL/title, cell content, script source, menu captions or screenshots. Source/privacy contracts verify the new report avoids URL and label fields.

## Unchanged foundation

The original Objective-C bridge, Touch Bar component renderer, build script, compiler-compatibility helper, screenshot presentation state machine, screenshot cache and screenshot watcher/copy engine are byte-identical to the baseline. `AppMain.swift` changes only release strings. `Install.command` changes its banner/guidance and adds a branch/version guard; it does not reset permissions or migrate/delete user data.

## Not verified here

**Apple macOS SDK typechecking; real Cocoa/ApplicationServices type bridging; compiling/linking/signing the app on a Mac; running Install.command on a Mac; approval continuity of the rebuilt ad-hoc application; native Accessibility IPC latency; live Chrome menu discovery; Google Sheets behavior and the user's actual script actions; physical Touch Bar rendering, clicks or screenshot coexistence.** No remote change was made to the user's Mac or spreadsheets.

The adapter harness compiles actual method bodies against explicit stand-ins, not Apple's C declarations or services. This catches portable Swift/control-flow regressions but does not establish macOS compatibility. A successful AX request is not verification of script completion. Browser versions and workbook accessibility structures may still expose a different limitation; use the expanded connection report rather than repeating a permission reset.

## Reproduce

```bash
swift test
python3 Tests/ScanRepair/native_adapter_harness.py
python3 Tests/NativeSheets/controller_harness.py
python3 Tests/NativeSheets/test_contracts.py
python3 Tests/AutoOpen/test_integration_contract.py
python3 Tests/ScanRepair/test_package_contracts.py
python3 Tests/BuildRepair/test_toolchain.py
swiftc -frontend -parse -swift-version 5 Sources/Core/*.swift Sources/Mac/*.swift
```

No browser extension or runtime dependency is added by this repair. The underlying browser/platform tree model is documented by Chromium at https://chromium.googlesource.com/chromium/src/+/main/docs/accessibility/overview.md. API entry points include Apple's `AXUIElementCopyMultipleAttributeValues`, `AXUIElementCopyAttributeValues` and `AXUIElementSetMessagingTimeout`; source use is not proof of live browser acceptance.

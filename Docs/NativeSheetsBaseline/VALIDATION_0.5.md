# RelayBar 0.5 — native Sheets validation receipt

Prepared September 17, 2026. **Extension-free source update, not a verified installed Mac release.** Built from the actual attached RelayBar v0.3 native archive; the extension-only v0.4 package is not a dependency. No installed app, browser, spreadsheet or Apps Script project was changed remotely.

## Results obtained in this run

| Check | Observed result | What this establishes |
|---|---|---|
| Portable Swift XCTest | **204 tests, zero failures** | 153 inherited tests plus 51 new native-menu policy/traversal/dispatch/confirmation tests on Linux |
| Actual controller with explicit service doubles | **20 assertions, zero failures** | Compiles and exercises the exact controller's asynchronous behavior using an explicitly substituted AX source, node type, workspace and permission provider |
| Native integration contracts | **18 tests passed** | Static source checks for gating, no extension routing, inline confirmation, privacy constraints and version metadata |
| Screenshot auto-open integration regression | **14 tests passed** | Existing source contracts and six pinned source hashes; version and the explicit native-onboarding enable path updated in the expectations |
| Compiler compatibility/repair regression | **16 tests passed** | Original compiler-repair harness, including actual synthetic duplicate-module compiler cases |
| Swift syntax parser | **14 Core/Mac files passed** | Swift 5 parsing, not macOS SDK typing or native linking |
| Shell syntax | **8 files passed** | `bash -n`; no Mac installer, signing, or actual Accessibility grant |
| Info.plist | **Valid, 0.5.0 build 7** | Bundle ID remains `local.relaybar` |
| Foundation comparison | **8 files byte-identical to v0.3** | Original bridge header/implementation, build/toolchain, Touch Bar component, screenshot presentation, cache and watcher/copy engine |

Test environment: Linux x86_64, Swift 6.2.1, Python 3.13.5. Exact compiler/platform information is in `SYNTAX_RESULTS_0.5.json`.

The 51 new XCTest cases use an explicit fake accessibility tree. They execute the same `NativeMenuEngine` and `NativeTapGate` used by the app: exact URL matching, focused-window/web-area routing, custom menu ordering, open submenus, disabled and missing metadata, grid/text/iframe pruning, ambiguous documents, dialogs, scan limits, stale focus/URL/element geometry, hit testing, uncertain actions without retry, confirmation expiry and cancellation. They do not call Apple's Accessibility services.

The controller harness uses the exact `NativeMenuController.swift` with its Cocoa import replaced by Foundation and explicit service doubles. It checks read-only observation, one-time preparation, late permission grant, inline confirmation, duplicate taps/confirmations, cancellation of queued work, rejected retired callbacks/revisions, and report privacy. The real `NativeAXSource` ApplicationServices adapter is not substituted into this Linux test and has only passed syntax parsing here.

The inherited 153 tests include old wire-model/mailbox policies that remain inert for foundation continuity. Passing those old tests is not evidence that the new native routing works on a Mac. No prior browser fixture screenshot or simulated Google response is presented as live acceptance evidence.

## Remaining checks — not executed

**Actual macOS SDK typechecking and app compilation; Objective-C/Swift native linkage; ad-hoc signing; running Install.command and the diagnostic commands on a Mac; native Accessibility authorization; browser accessibility-tree exposure and runtime flags; AX URL/menu/geometry/hit-test/action behavior; live Google Sheets and the user's Apps Script actions; Safari/Chrome/Edge/Brave/Chromium differences; physical Touch Bar layout, confirmation and screenshot coexistence.**

No installed version is inferred from earlier reports of a working RelayBar. This archive is not a precompiled, Apple-notarized or certified release. The original undocumented cross-app adapter remains opt-in and OFF after each app launch.

The adapter mirrors accessible **menus**, not every Apps Script function or canvas-rendered drawing button. A browser that does not expose the exact page URL or menu controls receives an unavailable state, not a guessed inventory. No browser extension, per-workbook script registration, sidebar, public script endpoint, remote-debugging server or injected JavaScript exists on this runtime path.

Target validation is best effort, not an atomic transaction with a web page. A successful native request is not proof that a script completed. A failed/uncertain native request is never automatically retried. Existing actions can still change data or send messages using their normal permissions; confirmation is enabled by default.

See `MAC_ACCEPTANCE_0.5.md` for the unexecuted device checklist. Start with a harmless existing menu action or a copied workbook. The in-app **Native connection report** contains permission, browser/page kind, status and counts, without URLs, sheet titles, cell contents or script source.

## Reproduce the executed checks

From the package root, with Swift and Python available:

```bash
swift test
python3 Tests/NativeSheets/controller_harness.py
python3 Tests/NativeSheets/test_contracts.py
python3 Tests/AutoOpen/test_integration_contract.py
python3 Tests/BuildRepair/test_toolchain.py
swiftc -frontend -parse -swift-version 5 Sources/Core/*.swift Sources/Mac/*.swift
```

The controller harness uses only the included sources, temporary files and installed Swift. No runtime dependencies or browser extensions are installed by these checks. Actual Mac-only diagnostics are in `Diagnostics/` and are not recorded as passes here.

## Receipts and provenance

`CORE_TEST_RESULTS_0.5.txt`, `CONTROLLER_FIXTURE_RESULTS_0.5.json`, `CONTROLLER_FIXTURE_RUN_0.5.txt`, `NATIVE_SOURCE_CONTRACTS_0.5.txt`, `AUTO_OPEN_REGRESSION_0.5.txt`, `BUILD_REPAIR_REGRESSION_0.5.txt`, `SYNTAX_RESULTS_0.5.json`, and `PROVENANCE_0.5.json` describe this run. `Docs/History/` contains earlier reports, not current test evidence. `SHA256SUMS.txt` covers the final package files except itself.

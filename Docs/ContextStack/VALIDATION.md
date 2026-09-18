# RelayBar 0.5 — Context Stack validation receipt

Prepared September 17, 2026. Environment: Linux x86_64, Swift 6.2.1, Node 22.16.0 and offline Chromium fixtures. **This is an implemented source update, not a Mac-compiled, installed, notarized or hardware-verified release.**

## Results actually obtained

| Check | Observed result | What it establishes |
|---|---|---|
| Portable Swift XCTest | **203 tests passed; zero failures** | All 153 inherited tests plus 50 Context Stack tests, running the production Core types and the injected production session/workspace coordinator |
| New native wiring contracts | **22 tests passed** | Source assertions for lifecycle/consent, no feature persistence/network, protected file hashes, real coordinator usage, all entry pages, sleep/termination, stale identities and exact output; not AppKit execution |
| Screenshot auto-open regression contracts | **14 tests passed** | Existing source-level regression checks, with release metadata expectations updated only |
| Compiler-repair regressions | **16 tests passed** | Original synthetic toolchain compatibility/repair cases; not a Mac compiler invocation |
| Automatic Sheets JavaScript | **81 tests passed** | Current, unchanged version 0.4 protocol/worker code under explicit Chrome API doubles |
| Automatic Sheets Chromium DOM fixtures | **53 assertions passed** | Actual adapter DOM interactions on synthetic Sheets menus in offline Chromium; not live Google Sheets or an installed extension |
| Automatic Sheets updater/rollback | **14 tests passed** | Script execution with explicit macOS command/filesystem doubles, including the new native 0.5.0 compatibility case; not changes to a user's browser |
| Swift parser | **Passed** | All Core and Mac Swift files parsed in Swift 5 language mode; **not macOS SDK typechecking** |
| Syntax and metadata | **Passed** | Shell and JavaScript parse checks; native 0.5.0/build 7 and browser 0.4.0 metadata/permissions checked |
| Foundation continuity | **9 native files and 6 extension files byte-identical** | Exact comparisons against both retrieved original source archives, recorded in PROVENANCE.json |

The 50 new Swift test methods cover opt-in baseline semantics, no reads while paused, counter/generation races, access-unavailable pause, private and file/multi-item markers, excluded foreground identities, exact Unicode/CRLF bytes, duplicate inclusion/order preservation, bounds without truncation/eviction, expiry/sleep-gap pauses, stable UUID/revision copying, full-packet fences, no feedback loop, failed writes, and independent retained project stacks. One randomized test checks 3,000 state transitions; these transitions are not counted as 3,000 additional test methods.

The DOM screenshot in `Evidence/menu-fixture.png` is inherited-adapter regression evidence from a synthetic page. It is **not a screenshot of Context Stack's native UI, a real workbook, or a physical Touch Bar**. Likewise, the old browser preview is not evidence for this feature.

## Explicitly not executed here

**macOS SDK typechecking, native app compilation/linking/signing, native installer execution, clipboard-permission behavior, AppKit review-panel layout, real NSPasteboard collection, the new native self-test, real app switching/focus behavior, browser native-host launch, extension installation, live Google Sheets controls, physical Touch Bar sizing/rendering/tapping, VoiceOver, or physical keyboard/touch acceptance.** No remote change was made to the user's Mac. Passing portable or source-contract tests does not establish these behaviors.

The new `Context_Stack_Test.command` builds on the Mac and invokes actual AppKit component checks using an isolated **named pasteboard**, not the user's General clipboard. It constructs the real native review hierarchy without displaying it and checks real Touch Bar item actions/stale controls. That self-test remains unexecuted here and does not prove physical hardware rendering even when it passes. `Screenshot_Test.command` remains available unchanged.

## Mac acceptance checklist

1. Disable the browser extension temporarily, save unfinished text, quit RelayBar, and run Install.command from the new extracted folder. Verify version 0.5.0 and the backup path. Re-enable the existing automatic Sheets extension without reinstalling it.
2. Run Context_Stack_Test.command and Screenshot_Test.command. Preserve their logs. A compiler or assertion failure is a failure, not evidence of successful installation.
3. Use synthetic text first. Start Collect from the stack page; verify explicit disclosure and that pre-existing clipboard text is not collected. Exercise any OS clipboard permission prompt; denial must not produce an endless retry loop. Try the manual-paste fallback.
4. Copy three distinct passages, a duplicate, text with indentation/CRLF/Unicode, an image and a file. Verify eligible copies appear once, unsupported items do not become bogus text clips, and the general clipboard is not changed merely by collection.
5. Review, exclude, reorder and remove clips. Tap an individual clip and paste into an unsent draft; compare full text. Copy Pack and confirm inclusion/order, then verify collection is paused and nothing was submitted.
6. Switch RelayBar projects and return. Stacks must remain separate and collection paused. Exercise Clear, the 20-clip limit, sleep/resume, the 15-minute stop, and Quit/relaunch (stacks empty). Clear must not erase the OS clipboard, screenshots, another project's stack or saved briefs/checkpoints.
7. Take a saved screenshot while the stack page is active. The existing screenshot auto-open should win, all five image slots should remain, and returning to Stack must preserve text. Test app/tab switching, physical bar width, normal native app bars, and ×/RB Hide recovery.
8. Verify existing automatic Sheets menus and default action confirmation still work. Do not add per-workbook AppsScript code or open the old RelayBar sidebar.

## Reproducible receipts

`SWIFT_TEST_RESULTS.txt`, `WIRING_TEST_RESULTS.txt`, `AUTO_OPEN_REGRESSION.txt`, `BUILD_REPAIR_REGRESSION.txt`, `AUTOMATIC_SHEETS_JS.txt`, `DOM_RUN.txt`, `AUTOMATIC_SHEETS_DOM.json`, `UPDATER_TEST_RESULTS.txt`, `SYNTAX_RESULTS.txt`, `PROVENANCE.json`, and the final root `SHA256SUMS.txt` accompany the source. Earlier versioned receipts are retained as historical evidence, not combined into this release's native test claim.

Portable tests: `swift test`. Static contracts: `python3 Tests/ContextStack/test_integration.py` and `python3 Tests/AutoOpen/test_integration_contract.py`. Toolchain fixtures: `python3 Tests/BuildRepair/test_toolchain.py`. Adapter tests: `node --test Tests/AppAware/protocol.test.cjs Tests/AppAware/worker.test.cjs`. Offline DOM: `python3 Tests/AppAware/automatic_browser_test.py` (requires a separately available Playwright/Chromium test environment). Updater fixtures: `python3 Automatic_Sheets_0.4/Tests/updater_test.py`. Syntax: `python3 Tests/AppAware/check_syntax.py`.

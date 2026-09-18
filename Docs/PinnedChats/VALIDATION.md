# RelayBar 0.6 — Validation receipt

Prepared September 17, 2026. Environment: Linux x86_64, Swift 6.2.1. **Implemented source update, not a verified installed Mac release.** Tests were run against the merged source containing Pins, Context Stack and Native Sheets.

## Executed results

| Area | Result | Boundary |
|---|---|---|
| Portable Swift XCTest | **344 passed, 0 failures** | 153 common baseline tests + 50 Context Stack + 51 Native Sheets + 90 Pins policy/navigation tests. Real portable code, not AppKit. |
| Pins controller fixture | **23 checks passed** | Exact PinnedChatsMac.swift controller compiled and run with explicit Cocoa/workspace/AX-reader doubles. Tests actual asynchronous controller flow, not actual Accessibility or the Mac SDK. |
| Native Sheets controller fixture | **20 checks passed** | Preserved actual native menu controller with explicit workspace/AX service doubles. |
| Pins wiring/source contracts | **41 passed** | Static assertions, not UI execution. Includes merged routes, cancellation, heading extraction, bounds and preserved Stack methods. |
| Context Stack wiring contracts | **22 passed** | Static checks with the deliberate retired browser host excluded and asserted absent. Current setup now checks native controls instead of old extension instructions. |
| Native Sheets source contracts | **18 passed** | Same controller/adapter/engine; metadata and Hide coexistence expectation updated for merge. |
| Screenshot auto-open contracts | **14 passed** | Native Sheets version of the inherited regression suite, with current version metadata. |
| Compiler-repair regressions | **16 passed** | Existing synthetic toolchain/error cases. Not a Mac app compilation. |
| Syntax and metadata | **36 checks passed** | Swift parser in Swift 5 mode; bash parsing; plist version/identity. Parsing is NOT Mac SDK typechecking. |
| Source continuity / packaging | See PROVENANCE.json and SHA256SUMS.txt | Exact input archive hashes, unchanged foundation/engine files, installer bits, ZIP integrity and inventory. |

Do not add these heterogeneous checks together and call the sum “native tests.” Historical 0.3/0.4 JavaScript and DOM receipts belong to a retired extension and are not evidence for this feature. Pre-merge test runs are not substituted for the final merged receipt.

## What the new tests cover

The 90 Pins policy checks exercise positive pin evidence, English heading and marker variants, headings with static-text children, original order and selected state, mixed pinned projects, strict private-chat URLs, host/credential/path rejection, native chat-only rows, repeated identities, hidden/disabled entries, no recents substitution, maximum counts/depth, three-per-page traversal, changed app/window/tab/provider/target, expired or non-finite clocks, unpinning, clear/cancellation and one-time ticket consumption.

The 23 actual-controller fixture checks exercise no eager collection, explicit start, actual slot construction, page movement, selected markers, compact widths, fresh rescan before one press, disabled controls while opening, old-button retirement, unpin/app-switch rejection, explicit provider-switch callback, queued-operation cancellation, late callback discard, uncertain action no-retry, unavailable status, termination clearing and view refresh callbacks. Cocoa and Accessibility dependencies are service doubles and are labelled in the harness.

The source checks verify no network/clipboard/JavaScript/keystroke paths in Pins; permission checks; bounded AX traversal; pruning of secure/editable/main nodes; metadata extraction; foreground checks before and after scan; exact native pointer checks before press; and screenshot/Stack/native-menu coexistence. They do not establish how current ChatGPT or Claude versions expose their actual accessibility trees.

Two early fixture failures exposed a marker-inside-link case and a section-container scope leak. They were corrected before the final suite. A later three-way merge check caught missing Context Stack handlers; those handlers were restored and all merged regression suites rerun. No failed intermediate receipt is represented as a final pass.

## Not executed here

**macOS SDK typechecking, app compilation, signing/notarization, Install.command on a Mac, Pinned_Chats_Test.command, Context_Stack_Test.command, real Accessibility permission prompts/tree exposure, installed ChatGPT or Claude navigation, browser/account switching with current live sidebars, physical Touch Bar rendering, VoiceOver, actual screenshot-to-UI transitions, and live native Sheets action execution.**

The controller fixture does not validate AXUIElement bridging or the real AppKit APIs. Native AX getters/action code was source-reviewed and parsed, not run on macOS. No user conversation titles, transcripts, workbook contents or actual pinned inventory were used. A current app may expose insufficient or differently labelled metadata; in that case the adapter deliberately reports unavailable rather than guessing a chat.

## Mac acceptance checklist

1. Save Stack content and drafts, quit the old app, then run Install.command from this package. Confirm the new app reports 0.6.0/build 9 and the previous app backup exists. Confirm no extension setup appears.
2. Enable native app controls and approve Accessibility. Start with harmless pinned chats in ChatGPT. Open its sidebar and expand Pinned. Tap Pins and compare titles/order with the sidebar. Existing projects must not appear as chats. Check the status/help action when metadata is absent.
3. Open each detected chat once. Confirm the intended conversation opens and no prompt, clipboard contents or message is altered. Check page arrows where enough pins exist. Long names must be distinguishable by ordinal/full help labels.
4. Repeat in Claude's Starred/Pinned list, including a starred project. Switch providers using the provider button. Test your configured desktop-app bindings and any browser actually used; these routes are conditional, not certified by the fixture suite.
5. Unpin/rename an item, switch tabs/windows/apps and change accounts before pressing an old button. Old or indistinguishable targets should be rejected or unavailable, not silently retargeted. Verify an unavailable/hidden sidebar gives status and Refresh restores after opening it.
6. While Pins is visible, save a screenshot. The existing five-thumbnail viewer should appear, copying only when a thumbnail is tapped. Return to Pins. Open Stack, verify retained clips, and confirm its explicit Collect/copy semantics are unchanged.
7. Open a test Google Sheet and verify the native menus/inline confirmation are still available with no extension. Start a confirmation, then open another RelayBar page; no pending action should execute. Return to the Sheet and choose a harmless action explicitly.
8. Hide RelayBar and quit/restart it. Confirm Pins no longer reads while closed, in-memory pins are not restored from disk, cross-app mode starts OFF, and your saved projects/screenshot cache remain. Test pause before private work. Restore the backup app if any live behavior is unsuitable.

## Reproduce portable checks

From this package root, run `swift test`; `python3 Tests/PinnedChats/controller_harness.py`; `python3 Tests/PinnedChats/test_wiring.py`; `python3 Tests/NativeSheets/controller_harness.py`; `python3 Tests/NativeSheets/test_contracts.py`; `python3 Tests/ContextStack/test_integration.py`; `python3 Tests/AutoOpen/test_integration_contract.py`; and `python3 Tests/BuildRepair/test_toolchain.py`.

The native component-construction command is **Pinned_Chats_Test.command** and must be run on a Mac. It performs no live assistant scan and does not replace the installed app.

## Receipts

The files in this directory include CORE_TEST_RESULTS.txt, PIN_CONTROLLER_RESULTS.txt, CONTROLLER_FIXTURE_RESULTS.json, NATIVE_MENU_CONTROLLER_RESULTS.txt, PIN_WIRING_RESULTS.txt, CONTEXT_STACK_RESULTS.txt, NATIVE_MENU_CONTRACTS.txt, SCREENSHOT_REGRESSION_RESULTS.txt, BUILD_REPAIR_RESULTS.txt, SYNTAX_RESULTS.json and PROVENANCE.json. Package SHA256SUMS.txt is generated after the source and these receipts are finalized.

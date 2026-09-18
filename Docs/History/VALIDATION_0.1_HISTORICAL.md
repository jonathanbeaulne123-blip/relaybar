# Validation receipt — RelayBar 0.1

Prepared 17 September 2026. Execution environment: Linux x86_64; Swift 6.2.1. No Mac was connected to this build session.

| Area | Actual result |
|---|---|
| Portable Swift core | **46 tests passed; 0 failures** |
| Core coverage | Input limits, prompt assembly, evidence boundaries, context heuristics, explicit routes, checkpoint serialization, local permissions, corrupt-file and symlink rejection |
| macOS Swift source syntax | **Passed parser checks**, using Swift 5 language mode |
| AppKit/Objective-C SDK typechecking | **Not run**; no macOS SDK in this environment |
| macOS compilation / local signature | **Not run**; Install.command performs these on the user's Mac |
| Shell scripts | **Passed bash syntax checks**; installation paths/actions not executed on macOS |
| Info.plist | Parsed and required identifier, executable and deployment target checked |
| Offline browser workbench | **21 interaction checks passed** in headless Chromium; no JavaScript exceptions |
| Browser source handling | Malicious-looking markup remained inert text; no injected image element |
| Browser layout | Desktop image inspected; 390-pixel viewport had no horizontal overflow |
| Browser-to-native checkpoint data | **Passed**: actual browser-exported checkpoint decoded and validated by the Swift core |
| Native panel visual layout | **Not run** |
| Accessibility / assistant routing | **Not run** |
| Physical Touch Bar / experimental overlay | **Not run** |

The browser HTML was loaded into a browser test page with `set_content`; the container's browser policy blocks direct `file://` navigation. This validates its DOM interactions, not that a given ChatGPT attachment preview permits scripts or file downloads. Open the standalone HTML in an ordinary browser for the intended preview workflow.

A browser test initially needed an explicit wait for asynchronous file import; the final checks include that wait. The final source also uses an explicit own-property check for action IDs when importing untrusted JSON. No test result here asserts that AppKit code compiled, the Mac installer completed, or a physical Touch Bar displayed anything.

Detailed receipts:
- CORE_TEST_RESULTS.txt
- SWIFT_PARSE_RESULTS.txt
- BROWSER_TEST_RESULTS.txt
- INTEROPERABILITY_RESULTS.txt

Re-run the portable tests with Test.command. Browser regression test source is in Tests/Browser/test_preview.py and needs an optional Playwright test environment; it is not a runtime dependency of RelayBar. Run Doctor.command and MAC_ACCEPTANCE.md on the actual Mac before promoting this prototype to a daily-use tool.

## Deliberate first-version boundaries

No API-driven intelligence, no automatic prompt submission, no app injection, no Keychain reads, no repository scan, no filesystem writes outside this tool's own local storage/build/install locations, no live usage claim, and no fake agent progress. The cross-app adapter is isolated, opt-in, runtime-checked, and off at every launch.

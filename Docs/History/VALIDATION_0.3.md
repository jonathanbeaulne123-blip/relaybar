# RelayBar 0.3 — Validation receipt

Prepared September 17, 2026. **Source update, not a verified installed Mac release.** This continues the actual mounted RelayBar 0.2.1 Auto Open archive; no user Mac or live spreadsheet was altered. See PROVENANCE_0.3.json for hashes and the exact foundation comparison.

## Results actually obtained

| Check | Observed result | Evidence boundary |
|---|---|---|
| Portable Swift XCTest | **153 tests, zero failures** | Original 101 plus 52 app-context/mailbox policy tests, executed on Linux |
| JavaScript tests | **73 tests, zero failures** | Protocol validation plus actual service-worker and .gs code under explicit Chrome/Google service doubles |
| Real Chromium sidebar DOM | **20 assertions passed; zero network requests** | Actual sidebar/content-script DOM behavior with mocked Google/Chrome APIs, not an installed extension or live Sheet |
| Screenshot auto-open wiring regression | **14 tests passed** | Source assertions; only version metadata and explicit Chromium allowlist expectations updated for this release |
| Inherited compiler-repair regressions | **16 tests passed** | Same repair test harness, including synthetic duplicate-module compiler cases |
| Swift parser | **Passed** | All Core/Mac sources parsed in Swift 5 mode; no macOS SDK typechecking |
| Native host Foundation check | **Passed with explicit NSWorkspace stub** | Foundation typing only; not AppKit or native host execution |
| Shell syntax | **9 files passed** | bash -n, not Mac installer execution |
| JavaScript / manifest syntax | **Passed** | Seven JS source/test files, .gs source, sidebar inline script, native plist and MV3 manifest/assets |
| Foundation continuity | **All 8 pinned files byte-identical** | Bridge header/implementation, build/toolchain, Touch Bar component, screenshot presentation/cache/watcher-copy code |

The .gs tests exercise drawing/image discovery, the explicit custom-menu registry, deduplication, worksheet/workbook binding, allowed function resolution, changed assignments, confirmation changes, no automatic execution, request replay refusal, lock/session handling, cache eviction, request limits, and refusing to return user function data. These are service doubles, not Google's runtime.

The browser worker tests exercise actual routing code with Chrome API doubles: iframe/extension identity, restricted origins, no page-triggered enabling, exact frame dispatch, focus loss, navigation clearing, disconnect, repeated request IDs, and persistent rejection of ambiguous simultaneous sidebars. The real Chromium DOM tests exercise connection consent, default confirmation, cancel, one-tap reviewed actions, duplicates, wrong workbook/token and disconnect. The two screenshots are labelled fixture evidence, not screenshots of the user's workbook or Touch Bar. The confirmation fixture was visually inspected.

Core tests cover typed receipt validation, staleness, ambiguous profiles, exact native app/tab/window/workbook/sidebar identity, command expiry, four-button paging through the supported inventory, private file permissions, no-follow reads, corruption, one-time consumption, and preserving screenshot priority through temporary browser-link loss. Actual hardware responsiveness is not inferred from these tests.

## Still untested

**macOS SDK compilation and signing; running Install.command or Set_Up_Sheets.command on a Mac; browser extension installation and native-messaging host launch; Google authentication/authorization; actual Apps Script V8 function resolution and iframe injection; the user's private functions/dialogs; physical Touch Bar rendering, app/tab switching and screenshot coexistence.** Chrome, Edge, Brave and Chromium adapters are included, but none were live-tested here. Safari/Firefox/Arc do not have this release's Sheets bridge.

The original private macOS cross-app adapter was not rewritten. A previous user report of a working older RelayBar is not validation of this update. Cross-app mode remains OFF on launch and must be explicitly enabled. A successful parse, mocked script call or browser fixture does not establish real-device completion.

The package does not contain the user's actual Apps Script project or a guessed list of their menu functions. Drawing/image discovery is implemented. Custom menu and unassigned macro functions need one-time explicit registration in the existing bound project. No script runs on an app switch. Unknown/discovered actions require confirmation by default. This does not sandbox the existing script's permissions or guarantee that it cannot partially fail after making changes.

## Reproduce the portable checks

From the package root, with Swift, Node and Python available:

```bash
swift test
node --test Tests/AppAware/*.test.cjs
python3 Tests/AutoOpen/test_integration_contract.py
python3 Tests/BuildRepair/test_toolchain.py
python3 Tests/AppAware/typecheck_host_foundation.py
python3 Tests/AppAware/check_syntax.py
```

The DOM test additionally requires Python Playwright and Chromium. It first uses an installed `chromium` executable, or Playwright's Chromium when available:

```bash
python3 Tests/AppAware/sidebar_browser_test.py
```

No runtime dependency installation is performed by the app package. Linux used Swift 6.2.1, Node 22.16.0 and installed Chromium for this receipt. `Test.command` retains the original portable Swift test entry point. `Doctor.command` and `Screenshot_Test.command` remain real-Mac checks to perform, not passes recorded here.

## Receipt files

CORE_TEST_RESULTS_0.3.txt, JS_TEST_RESULTS_0.3.txt, SIDEBAR_BROWSER_RESULTS_0.3.json, AUTO_OPEN_REGRESSION_RESULTS_0.3.txt, BUILD_REPAIR_TEST_RESULTS_0.3.txt, HOST_FOUNDATION_TYPECHECK_0.3.txt, SYNTAX_RESULTS_0.3.txt and PROVENANCE_0.3.json. Historical 0.1/0.2/0.2.1 reports are retained separately and are not this release's evidence. Use MAC_ACCEPTANCE_0.3.md for the uncompleted live-device checklist.

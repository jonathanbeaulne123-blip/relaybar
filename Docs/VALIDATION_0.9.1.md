# RelayBar 0.9.1 — Persistent Shell build-fix validation

Prepared September 17, 2026. Version **0.9.1, build 17**, bundle ID `local.relaybar`.

## Why this release exists

The user ran the original 0.9.0 installer on macOS 15.0 / arm64 with Apple Swift 6.0.3. Compilation reached `Sources/Mac/AppMain.swift` and stopped because `returnToRelayBar(showPanel:)` declared a Boolean local named `showPanel` and later evaluated `if showPanel { showPanel() }`; Swift resolved the second `showPanel` as the Boolean and reported `cannot call value of non-function type 'Bool'`. The installer stopped during compilation, before its install/replace stage.

0.9.1 keeps the external call label unchanged but renames the local binding to `shouldShowPanel`:

```swift
private func returnToRelayBar(showPanel shouldShowPanel: Bool) {
    ...
    if shouldShowPanel { showPanel() }
    ...
}
```

No Persistent Shell feature logic was intentionally changed beyond that compile fix and release/installer/recovery metadata.

## Results executed for 0.9.1

| Check | Result | Boundary |
|---|---:|---|
| Swift XCTest | **427 passed, 0 failures** | Portable Core tests on Linux. |
| Exact `returnToRelayBar` extracted-method typecheck | **Passed** | The exact corrected method is extracted from production `AppMain.swift`, embedded in a minimal Swift harness and typechecked. This proves the shadowing expression is fixed, not full AppKit linkage. |
| Persistent Shell contracts | **11 passed** | Includes a new regression that rejects `if showPanel { showPanel() }` and requires the external-label/internal-binding form. |
| Production Button Families adapter | **176 passed** | Explicit AppKit/feature doubles; includes persistent shell layout/app-pin/Mac-handoff behavior. |
| Button hierarchy guide | **43 passed** | Offline Chromium guide checks. |
| Button Families wiring | **21 passed** | Source/integration contracts. |
| Native Sheets controller | **24 passed** | Explicit AX/workspace doubles; includes Hearth Tools lazy menu cascade and verified dispatch policy. |
| Native Sheets contracts | **18 passed** | Source contracts. |
| Lean Scan/native adapter | **30 passed** | Exact engine/adapter bodies against AX service doubles. |
| Context Stack integration | **22 passed** | Source/integration contracts. |
| Pinned Chats controller | **23 passed** | Explicit doubles. |
| Pinned Chats wiring | **41 passed** | Source/integration contracts. |
| Screenshot auto-open contracts | **14 passed** | Screenshot priority/persistent-shell regressions. |
| Build/compiler-repair regression | **16 passed** | Existing duplicate-module compatibility harness. |
| Unified product contracts | **13 passed** | Confirms merged feature engines and no browser extension/Apps Script runtime. |
| Installer/scan package contracts | **12 passed** | Includes 0.9.0 → 0.9.1 lineage handling and downgrade refusal. |
| Permission recovery helper | **24 passed** | Targets only 0.9.1 build 17; explicit macOS-command doubles. |
| Browser preview | **21 passed** | Offline Chromium with zero reported JS exceptions. |
| Swift source parser | **Passed** | Swift 5 parser across production Core/Mac sources. |
| Shell syntax | **Passed** | `bash -n` over command/build scripts. |

Detailed receipts are under `Docs/BuildFix_0.9.1/`.

## Still not verified here

This environment is Linux, so it cannot rerun the complete macOS Cocoa/ApplicationServices link that failed on the user's Mac. The exact reported source error has been removed and the corrected production method separately typechecks, but the final acceptance test is running `Install.command` on the Mac. Existing Sendable/deprecation diagnostics seen in the user's 0.9.0 log were warnings under the package's explicit `-swift-version 5` build mode and were not the compile-stopping error.

The physical Touch Bar, login LaunchAgent, installed-app discovery, Accessibility continuity, Google Sheets live UI, and stock-macOS Touch Bar handoff remain real-device checks.

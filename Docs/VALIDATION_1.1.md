# RelayBar 1.1.0 — Claim Ledger validation

Prepared September 18, 2026. Version **1.1.0, build 21**, bundle ID `local.relaybar`.

Environment the checks below were executed in: macOS 15.0 (24A335), arm64,
Apple Swift 6.0.3 from `/Library/Developer/CommandLineTools`, macOS SDK 15.2.
Working tree baseline: commit `63487e7` plus a set of unrelated uncommitted
changes described under "Still not verified here".

## Why this file exists

1.1.0 adds a feature whose entire purpose is to refuse to overstate. The same
standard applies to its own validation: what follows separates what was *run*,
what it *proves*, and what it does **not**.

## Results executed for 1.1.0

| Check | Result | What it establishes |
|---|---:|---|
| Whole-tree Swift typecheck | **82 files, 0 errors** | Every Core and Mac source, plus the Objective-C bridge header, typechecks together under `-swift-version 5` with Cocoa, ApplicationServices, Carbon, ImageIO and CoreGraphics. |
| Native link of the app target | **Linked** | The full `Sources/Core` + `Sources/Mac` + the real `Sources/Bridge/NativeBridge.m` link into an executable for this machine (`arm64-apple-macosx12.0`, the deployment target `Scripts/build.sh` uses) with the shipped frameworks. A link failure is a compile failure; this is the strongest pre-install check available without running the installer. |
| `--claim-ledger-self-test` on that linked binary | **35 checks passed, 0 failed** | Real AppKit panel, Touch Bar slot and chip construction, real `NSPasteboard` behaviour on a named pasteboard, and the real controller's review/plan/audit paths. Boundary below. |
| Claim Ledger portable suites | **81 passed, 0 failed** | `ClaimExtractorTests` 30, `ClaimCheckerTests` 26, `ClaimReceiptTests` 17, `RehearsalWorktreeTests` 8. |
| Whole portable suite | **649 passed, 5 failed** | 24 of the 27 files in `Tests/RelayCoreTests` ran; exclusions and the five failures are attributed below. |
| Shell syntax | **Passed** | `bash -n` over every `*.command` and `Scripts/*.sh`. |
| `Info.plist` | **OK** | `plutil -lint` on the 1.1.0 / build 21 manifest. |

Receipts: `Docs/ClaimLedger_1.1/` (`CORE_SUITES.txt`, `WHOLE_SUITE.txt`,
`NATIVE_SELFTEST.txt`, `TYPECHECK.txt`, `LINK.txt`, `SHELL_SYNTAX.txt`,
`HARNESS.txt`).

### What the native self-test actually exercises

`Sources/Mac/ClaimLedgerNativeChecks.swift` builds a `ClaimLedgerController`
against a **named** pasteboard and a synthetic observation source (one file, one
commit, no Git repository, no declared command), then asserts:

* a review without a project root is refused and creates no ledger;
* a review builds a ledger and settles nothing;
* with no declared command, an execution claim stays `unverified` and says why;
* a file claim is verified from a local read and carries a 64-character SHA-256;
* a proposal is `notCheckable`;
* planning selects the declared command verbatim and plans a clean tree in place;
* the reply audit flags a restatement of an unsupported claim and flags nothing else;
* the receipt is exactly one pasteboard item, is marked as RelayBar output,
  contains its `COVERAGE` disclosure, and renders verdicts;
* the evidence chip and every Verify-page slot construct as real Touch Bar items
  within the 685pt budget (**estimated widths and gaps, not hardware spacing**);
* the panel is constructed without being shown and triggers no navigation;
* `NSPasteboard.general.changeCount` is unchanged — the general clipboard was
  never read or written.

Run it yourself on a Mac with `./Run_Self_Test.command claim-ledger`.

## How the portable suites were run, and why

`swift build` and `swift test` cannot run in this environment: the installed
Command Line Tools reject the SwiftPM manifest's imports before reaching any
source file (a duplicate module map in the CLT SDK — the same fault
`Scripts/toolchain.sh` documents and works around). `Scripts/build.sh` was also
not run, because it installs an app; these checks deliberately stop short of that.

Instead, `build/claims-check/` holds a build-time-only harness:

```
bash build/claims-check/run-tests.sh          # the four Claim Ledger suites
bash build/claims-check/run-all-suites.sh     # the whole portable suite
bash build/claims-check/typecheck.sh          # whole-tree typecheck
bash build/claims-check/build-selftest.sh     # native link
build/claims-check/selftest/RelayBar --claim-ledger-self-test
```

It copies `Sources/` into `build/`, compiles the **real** `Tests/RelayCoreTests`
sources against that copy using a portable stand-in for the subset of the XCTest
API they use, and runs them. `build/claims-check/sync.sh` additionally applies the
**copy-only** patches listed in `build/claims-check/patches.txt`, which exist only
to work around compile errors in unrelated in-flight work in the same tree.
**`Sources/` and `Tests/` are never written by the harness**, and nothing under
`build/` ships: it is git-ignored, along with the rest of the build output.

The limit that follows: the shim is not XCTest, and the copy is compiled without
`-O`, without codesigning and without a universal-binary pass. The shim was
extended (throwing `setUpWithError`/`tearDownWithError`, `XCTUnwrap`, floating
point `accuracy:`, `XCTAssertGreaterThanOrEqual`) until all 24 files compiled
unmodified.

## The five failures, attributed

All five are pre-existing mismatches between `Sources/Core` and its tests in
areas 1.1.0 does not touch, and they reproduce from committed baseline files:

* `NativeMenuTests.testUntrustedURLFormsFail`, `testTwoWebAreasFailClosed`,
  `testChangedTabEvenSameURLRefused`, `testChangedSelectionFocusRefused` — sheet
  URL classification and verified-click refusal policy (`SiteControls.swift`,
  which has unrelated uncommitted changes in this tree).
* `RealityTests.testFileChangesExtractTrackedAndUntrackedFiles` — ordering.
  `RealityDiff.files(in:)` sorts with `localizedStandardCompare` **at commit
  `63487e7`**, while the test still expects plain ordering. Nothing in 1.1.0
  touches `RealityDiff`.

Three test files were excluded because they no longer compile against the current
portable target — `AppSwitcherTests.swift`, `SiteControlsTests.swift`,
`TabContextRouterTests.swift` (symbols that currently live outside
`Sources/Core`, or a non-optional return expectation). They are excluded, not
patched and not deleted; every exclusion is printed by `run-all-suites.sh`.

One failure found during this exercise **was** attributable to 1.1.0 and is
fixed: the reply audit missed a claim restated inside a longer sentence
("the test suite passes, so I merged it"). `ClaimMatcher.similarity` now scores
the better of plain overlap and containment with a two-shared-word floor, and two
regression tests cover both the catch and the counterweight — one shared word is
not a repetition.

Because unrelated work is being edited in the same working tree, counts for
non-ledger suites can shift between runs. The Claim Ledger suites
(`CORE_SUITES.txt`) are stable, and the four of them plus the native self-test are
the checks that govern this release.

## Still not verified here

This environment can typecheck and link, but it cannot stand up the product:

* the installed `RelayBar.app` bundle, icon generation, ad-hoc codesigning and the
  deploy step of `Scripts/build.sh`;
* physical Touch Bar rendering and spacing, and how the one-slot evidence chip
  sits beside the shell controls on hardware;
* the login LaunchAgent in a real login session;
* a **real** declared command being executed, cancelled, or timed out;
* a **real** rehearsal: forking a worktree from a live dirty repository, running
  the declared command there, and discarding the worktree afterwards;
* `Run_Self_Test.command all` end to end on a Mac (its other suites need
  Accessibility permission and running applications);
* anything about the reader's own repository. A receipt describes the machine
  that produced it and one commit; nothing here verifies a claim about a project
  this environment never had.

The final acceptance test remains `Install.command` on a Mac, followed by
`RB → Verify → Review the draft as claims` on a real project and
`./Run_Self_Test.command claim-ledger`.

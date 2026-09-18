# RelayBar 0.2.1 validation receipt

Prepared September 17, 2026 from the actual supplied RelayBar_v0.2_Screenshot_Shelf.zip.
Environment: Linux x86_64, Swift 6.2.1. No user Mac or physical Touch Bar was available.

## Executed here

| Area | Observed result |
| --- | --- |
| Portable Swift engine, shelf and presentation policy | **101 tests passed, 0 failures**: 77 existing plus 24 new |
| Existing compiler-repair regression suite | **16 passed** |
| Static production-wiring/source contract checks | **14 passed**; these are not UI execution |
| Swift source parsing | All Core/Mac files parsed in Swift 5 language mode |
| Portable Core typechecking | Passed on Linux |
| Shell syntax | All commands and build/helper scripts passed bash parsing |
| Metadata | local.relaybar; version 0.2.1; build 4; minimum macOS 12 |
| Protected baseline files | Original Objective-C bridge, toolchain helper/build script, watcher/cache/copy engine byte-identical |
| Packaging | ZIP integrity, required files, installer executable bit, checksum inventory checked |

## What the new portable tests exercise

Capture while Tools is selected; repeated capture while the viewer is already open;
explicit reopen rather than cached presentation; disabled cross-app mode; ineligible
foreground app; deferred presentation on return; stable ordinary refreshes; a displaced
bar; cancelling with Tools, thumbnail selection, Hide and auto-open off; rapid capture
bursts and stale callback invalidation; manual Shots while auto-open is off; structural
layout changes; three finite recovery delays. The same policy is used in AppMain.swift.

The static checks verify production wiring, focus/clipboard exclusions on the new
capture paths, live foreground checks, opt-in gating, preserved allowlist, fresh-bar
responder rebinding and hashes of unchanged baseline components. Static checks do not
execute AppKit or prove OS behavior.

## Not executed here

**macOS SDK typechecking, app compilation, signing, installation, native ImageIO/file-
watcher/Touch Bar self-tests, physical Touch Bar visibility and image paste into apps.**
The current installed v0.2 build outcome was not supplied; this update does not prove
that installation succeeded. No remote change was made to the user's Mac.

The extended native `Screenshot_Test.command` adds fresh-bar/retired-control checks
and real watcher-event-to-presentation-policy checks. It uses synthetic files and a
named pasteboard only. It has NOT been run here. The manual test in START_HERE.md is
required for the actual automatic viewer, keyboard focus and physical Touch Bar.

The user previously confirmed a working physical Touch Bar/cross-app baseline. That
observation is not presented as validation of either v0.2 or this v0.2.1 update.

## Receipts

- CORE_TEST_RESULTS_0.2.1.txt
- BUILD_REPAIR_TEST_RESULTS_0.2.1.txt
- INTEGRATION_CONTRACT_RESULTS_0.2.1.txt
- SYNTAX_RESULTS_0.2.1.txt
- PROVENANCE_0.2.1.json
- ../SHA256SUMS.txt

All older versioned receipts remain historical. No browser mock is used as evidence
of native auto-opening or full-resolution paste.

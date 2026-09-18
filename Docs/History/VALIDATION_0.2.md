# RelayBar 0.2 validation receipt

Prepared September 17, 2026. Build environment: Linux x86_64, Swift 6.2.1. No user Mac or physical Touch Bar was available to execute this update here.

| Area | Result actually obtained |
|---|---|
| Existing portable Swift engine | 46 tests passed again |
| New portable Screenshot Shelf policy/storage | 31 tests passed |
| Total Swift XCTest suite | **77 tests; 0 failures** |
| Existing compiler-repair regressions | **16 passed**, including actual synthetic Swift/Clang duplicate-module failure and workaround success |
| Swift source parser | Passed for all Core/Mac sources, Swift 5 mode |
| Core typechecking | Passed on Linux |
| Shell syntax | Passed bash parsing for all commands and build/helper scripts |
| Info.plist | Parsed; version 0.2.0, bundle ID local.relaybar, target macOS 12 |
| Original Objective-C bridge and toolchain workaround | Byte-identical to supplied 0.1.1 archive |
| macOS SDK typechecking / application compilation / local signing | **Not run here** |
| New native ImageIO / file watcher / clipboard self-test | **Not run here**; execute Screenshot_Test.command on Mac |
| Actual physical thumbnail layout, cross-app updates and assistant paste | **Not run here**; requires user's Mac |

Portable tests cover exactly five entries, out-of-order arrivals, duplicate-event rejection, cache eviction, full stored-byte round trip, relaunch, clear watermarks, old-source suppression, source/unrelated-file preservation, private permissions, corruption, symlink refusal, failed commit behavior, format/name gating and incomplete-file settling. They do not decode images: the test byte payloads are explicitly opaque fixtures.

The source for the native self-test performs image decoding, clipboard format/size checks, real temporary-directory monitoring and native Touch Bar item construction on a Mac. It does not read the user's screenshot directory or General clipboard. Its existence is not reported as a test pass.

## Previously confirmed by the user

The earlier build launched, appeared on the physical Touch Bar, and then appeared in the ChatGPT workflow after cross-app setup. The exact installed build/version and full test output were not supplied. These observations validate a working baseline, not this new screenshot code.

## Receipts

- CORE_TEST_RESULTS_0.2.txt
- BUILD_REPAIR_TEST_RESULTS_0.2.txt
- SYNTAX_RESULTS_0.2.txt
- PROVENANCE_0.2.json

Prior 0.1/0.1.1 receipts and browser demos are historical. No browser mock was used as evidence of native screenshot collection or pasting.

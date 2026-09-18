# RelayBar 0.1.1 validation — 17 September 2026

## Scope

Targeted build-system correction following the supplied failed Mac install log.
This is a **repair candidate** until tested against that actual Mac SDK.
The original 0.1 receipt is preserved as `VALIDATION.md` and is historical.

| Check | Result in this session |
| --- | --- |
| Existing portable engine suite | 46 tests passed, 0 failures (Linux) |
| Build-repair suite | 16 tests passed, 0 failures (Linux) |
| Real Clang duplicate-module reproduction | Failed without local overlay, passed with it |
| Real Swift duplicate-module reproduction | Failed without local overlay, passed with it |
| Synthetic toolchain file hashes | Unchanged across both real-compiler tests |
| Preflight control flow | Mocked baseline/retry success and failure gates passed |
| Exact module-map validation | Additional declarations, changed headers, missing files and symlink maps refused |
| Shell scripts | Bash syntax checks passed; not executed on macOS |
| Swift source parser | Passed; not an AppKit SDK typecheck |
| Mac SDK / AppKit / Objective-C SDK typechecking | NOT RUN |
| Mac build, signing and installation | NOT RUN |
| Mac SwiftPM manifest/target flag forwarding | Implemented; Mac execution NOT RUN |
| Native permissions, app routing, actual Touch Bar | NOT RUN |
| Browser preview | Unchanged; historical 0.1 browser checks were not rerun for this build-only change |

The Swift/Clang reproduction uses isolated artificial module files, not Apple's
SDK. The mocked gate tests validate script control flow, not a Mac compiler.
No actual macOS or hardware result is implied by the passing tests.

## Re-run

- `Test.command`: existing Swift core tests. On Mac it first checks the toolchain.
- `python3 Tests/BuildRepair/test_toolchain.py`: optional developer regression suite;
  Python is not required to build or run RelayBar.
- `Toolchain_Check.command`: compile-only Mac preflight, no app installation.
- `Install.command`: complete Mac build and install after preflight.
- `Doctor.command` plus `Docs/MAC_ACCEPTANCE.md`: subsequent native verification.

## Primary technical references used for the repair

- Clang argument reference: `-ivfsoverlay` gives the compiler an overlaid filesystem
  view. https://clang.llvm.org/docs/ClangCommandLineReference.html
- SwiftPM 6.2.1 source documents separate `-Xswiftc`, `-Xbuild-tools-swiftc` and
  legacy `-Xmanifest` forwarding. The test script detects which manifest option
  the installed compiler exposes instead of assuming the newest release.
  https://raw.githubusercontent.com/swiftlang/swift-package-manager/swift-6.2.1-RELEASE/Sources/CoreCommands/Options.swift
- Original failure evidence: user's supplied `Pasted text.txt` installation log.

These references support the compiler mechanisms, not a claim that Apple
endorses this workaround or that it already repaired the user's Mac.

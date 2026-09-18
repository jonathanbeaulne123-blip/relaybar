# RelayBar 0.1.1 — targeted compiler repair

## What the submitted log establishes

The first reported error is `redefinition of module 'SwiftBridging'`, with both
`usr/include/swift/module.modulemap` and `usr/include/swift/bridging.modulemap`
under the selected Apple Command Line Tools directory. It occurs while Swift
precompiles RelayBar's `NativeBridge.h`. The later Foundation, Cocoa and other
framework errors appear downstream of this failure. The installer exits before
installing the app. The log does not establish which tool update caused the
conflict, the complete compiler/SDK versions, or whether other source errors
will appear after this blocker is cleared.

## Use this package

1. Unzip into a **new folder**. The folder in this archive is `RelayBar_0.1.1`.
   Keep the old `RelayBar` folder and its installation log; do not merge folders.
2. Review the scripts, then double-click **Install.command inside RelayBar_0.1.1**.
   It performs the new compiler check automatically before building the app.
3. A successful install ends with `Installed: .../Applications/RelayBar.app`
   and opens RelayBar. Only then test the panel and physical Touch Bar.

When Finder refuses to open a downloaded command, inspect it first. In Terminal,
type `bash `, drag this new folder's **Install.command** into Terminal, and press
Return. Do not disable Gatekeeper or System Integrity Protection.

For a compiler check without app installation, use **Toolchain_Check.command**.
This writes local compiler probes/caches/logs but does not install or run RelayBar.

## What changed

- Swift, Clang and the SDK are resolved through the same selected Apple developer
  directory. An explicit `DEVELOPER_DIR` is respected for this process only;
  the script never runs `xcode-select --switch`. Inherited SDK/header overrides
  are ignored within the build process, not edited in your shell profile.
- A small Cocoa + actual Objective-C bridge probe runs before the full compile.
  A fresh, project-local module cache is used; no global cache is deleted.
- Only after the exact duplicate pair appears in the probe log does the helper
  inspect those two map files. Both must match the same narrow, single-module
  definition. Extra modules, unfamiliar contents, missing headers and symlinks
  are refused.
- For that verified pair, a compiler virtual-filesystem overlay gives the old
  `module.modulemap` an empty, local compile-only view. The real definition in
  `bridging.modulemap` is retained explicitly. **Neither Apple file is changed,
  removed, renamed or replaced.** This is our targeted workaround, not an
  Apple-issued repair of the underlying developer-tools installation.
- A second probe must pass with that view before the full app build proceeds.
  Unknown failures stop instead of being suppressed. The same flags are passed
  to the app, icon builder, and (on macOS) the SwiftPM test/manifest compilers.
- Toolchain versions, file hashes, baseline errors and retry errors are saved
  locally. Doctor can now perform the compiler check before an app exists.
- Application logic is unchanged; app version metadata is now 0.1.1. The browser
  preview is deliberately the original 0.1 workflow, not a new native test.

No paid software, model calls, API key, administrator password, developer-tool
removal, global developer-directory switch, or security bypass is part of this
repair. The installer does not edit your project briefs or checkpoints. An
existing installed RelayBar app is only replaced after a successful build and
signature check, and is backed up first.

## What success looks like

The compiler check prints either:

```
PASS: compiler probe without a workaround.
```

or:

```
PASS: compiler probe with the project-local compatibility view.
```

This only proves the small probe compiled. The full app must still compile,
link, be locally signed, install, launch, and pass native/hardware checks.
A probe PASS is **not** an installation or Touch Bar PASS.

## When it still stops

Do not repeatedly run the old installer or delete `/Library/Developer/CommandLineTools`.
Share the new `BuildLogs/install-*.log` and the environment/probe files identified
at the end of that log, under `build/runs/run.*/`. They include local paths and
version information, not chat contents. Review/redact personal paths before sharing.

A persistent duplicate-map failure with unfamiliar files, an SDK mismatch, or a
new app-source diagnostic needs a different correction. This package does not
pretend to repair every possible developer-tools problem. Keep existing Xcode
and Command Line Tools installations unchanged until the new logs establish
what is actually needed.

## Validation performed here

Linux x86_64, Swift 6.2.1 and Clang 17:

- 46 existing Swift core tests passed again, with zero failures.
- 16 build-repair checks passed: exact map matching, refusal of unrelated maps,
  missing files, symlinks and existing output; path escaping; probe/retry gates.
- Actual Swift and Clang compiler tests reproduce a duplicate `SwiftBridging`
  failure using artificial module files, then pass with the local overlay.
  SHA-256 checks confirm those artificial original toolchain files are unchanged.
- Shell syntax and Swift parser checks passed.

**Not performed:** macOS SDK typechecking, complete native Mac compilation,
Mac SwiftPM test execution, Apple local signing, app installation, Accessibility,
app launching, Touch Bar rendering or cross-app overlay testing. Those still
require your Mac. Bash syntax checks here ran on Linux Bash, not Mac Bash 3.2;
the scripts deliberately avoid newer Bash constructs.

Receipts: `Docs/BUILD_REPAIR_TEST_RESULTS.txt`, `Docs/CORE_TEST_RESULTS_0.1.1.txt`,
`Docs/REPAIR_SYNTAX_RESULTS.txt`, and `Docs/VALIDATION_0.1.1.md`.

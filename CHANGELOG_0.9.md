# RelayBar 0.9 — Persistent Shell changelog

## Added

- Persistent RelayBar Touch Bar shell enabled by default.
- Fixed right-side Chrome, Claude and ChatGPT app buttons plus far-right **** macOS button.
- App-button discovery/activation by bundle ID and configured assistant app path; missing apps render disabled.
- Explicit **macOS Touch Bar mode** that dismisses RelayBar and is not automatically reclaimed on ordinary foreground-app changes.
- **Return RelayBar Touch Bar**, **Pause Persistent Touch Bar**, and **Launch RelayBar at Login** menu controls.
- User-only login LaunchAgent at `~/Library/LaunchAgents/local.relaybar.login.plist`, enabled by default with an explicit persistent opt-out.
- Core `PersistentShellState` policy and Mac `PersistentShellMac` app/login helper.
- Flexible-space Touch Bar item so app pins stay grouped at the far right.
- Persistent-shell regression tests and production-family-adapter checks.

## Changed

- Cross-app presentation is no longer limited to only the old assistant/browser allowlist. RelayBar’s shell can remain present over ordinary foreground apps while the feature-specific scanners keep their own stricter allowlists.
- Screenshot auto-open replaces only the contextual region; fixed app pins and the macOS button remain.
- Old global Touch Bar **×** hide controls are removed from the family presentation. The far-right **** button is now the deliberate stock-Mac escape hatch.
- Existing “overlay” command language is now “Persistent shell / Pause shell”.
- Startup no longer requires re-enabling the cross-app bar every app launch. Native Sheets permission/detection remains independently opt-in as before.
- Installer version becomes **0.9.0 build 16** and accepts the published 0.8.0/0.8.1/0.8.2 lineage while refusing unknown/newer builds.
- `Fix_Access.command` recognizes exactly 0.9.0 build 16.

## Preserved

- Google Sheets/Hearth Tools Verified Click dispatch from 0.8.2.
- Menu Cascade, Lean Scan and adaptive menu bounds.
- Screenshot watcher/cache/copy/auto-open behavior.
- Button Families hierarchy, Context Stack, Pinned Chats, prompt/project/checkpoint features.
- No browser extension or per-spreadsheet Apps Script setup.

## Not claimed

The 0.9 source is not claimed to have been Mac-SDK compiled, installed, login-launched or physically Touch-Bar tested in the build environment. Portable tests and explicit doubles are evidence of code paths, not a substitute for the user's Mac acceptance test.

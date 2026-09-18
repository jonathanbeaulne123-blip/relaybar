# RelayBar 0.9.1 — Persistent Shell build fix

Prepared September 17, 2026.

## Fixed

- Mac compilation blocker in `AppMain.swift`: `returnToRelayBar(showPanel:)` used a Boolean local named `showPanel` and then attempted `showPanel()`, which Swift correctly resolved as trying to call the Boolean.
- The external method label remains `showPanel:` for all callers, but its internal local is now `shouldShowPanel`, so `showPanel()` resolves to the existing method.
- Release version is now **0.9.1 build 17** so this corrected package is distinguishable from the failed 0.9.0 build 16 archive.
- Permission-recovery helper now targets exactly 0.9.1 build 17.

## Unchanged

Persistent Shell layout and behavior, app pins, macOS handoff, login preference, Verified Click, Native Sheets scanning/menu cascade, Screenshot Shelf, Button Families, Context Stack and Pinned Chats are otherwise unchanged from 0.9.0.

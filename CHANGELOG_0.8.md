# RelayBar 0.8.0 (build 13) — Unified

- Consolidates Button Families, Context Stack, Pinned Chats, Screenshot Shelf/auto-open, prompting/checkpoints and Native Sheets into one installable source tree.
- Uses the 0.7 Button Families branch as the UI/product foundation; its Context Stack and Pinned Chats engines are byte-identical to the supplied standalone branches.
- Replaces the 0.7 Native Sheets 0.5.1 engine with the 0.5.2 Menu Cascade behavior while retaining the Lean Scan adapter/budgets.
- `Hearth Tools`/other custom menu triggers may navigate when Chrome omits `AXEnabled` but still exposes a valid native menu action; explicit false remains disabled.
- Adds a short, bounded post-menu expansion window so lazily created menu items exposed under generic Chromium group/list wrappers become Touch Bar actions.
- Makes app-aware mode actually enter Sheet controls when a Sheet/document becomes active, while preserving manual Back/Home access and screenshot interruption priority.
- Ships the previously proven app-specific Accessibility recovery flow as `Fix_Access.command`, updated for 0.8.0 build 13.
- Removes current-product dependence on browser extensions, Apps Script injection, sidebars or per-workbook configuration.
- Installer accepts the known 0.5.2 and 0.7 releases, backs up the prior app and refuses unknown/newer versions.

Source release. Mac SDK compilation, installation, live Sheets/Hearth Tools and physical Touch Bar behavior remain on-device acceptance checks.

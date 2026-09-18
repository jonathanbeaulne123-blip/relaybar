# RelayBar 0.8.1 (build 14) — Large-Sheet menu repair

This is a targeted update to the unified 0.8 product. It does not add a browser extension, Apps Script integration, or per-spreadsheet setup.

## Changed
- Keeps the browser/document identity traversal at the existing **900-node** cap.
- Raises only the Google Sheets menu-discovery phase to **1,600 nodes** after a real Chrome/Sheets report showed the old 900-node phase cap was being reached with substantial time remaining.
- Raises the total per-scan Accessibility query budget from **3,500 to 5,000**. The existing **850 ms deadline**, depth 24, 4,096-child safety bound, complete-or-disabled publication, foreground/document revalidation and single-action/no-retry dispatch rules remain.
- Connection report now prints the dedicated Sheet menu node budget and identifies the Native Sheets engine as **0.5.3 · Adaptive Bounds**.
- Retargets the bundled Accessibility recovery helper to **0.8.1 build 14**.

## Reproduction added
A new 1,200-noise-node lazy-menu fixture fails on the exact 0.8.0 scanner with `node bound reached` and passes with 0.8.1, exposing both simulated Hearth child actions. The hard node bound is still covered by a larger >1,600-node fixture that must fail closed.

## Unchanged product areas
Button Families, Context Stack, Pinned Chats, Screenshot Shelf/auto-open, prompt tools, native AX adapter implementation, Objective-C cross-app bridge, compiler-repair path and no-extension architecture are unchanged except release metadata and updated tests/docs.

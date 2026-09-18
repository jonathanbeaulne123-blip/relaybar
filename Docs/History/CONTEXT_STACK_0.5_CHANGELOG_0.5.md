# RelayBar 0.5 — Context Stack

Added one native workflow: explicitly collect copied plain-text passages into a project-separated in-memory stack, then copy a reviewed, ordered handoff from the Touch Bar.

- Stack entry on AI, browser/Sheets and screenshot pages; three recent exact-text clip buttons, Pack, Collect/Pause and Review.
- Scrollable native review with full text, include/exclude, ordering, remove, clear and manual-paste fallback.
- Opt-in collection with explicit disclosure, 15-minute limit, sleep/session/interruption pauses, visible menu indicator and no automatic persistence.
- Bounded retained text, byte-exact duplicate suppression, stable-identity actions, generation/counter race checks, private-marker filters and limited obvious-secret heuristics.
- Native app version 0.5.0/build 7. The automatic Sheets extension remains byte-identical version 0.4.0. Existing automatic Sheets users do not reinstall or reconfigure that extension.
- First-time Sheets help now describes the automatic adapter, not the obsolete per-workbook script/sidebar method. Included extension-only updater explicitly accepts native 0.3.0 and 0.5.0; unknown versions still refuse to update.

No change to the original Objective-C overlay bridge, compiler repair helper/build script, native TouchBarDriver, screenshot watcher/cache/copy core, or screenshot auto-open policy. Cross-app mode remains off at launch. No Mac installation or live Google file mutation was performed here.

# Button Families — implementation and compatibility notes

## Source ownership

`Sources/Core/ButtonHierarchy.swift` owns the page taxonomy, titles, parent links, commands, screenshot return state, navigation generation, project paging and the portable native-Back decision. It performs no I/O and has no clipboard, app, AX or storage handle.

`Sources/Mac/AppMain.swift` adapts that catalog to existing `TouchBarDriver.Slot` values and an RB menu. `FamilyMenuItem.swift` carries explicit menu closures. The family adapter reuses the real clip, screenshot, pin and native-menu leaf closures. Existing revision/identity guards remain inside those closures; a new navigation-generation guard rejects taps delivered from retired family views. Suggested prompts are marked in fixed positions rather than substituted.

The existing renderer, screenshot watcher/cache/copy/presentation engine, Stack engine/controller, Pins engine/reader/controller, prompt engine, data models/store and Objective-C bridge are preserved from 0.6. The actual 0.5.1 NativeMenus and NativeAXSource bodies are brought forward byte-for-byte; its controller differs only in the displayed release/engine label. There is no attempt to make old browser-extension code active again.

## Tree versus temporary context

All normal pages have one canonical parent. Screenshots may have a temporary return destination representing an interruption; this is separate from the canonical tree. Nested screenshot options retain that return destination. Repeated captures preserve the first return. Explicit navigation elsewhere clears it. The existing ScreenshotPresentationState still decides whether/when to present or recover the bar; the navigation model only decides which page to return to.

The family page is not reset by ordinary native scan refreshes or copy checkmarks. Changing the underlying app invalidates native targets in their own engine. Unsupported Pins returns to Chats. Sheets controls live below Workspace, with Back prioritizing cancel → menu roots → Workspace. No browser key is sent for Back. App-aware settings still affect detection and overlay eligibility, not which unrelated family replaces the root.

Static child pages have at most five entries. Live projects use four choices plus pager/Manage; images preserve five slots; Pins preserves three titles and its controls. Width-budget tests include populated dynamic fixtures; these are point-sum checks, not physical hardware measurement. The original AppKit renderer remains unchanged.

## Safe source update

The full package is based on exact archives whose hashes are in PROVENANCE.json. The 0.5.1 scanner repair was retrieved during this task and compared against the actual 0.5 Native Sheets ancestor before merging. Its only other production AppMain changes were version strings; no 0.6 Pins/Stack functionality was dropped by replacing AppMain with the older branch.

The optional merger operates on source copies only. It knows exact 0.6 file ancestors and hashes, as well as exact already-published repaired scan files. It preserves unrelated source and extra metadata, rejects conflicts or newer/incomplete branches, writes a new copy only after validation, and never invokes that copy’s code. It does not merge an installed binary or guess at unshared Mac edits. A merge receipt is not proof of a Mac build. Run it from the original release folder; generated copy inventories/receipts belong to the copy.

The installer keeps the inherited build, ad-hoc signing verification, backup and restore path. Its new known-lineage guard accepts published older releases including 0.5.1 build 10 and 0.6 build 9; unknown/newer releases are refused. It does not reset Accessibility or delete settings. Local custom edits using unchanged version labels cannot be identified from an installed app; use the source-copy workflow instead of the ordinary installer.

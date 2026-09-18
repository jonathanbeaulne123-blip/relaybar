# Context Stack — design and integration notes

The goal is to remove repeated copy/paste and ad-hoc document assembly when handing a task between assistants. The core unit is an exact passage, not a rewritten AI summary. The user chooses when collection starts and exactly which excerpts make up the resulting handoff.

## Current production paths

`AppMain.swift` creates `ContextStackController` after the existing panel, connects it to the selected project and existing TouchBarDriver, adds Stack access to AI, Sheets/browser and screenshot layouts, and retains screenshot auto-open priority. A new screenshot may replace the visible stack page but never clears text. The native overlay eligibility policy is unchanged.

`ContextStackMac.swift` supplies the real NSPasteboard boundary, explicit consent/pause controls, 0.2-second common-run-loop timer, session/sleep suspension, menu indicator callbacks, eight-slot Touch Bar view, and scrollable native review panel. Timer ticks do not activate apps or open windows. Real Review and Collect consent are explicit UI actions. The entire review scrolls on shorter screens; full text preview and optional manual input have independent scroll areas.

`ContextStack.swift` owns admission, exact duplicate suppression, bounds, stable clip IDs, revisions, ordering, inclusion, textual packet composition, and the injected session/workspace coordinator. Production and tests use the same coordinator. It has no storage, network, activation, or keystroke APIs. Its pasteboard protocol is intentionally small enough to exercise payload/metadata read boundaries and reentrant change scenarios under tests.

## Safety and correctness

Initialisation and Start/Resume sample a change counter but never read an existing payload. While paused, the coordinator performs no metadata/payload queries. On a change it rejects excluded foreground identities and marked/multi-item/non-text content before reading text, verifies the counter before and after reading, and verifies a generation/project ticket before committing. Denied/nil reads pause rather than retrying continuously. Admission uses UTF-8 byte sizes and never partially adds a clip.

A stack-full condition pauses instead of oldest-item eviction: losing the initial requirements would defeat the feature. Duplicate detection compares UTF-8 bytes rather than Swift's canonical Unicode string equality. Packet text contains literal original excerpts in robust code fences (longer than every backtick run in that excerpt); headings are observational metadata. Fences are formatting, not a proof of prompt-injection immunity. Nothing is executed or interpreted as an instruction by RelayBar.

Touch Bar clip actions close over UUIDs, not mutable positions. Pack actions carry a revision in both the action and item key. The inherited driver retires and disables old controls on structural changes. Removed/stale clip or packet actions do not substitute new content. Single-clip output is exact plain text. Packet output writes one complete native item with an output marker; the session also advances its baseline, avoiding self-collection. A write failure reports failure and pauses without deleting the stack; the macOS clear/write operation is not a transactional guarantee to restore the previous OS clipboard on failure.

A workspace has at most 100 in-memory sessions, matching the configuration's project bound. Switching pauses both sides; it does not discard another project's clips or claim they belong to the new project. All sessions are cleared at termination. No new persistent preference is used: collection consent and data are scoped to the running app.

## Scope and compromises

No global event tap, Accessibility capture, screenshot OCR, cross-assistant send automation, clipboard daemon, cloud storage, or API key is introduced. The observed foreground app is not claimed to be the pasteboard owner. Marker/app/token filters are best-effort, not a password-security product. 0.2-second polling can miss rapid copies or clipboard transitions while the main loop is blocked. Explicit Paste clip and normal user-initiated paste into the review editor provide fallback inputs. Native macOS permission behavior and AppKit correctness require device validation; Linux parsing does not prove either.

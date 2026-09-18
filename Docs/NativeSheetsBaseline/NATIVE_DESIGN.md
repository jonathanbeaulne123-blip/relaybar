# Native adapter design

## Foundation and scope

Built from the exact attached `RelayBar_v0.3_App_Aware.zip`, not the extension-only v0.4 patch. The native entry points and live browser mailbox consumption have been replaced; BrowserExtension, AppsScript, Set_Up_Sheets.command and BrowserNativeHost.swift are absent. Legacy wire models/core tests remain inert for baseline continuity. No user's browser, sheet, script project or installed app was accessed here.

## Runtime code path

`NSWorkspace` activation notifications and the existing timer call `NativeMenuController.observe`. Scanning is enabled only when app-aware layouts, native menu detection and cross-app presentation are explicitly enabled. At most one read/job is live; cancelled old jobs cannot update the view.

`NativeAXSource` provides the real ApplicationServices adapter. AX node equality uses CFEqual/CFHash, not captions. It queries only the foreground browser's focused window. No title-based URL fallback or address-field keystroke exists. Optional browser accessibility preparation occurs once per granted process, using only advertised settable runtime attributes.

`NativeMenuEngine` in Sources/Core contains the actual discovery and dispatch policy used by the app and the portable tests. It requires one visible top-level web area, validates the exact URL, skips nested web areas/iframes and cell/text/scroll-area content, and finds menu containers. Dialogs, incomplete scans and ambiguous pages disable actions. Budget: 900 nodes per traversal, depth 24, up to 256 children per native read, at most 3,500 accessor operations, a 0.85-second read deadline and 0.08-second native read timeout. These are bounds, not measured browser latency. A single IPC that overruns its deadline can add its own timeout; there is no hard realtime guarantee.

Controls contain exact node identity, label, menu path, role, intended action, enabled state and geometry. Four per page are rendered through the original TouchBarDriver. Dynamic revisions retire earlier button bindings; equal heartbeats do not rebuild them. Open nested menu items are ordered before parent items. All discovered controls are reachable; there is no arbitrary 120-action truncation, but the traversal budget deliberately bounds inventory size.

`NativeTapGate` implements inline eight-second confirmation and a single in-flight reservation. Before dispatch, the engine obtains a new snapshot, checks foreground PID, focused window, web-area node, full URL including query/fragment, focus identity, target metadata and supported action. A native hit test at the target's centre must resolve to that same element or its descendant. The position is used to verify visibility, NOT to click. Immediately before dispatch, current identity, permission and cancellation are checked again.

Dispatch makes exactly one AXPress or AXShowMenu call. It never tries a coordinate click, keystroke or alternate action following failure. An unsuccessful AX return is reported as uncertain because it does not establish that the browser never acted. Every attempt invalidates the old control snapshot; subsequent discovery is read-only, not a retry.

## Limits that must not be represented as solved

AX is not an atomic transaction with a webpage; a control's script implementation can change without its caption/geometry changing. Page selection state is guarded only to the extent URL/focus identity expose it. A browser may omit or reuse elements, suppress controls, or omit supported actions. Strict hit testing can refuse a legitimate control rather than guess. A missing exact web URL is a hard routing failure. Canvas drawings and script-only functions are not enumerated.

This is not an OS-wide replacement for every application's native bar. The original assistant/cross-app implementation is retained; the new menu adapter targets a specific browser allowlist and Sheets edit URLs. Firefox, Arc and embedded browser views are not claimed supported. Native menu visibility, accessibility exposure, window/menu geometry, AX action handling, Google permissions and physical Touch Bar presentation require real-Mac acceptance tests.

## Confirmation and screenshot coexistence

Confirmation never opens a separate window or steals browser focus. New screenshots, Tools/Sheets return, Hide, explicit pause, permission failures, route/focus/control changes and stale revisions cancel pending interactions. The original screenshot page/recovery state machine is unchanged. Transient metadata loss does not itself dismiss a screenshot page; a confirmed different route or app does. An action already delivered to the browser cannot be cancelled retroactively.

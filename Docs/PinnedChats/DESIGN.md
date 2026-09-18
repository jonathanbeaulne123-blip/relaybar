# Pinned Chats architecture

## Data path

Explicit Pins entry → PinnedChatsController → serial PinnedChatsAXReader → an identified foreground sidebar metadata tree → PinnedChatPolicy → PinNavigationGate → the existing TouchBarDriver. A title tap captures a generation/ticket, rescans the live sidebar, consumes the one-use ticket, verifies native element/window/document identity again, and requests one AXPress. A successful AX request is not proof the target conversation loaded.

AppMain.swift is the integration point: no replacement window framework or independent browser app. It retains both branches' existing native controllers. Native Sheets and Pins have separate metadata readers and policy types; neither uses the old BrowserMailbox host. Context Stack and screenshots retain their distinct clipboard actions and lifecycles.

## Boundaries

The reader asks for the focused window and official browser document URL, refuses multiple web documents or sidebars, and prunes secure/editable fields and main landmarks. Sidebar/static metadata normalization supports labelled section containers, heading siblings and row-local non-action markers. The reader is bounded to 700 nodes, depth 24, 1.2 seconds of traversal budget with per-query timeouts. This is a practical best-effort budget, not an OS hard realtime deadline. Limited inventories are disabled, not silently treated as complete.

A project is not a conversation: URL routes must denote private chats, and native mixed-section rows need a chat-specific identity. A clearly chat-only section can support title-only native buttons. Duplicate identities are disabled. Headings that end a section stop pin scope; a container never pins arbitrary following siblings.

The controller reads only after entering Pins. It keeps metadata and target references in memory and refreshes about every two seconds. Pending callbacks are guarded by epochs and current foreground PID. UI tickets expire, are bound to exact session/inventory, and are consumed once. No input injection, paste, send, arbitrary URL launch or automatic retry exists on the chat action path.

Provider switching is a separate explicit action that opens the user's configured desktop application via AppMain's existing application resolver. Browsers are followed only after the user focuses their intended tab; no hidden account enumeration or cross-profile tab automation is claimed.

## Merge notes

The latest Native Sheets archive became available during development. The final AppMain is a resolved three-way merge of the actual 0.3 common foundation, the Context Stack + Pins branch and the newly retrieved Native Sheets 0.5 branch. The native menu engine/AX adapter/controller and the Context Stack engine/mac controller are copied unchanged; only integration, entry points, metadata and current docs/tests are adjusted. No active browser extension is reintroduced.

## Limitations

These are semantic Accessibility adapters, not stable vendor account APIs. Current native/web implementations, language, virtualization and hidden/collapsed sidebars can make pins unavailable. Live macOS compilation, real UI exposure, accessibility-reader behavior and physical Touch Bar usability remain acceptance tasks. Pin navigation uses best-effort revalidation, not an atomic transaction with the remote app.

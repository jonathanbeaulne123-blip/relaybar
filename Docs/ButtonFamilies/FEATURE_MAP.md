# Complete feature map

Generated from `Sources/Core/ButtonHierarchy.swift`, the catalog used by the native bar and RB menu. Dynamic surfaces are listed separately; no live user content is embedded.

| Page | Immediate children / explicit commands |
| --- | --- |
| Home | Prompting ›; Context ›; Chats ›; Workspace ›; Settings › |
| Home › Prompting | Next slice; Challenge; Handoff; More prompts ›; Draft › |
| Home › Prompting › More prompts | Build & review ›; Write & refine › |
| Home › Prompting › More prompts › Build & review | Explain; Diagnose; Add tests; UI review |
| Home › Prompting › More prompts › Write & refine | Tighten; Expand |
| Home › Prompting › Draft | Review draft; Copy draft; Copy + Open; Prefill Claude…; Save… |
| Home › Context | Capture ›; Context Stack ›; Screenshots › |
| Home › Context › Capture | Selection; Clipboard text; Edit reference; Clear session… |
| Home › Context › Context Stack | Collect; Recent clips ›; Review stack; Stack options › |
| Home › Context › Context Stack › Recent clips | Native dynamic controls; see below. |
| Home › Context › Context Stack › Stack options | Paste clip; Review stack; Clear stack… |
| Home › Context › Screenshots | Screenshot options › |
| Home › Context › Screenshots › Screenshot options | Save folder…; Collect images; Auto-open; Clipboard image; Clear shelf… |
| Home › Chats | Pinned chats ›; Destination ›; Open GPT; Open Claude; Pins status |
| Home › Chats › Pinned chats | Native dynamic controls; see below. |
| Home › Chats › Destination | ChatGPT; Claude |
| Home › Workspace | Projects ›; Workflow mode ›; Checkpoints ›; App controls › |
| Home › Workspace › Projects | Project options › |
| Home › Workspace › Projects › Project options | Edit brief…; New project… |
| Home › Workspace › Workflow mode | Native dynamic controls; see below. |
| Home › Workspace › Checkpoints | Save…; Load…; Local data |
| Home › Workspace › App controls | Native dynamic controls; see below. |
| Home › Settings | Layout & bar ›; Native controls ›; Assistant settings ›; Local data; About / privacy |
| Home › Settings › Layout & bar | App-aware; Cross-app bar…; Hide bar |
| Home › Settings › Native controls | Enable native…; Sheets detection; Ask before run; Connection report; Permission… |
| Home › Settings › Assistant settings | Follow assistant; Prefer desktop; GPT app…; Claude app… |

## Dynamic controls retained

- **Context Stack overview:** actual revision-bound Pack N plus Collect/Pause, Clips, Review and More. Pack copies and pauses, never pastes or sends.
- **Recent clips:** three actual stable-ID clip slots; Review opens the existing all-clips window. Review retains per-clip inclusion, reordering, removal, full packet preview, manual text input and explicit paste. Its native Touch Bar follows the same active family.
- **Screenshots:** all five original image/empty slots. A thumbnail copies its full-resolution cached image. More contains folder selection, watching, auto-open, clipboard-image import and clear.
- **Pinned chats:** the existing live Pins controller supplies three titles, current selection, earlier/later page, refresh, and other-provider activation. Setup/status remains reachable under Chats. Group rendering does not fabricate pins.
- **Projects:** four real project entries per page, page index / advance and Manage. The supported 100-project maximum remains fully reachable. Manage exposes edit brief and new project.
- **Workflow mode:** all four existing mode values, selected marker and no prompt generation on selection.
- **App controls / Sheets:** actual exposed roots/open actions, native page controls, Run/Cancel confirmation, connection-report or unavailable state. Existing native revision and target validation remain unchanged.

## Global and panel controls

Home and the five families are available from the RB menu. Open RelayBar and Quit remain top-level app commands; the active-app/collection status remains visible. Child pages add Back and Home, and all pages retain × Hide. The standard application Edit menu retains Undo, Cut, Copy, Paste and Select All. The panel retains project/destination/mode pickers, reference/task editing, explicit compose/action picker, full draft editing and explicit output buttons in labeled sections. Window controls and the existing global panel hotkey remain unchanged.

## Stable meanings

An arrow marks a family, not an executable child. Back does not hide; Hide does not mean “up one level.” Destination changes prompt targeting; opening an assistant activates its configured app and may update target only through the existing Follow assistant preference. Save/Load checkpoints belong to Workspace; Save also remains next to the finished draft as a contextual shortcut. Dangerous clearing and permission changes stay explicit; Clear session now has a Cancel-first confirmation.

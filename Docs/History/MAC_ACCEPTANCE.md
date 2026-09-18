# RelayBar — on-device acceptance checklist

Status at delivery: **NOT RUN ON A MAC.** Mark each row only after testing it on the actual device. Linux core tests do not establish macOS compilation or hardware behavior.

| Check | Expected result | On-device status |
|---|---|---|
| Clean native build | Install.command compiles Swift + Objective-C and verifies an ad-hoc signature | Not run |
| Architecture | Native binary matches the Mac, or universal build contains arm64 + x86_64 | Not run |
| Basic launch | RB appears in menu bar; panel opens; no permission prompt on initial launch | Not run |
| Panel layout | Text and buttons fit at 820-pixel minimum width; vertical scroll reaches all controls | Not run |
| Field editor | Copy/paste/select-all work in both text editors, task field, and project editor | Not run |
| Global shortcut | Control–Option–Command–Space opens panel from another app | Not run |
| Shortcut conflict | RB menu works even when shortcut registration fails | Not run |
| Native Touch Bar | Seven slots appear with RelayBar active, including while editing text | Not run |
| Capture without permission | No whole document read; offers clipboard or optional permission | Not run |
| Capture with permission | Reads only selected plain text; displays origin/time; no message sent | Not run |
| Unsupported selection | Clear failure and clipboard route; no simulated Copy or whole-view scraping | Not run |
| Secure text | Capture refuses a focused secure/password subrole | Not run |
| Oversized reference | Rejects >24,000-character capture without truncation; manual oversized text cannot compose | Not run |
| Smart actions | Error → Diagnose/Tests; code → Explain/Tests; prose → Tighten/Challenge | Not run |
| Manual modes | Build, Review, Writing override heuristic suggestions | Not run |
| Draft safety | Editing reference/task/brief or destination invalidates the previous draft | Not run |
| Desktop auto-follow | Recognized app changes target only when no draft exists | Not run |
| Copy + Open ChatGPT | Correct installed app or browser opens; intended packet is on clipboard; no paste/send | Not run |
| Copy + Open Claude | Same safety behavior; optional chosen .app path works | Not run |
| ChatGPT renamed app | Explicit Choose ChatGPT application override works | Not run |
| Claude prefill | Confirmation appears; new chat prefilled; no submit; oversized drafts rejected | Not run |
| Handoff | Destination switches; packet includes brief/reference/evidence caveat; no hidden history | Not run |
| Project isolation | Project switch clears reference, task, draft; saves selected project | Not run |
| Checkpoint persistence | Explicit save creates private local JSON; restores correct brief/source/target/draft | Not run |
| Corrupt config | Existing file preserved; session warns and uses temporary defaults | Not run |
| Overlay opt-in | Off at launch; confirmation explains undocumented API and browser scope | Not run |
| Overlay cross-app | ChatGPT/Claude/browser shows requested bar; other apps regain normal bar | Not run |
| Overlay recovery | ×, RB → Hide, shortcut, and Quit provide workable recovery | Not run |
| Overlay restart | Relaunch never silently restores overlay mode | Not run |
| Privacy | No network connection, credentials, continuous clipboard sampling, or unsolicited disk capture | Not run |
| Uninstall | App removal is confirmed; saved data preserved unless DELETE explicitly chosen | Not run |

Record the exact Mac model, macOS version, build log, assistant app names/versions, and whether any other Touch Bar utility is running. Do not include captured private content in a bug report.

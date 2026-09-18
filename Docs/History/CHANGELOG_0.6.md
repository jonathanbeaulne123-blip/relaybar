# RelayBar 0.6.0 — build 9

Added native Pinned Chats navigation: positive pin/star detection, three real titles per page, foreground assistant binding, explicit provider switch, bounded refresh, fresh-target checks and single AXPress dispatch. No browser extension, clipboard action or message send in this feature.

Merged the actual Context Stack 0.5 and Native Sheets 0.5 branches against their common 0.3 foundation. Both feature engines remain intact. Retired the former browser host, extension, Apps Script bundle and setup scripts from the active package; no extension is installed or needed. The installer does not delete pre-existing extension files or browser registrations from a user's Mac.

Preserved screenshot watcher/cache/copy, presentation policy, native Touch Bar renderer, Objective-C overlay bridge, build script and compiler repair helper. Pins/Stack page entry cancels native menu interactions, and screenshot arrival retains priority. Cross-app mode remains OFF on launch.

This is source requiring Mac validation, not an installed or hardware-verified release.

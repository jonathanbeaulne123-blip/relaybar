#!/bin/bash
# Fix_Permissions.command — Automates Accessibility & Automation permissions
# Signs RelayBar with a permanent designated requirement so permissions persist forever.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

APP="$HOME/Downloads/RelayBar.app"
if [[ ! -d "$APP" ]]; then
    APP="$HOME/Applications/RelayBar.app"
fi

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
if [[ ! -d "$APP" ]]; then
    printf 'RelayBar.app was not found in ~/Downloads or ~/Applications.\n'
    printf 'Building RelayBar now…\n'
    bash "$ROOT/Scripts/build.sh"
fi

printf '\n========================================================\n'
printf '  RELAYBAR PERMISSION AUTOMATOR & STABILIZER\n'
printf '========================================================\n\n'

printf '1. Closing any running RelayBar instances…\n'
/usr/bin/killall RelayBar 2>/dev/null || true
sleep 0.5

printf '2. Signing with permanent bundle identifier requirement…\n'
/usr/bin/codesign --force --sign - --requirements '=designated => identifier "local.relaybar"' --timestamp=none "$APP"
/usr/bin/codesign --verify --strict "$APP"
printf '   ✓ Signature verified: designated => identifier "local.relaybar"\n'
printf '   (macOS will retain your permissions permanently across rebuilds!)\n\n'

printf '3. Opening macOS System Settings to Accessibility & Automation…\n'
/usr/bin/open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility' || true
/usr/bin/open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Automation' || true

printf '\n========================================================\n'
printf 'WHAT TO DO NOW (ONE-TIME ONLY):\n'
printf '1. In System Settings → Accessibility:\n'
printf '   - Ensure RelayBar is toggled ON.\n'
printf '   - If you see an older RelayBar entry, toggle it OFF and back ON.\n'
printf '2. In System Settings → Automation:\n'
printf '   - Ensure RelayBar has Google Chrome checked.\n'
printf '========================================================\n\n'

printf 'Launching RelayBar from %s…\n' "$APP"
/usr/bin/open "$APP"

printf 'Done! Press Return to close this window. '
read -r _ || true

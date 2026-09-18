#!/bin/bash
set -euo pipefail
finish() { if [[ -t 0 ]]; then printf '\nPress Return to close. '; read -r _ || true; fi; }
trap finish EXIT
if [[ "$(uname -s)" != "Darwin" ]]; then echo 'Run this on your Mac.'; exit 2; fi
if pgrep -x RelayBar >/dev/null 2>&1; then echo 'Quit RelayBar from its RB menu, then run this again.'; exit 2; fi
FORCE=0
if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then FORCE=1; fi

APP="$HOME/Applications/RelayBar.app"
if [[ -e "$APP" ]]; then
  ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
  [[ "$ID" == "local.relaybar" ]] || { echo 'Refusing to remove an unrelated application.'; exit 2; fi
  if [[ $FORCE -eq 1 ]]; then
    rm -rf "$APP"; echo 'Application removed (--force).'
  else
    printf 'Remove RelayBar.app? Your saved projects, checkpoints and screenshot shelf will be kept. [y/N] '
    read -r answer
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then rm -rf "$APP"; echo 'Application removed.'; else echo 'Nothing removed.'; exit 0; fi
  fi
else echo 'No installed RelayBar.app was found.'; fi
LOGIN_PLIST="$HOME/Library/LaunchAgents/local.relaybar.login.plist"
if [[ -f "$LOGIN_PLIST" && ! -L "$LOGIN_PLIST" ]]; then
  rm -f "$LOGIN_PLIST"
  echo 'RelayBar login item removed.'
fi
DATA="$HOME/Library/Application Support/RelayBar"
if [[ -d "$DATA" ]]; then
  printf '\nAlso permanently delete RelayBar project briefs, checkpoints and cached screenshots? Type DELETE to confirm: '
  read -r answer
  if [[ "$answer" == "DELETE" ]]; then
    rm -rf "$DATA"
    /usr/bin/defaults delete local.relaybar screenshotShelf.folder >/dev/null 2>&1 || true
    /usr/bin/defaults delete local.relaybar screenshotShelf.enabled >/dev/null 2>&1 || true
    for key in nativeMenus.enabled nativeMenus.introduced nativeMenus.askActions persistentShell.enabled persistentShell.loginEnabled; do
      /usr/bin/defaults delete local.relaybar "$key" >/dev/null 2>&1 || true
    done
    echo 'Local RelayBar data and its screenshot/native-menu preferences deleted. Original screenshots were not removed.' 
  else echo 'Your local RelayBar data was preserved.'; fi
fi
echo 'No browser extension was installed by this release. The user login item was removed. Accessibility access can be revoked in System Settings.'
echo 'Build folders and any previous-version app backups remain where you placed them. No system-wide settings were changed.'

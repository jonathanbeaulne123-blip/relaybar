#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/BuildLogs"
LOG="$ROOT/BuildLogs/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1
finish() {
  result=$?
  if [[ $result -ne 0 ]]; then printf '\nInstallation stopped (exit %s). The log is %s\n' "$result" "$LOG"; fi
  if [[ -t 0 ]]; then printf '\nPress Return to close this window. '; read -r _ || true; fi
}
trap finish EXIT
printf 'RELAYBAR 0.9.1 — PERSISTENT SHELL / VERIFIED CLICK / BUTTON FAMILIES / PINS / CONTEXT / SCREENSHOTS / NATIVE SHEETS\n\n'
printf 'This script compiles the included source and installs only into ~/Applications.\n'
printf 'This is the consolidated source package; do not merge it into older RelayBar folders in Finder.\n'
printf 'It does not install paid tools, disable Gatekeeper, request an API key, or modify ChatGPT/Claude.\n\n'
if [[ "$(uname -s)" != "Darwin" ]]; then echo 'Run this installer on your Mac.'; exit 2; fi
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
  printf "Apple's free Command Line Tools are required. Start Apple's installer? [y/N] "
  read -r answer
  if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
    xcode-select --install || true
    echo 'Complete the Apple installer, then run Install.command again.'
  else
    echo 'No tools were installed. You can install them later with: xcode-select --install'
  fi
  exit 0
fi
if pgrep -x RelayBar >/dev/null 2>&1; then
  echo 'Quit RelayBar from its RB menu, then run this installer again. No running app was stopped.'
  exit 2
fi
bash "$ROOT/Scripts/build.sh"
# Re-check after compilation: do not replace an app opened during the build.
if pgrep -x RelayBar >/dev/null 2>&1; then
  echo 'Build completed. Quit the running RelayBar, then run this installer again.'
  exit 2
fi
DEST="$HOME/Applications"
mkdir -p "$DEST"
APP="$DEST/RelayBar.app"
if [[ -L "$APP" || -L "$DEST" ]]; then echo "Refusing a symlinked app or Applications directory."; exit 2; fi
if [[ -e "$APP" ]]; then
  IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$IDENTIFIER" != "local.relaybar" ]]; then echo "Refusing to replace an unrelated app at $APP"; exit 2; fi
  CURRENT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)
  CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || true)
  TARGET_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Resources/Info.plist")
  case "$CURRENT:$CURRENT_BUILD" in
    0.1.0:1|0.1.1:2|0.2.0:3|0.2.1:4|0.3.0:5|0.5.0:7|0.5.1:10|0.5.2:12|0.6.0:9|0.7.0:11) ;;
    0.8.0:13|0.8.1:14|0.8.2:15) ;;
    0.9.0:*)
      if [[ ! "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || [[ ! "$TARGET_BUILD" =~ ^[0-9]+$ ]] || (( 10#$CURRENT_BUILD > 10#$TARGET_BUILD )); then
        echo "Refusing to replace a newer or unrecognized build ($CURRENT build $CURRENT_BUILD)."; exit 2
      fi ;;
    0.9.1:*)
      if [[ ! "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || [[ ! "$TARGET_BUILD" =~ ^[0-9]+$ ]] || (( 10#$CURRENT_BUILD > 10#$TARGET_BUILD )); then
        echo "Refusing to replace a newer or unrecognized build ($CURRENT build $CURRENT_BUILD)."; exit 2
      fi ;;
    *) echo "Unrecognized or newer RelayBar ($CURRENT build $CURRENT_BUILD). Preserve your current app/source before installing."; exit 2 ;;
  esac
fi
STAGE="$(mktemp -d "$DEST/.RelayBar-stage.XXXXXX")"
/usr/bin/ditto "$ROOT/build/RelayBar.app" "$STAGE/RelayBar.app"
/usr/bin/codesign --verify --strict "$STAGE/RelayBar.app"
BACKUP=""
if [[ -e "$APP" ]]; then
  BACKUP="$DEST/RelayBar Previous $(date +%Y%m%d-%H%M%S)-$$.app"
  mv "$APP" "$BACKUP"
fi
if ! mv "$STAGE/RelayBar.app" "$APP"; then
  if [[ -n "$BACKUP" ]]; then mv "$BACKUP" "$APP"; fi
  echo 'Installation failed; the previous app was restored.'
  exit 1
fi
rmdir "$STAGE"
printf '\nInstalled: %s\n' "$APP"
if [[ -n "$BACKUP" ]]; then printf 'Previous version preserved: %s\n' "$BACKUP"; fi

# RelayBar 0.9 is meant to be available whenever the user logs in. Preserve an
# explicit user opt-out from the app menu; otherwise install a user-only login
# LaunchAgent that opens this exact ~/Applications copy without stealing focus.
LOGIN_PREF=$(/usr/bin/defaults read local.relaybar persistentShell.loginEnabled 2>/dev/null || printf '1')
if [[ "$LOGIN_PREF" != "0" ]]; then
  LOGIN_DIR="$HOME/Library/LaunchAgents"
  LOGIN_PLIST="$LOGIN_DIR/local.relaybar.login.plist"
  mkdir -p "$LOGIN_DIR"
  chmod 700 "$LOGIN_DIR" 2>/dev/null || true
  ESCAPED_APP=$(printf '%s' "$APP" | /usr/bin/sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
  cat > "$LOGIN_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.relaybar.login</string>
<key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-g</string><string>$ESCAPED_APP</string></array>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Interactive</string>
</dict></plist>
EOF
  chmod 600 "$LOGIN_PLIST"
  /usr/bin/plutil -lint "$LOGIN_PLIST" >/dev/null
  printf 'Launch at login: enabled (%s)\n' "$LOGIN_PLIST"
else
  printf 'Launch at login: preserved as disabled by your existing RelayBar preference.\n'
fi

printf '\nRelayBar now starts in persistent Touch Bar mode. Chrome, Claude and ChatGPT shortcuts stay at the right beside the  macOS button.\n'
printf 'Tap  to hand the entire strip back to macOS. RelayBar will not reclaim it on ordinary app switches; use the RB menu to return.\n'
printf 'Choose your screenshot save folder in RB → Context → Screenshots → Screenshot options. No Screen Recording permission is needed.\n'
printf 'For Google Sheets / Pins, choose RB → Settings → Native controls → Enable native… and grant Accessibility if asked.\n'
printf 'No browser extension, Apps Script edits, sidebar or per-spreadsheet setup is required.\n'
printf 'If macOS shows RelayBar enabled in Accessibility but the in-app report says not granted, quit RelayBar and run Fix_Access.command once.\n'
/usr/bin/open "$APP"
